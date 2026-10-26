import '../config/kids_topics.dart';
import '../config/kids_up_owners.dart';
import '../models/video.dart';
import 'bilibili_api.dart';
import 'kids_mode_service.dart';
import 'settings_service.dart';

/// 一次带过滤的搜索分页结果
class KidsSearchPage {
  /// 过滤后允许展示的视频
  final List<Video> videos;

  /// 实际请求到的最后一页（因为可能为了凑够结果连翻几页）
  final int lastPage;

  /// 原始结果是否满页（满页说明后面还有更多）
  final bool rawFull;

  const KidsSearchPage({
    required this.videos,
    required this.lastPage,
    required this.rawFull,
  });
}

/// 儿童模式内容装配
///
/// 所有内容都来自“主题关键词搜索”，并且经过 [KidsModeService] 白名单过滤，
/// 不使用哔哩哔哩的个性化推荐接口。
class KidsFeedService {
  KidsFeedService._();

  /// 单页搜索条数（与 video_api 中 pagesize 保持一致，用于判断是否还有下一页）
  static const int _pageSize = 20;

  /// 加载某个主题的一页内容
  ///
  /// 主题有多个搜索词时按页轮流使用，保证向右翻页能不断拿到新内容。
  static Future<List<Video>> loadTopicFeed(
    KidsTopic topic, {
    int page = 1,
  }) async {
    switch (topic.kind) {
      case KidsTopicKind.music:
        return _loadMusicFeed(topic, page: page);
      case KidsTopicKind.upOwners:
        return _loadUpOwnerFeed(page: page);
      case KidsTopicKind.search:
        return _loadSearchFeed(topic, page: page);
    }
  }

  /// 关键词搜索（普通主题）
  ///
  /// 排序方式跟搜索结果页共用同一个设置（默认综合排序，可在搜索页切换）。
  static Future<List<Video>> _loadSearchFeed(
    KidsTopic topic, {
    int page = 1,
  }) async {
    final queries = topic.queries.isEmpty ? [topic.label] : topic.queries;
    final queryIndex = (page - 1) % queries.length;
    final subPage = ((page - 1) ~/ queries.length) + 1;

    final raw = await BilibiliApi.searchVideos(
      queries[queryIndex],
      page: subPage,
      order: SettingsService.searchOrder,
    );

    final matched = <String, Video>{};
    for (final video in raw) {
      if (video.bvid.isEmpty) continue;
      if (!KidsModeService.matchesTopic(video, topic)) continue;
      matched[video.bvid] = video;
    }

    final videos = matched.values.toList();
    return videos;
  }

  /// 流行音乐：优先用音乐区排行榜，接口挂了再退回关键词搜索
  static Future<List<Video>> _loadMusicFeed(
    KidsTopic topic, {
    int page = 1,
  }) async {
    var videos = await BilibiliApi.getMusicRanking();

    if (videos.isEmpty) {
      // 排行榜拿不到内容时，用「流行歌曲 / 热歌推荐 / 新歌推荐」兜底
      final queries = topic.queries.isEmpty ? ['流行歌曲'] : topic.queries;
      final query = queries[(page - 1) % queries.length];
      videos = await BilibiliApi.searchVideos(query, page: page);
    } else if (videos.length > _pageSize) {
      // 排行榜一次就返回全部，用轮转的方式实现“向下翻页”
      final start = ((page - 1) * _pageSize) % videos.length;
      final end = start + _pageSize;
      videos = end <= videos.length
          ? videos.sublist(start, end)
          : [
              ...videos.sublist(start),
              ...videos.sublist(0, end - videos.length),
            ];
    }

    final result = videos.where((v) => v.bvid.isNotEmpty).toList();
    // 这些内容是主动挑过的，直接放行，别被标题白名单挡掉
    KidsModeService.allowVideos(topic.id, result);
    return result;
  }

  /// 我的 UP 主：把名单里每个 UP 主的投稿混在一起
  static Future<List<Video>> _loadUpOwnerFeed({int page = 1}) async {
    final owners = await KidsModeService.resolveUpOwners();
    if (owners.isEmpty) return [];

    const topicId = 'my_ups';
    final perOwner = 10;
    final lists = <List<Video>>[];

    for (final owner in owners) {
      var videos = <Video>[];

      if (owner.mid > 0) {
        videos = await BilibiliApi.getSpaceVideos(mid: owner.mid, page: page);
      }

      if (videos.isEmpty) {
        // 空间接口被风控 / 没数据时，退回“按名字搜索 + 只留本人投稿”
        final collected = <Video>[];
        for (var p = 1; p <= 3 && collected.length < perOwner; p++) {
          final raw = await BilibiliApi.searchVideos(owner.name, page: p);
          if (raw.isEmpty) break;
          for (final video in raw) {
            if (_isOwner(video, owner)) collected.add(video);
          }
        }
        videos = collected;
      }

      if (videos.isNotEmpty) {
        lists.add(videos.take(perOwner).toList());
      }
    }

    if (lists.isEmpty) return [];

    // 轮流取，保证一行里几个 UP 主都有
    final merged = <Video>[];
    final seen = <String>{};
    for (var i = 0; i < perOwner; i++) {
      for (final list in lists) {
        if (i >= list.length) continue;
        final video = list[i];
        if (video.bvid.isEmpty || seen.contains(video.bvid)) continue;
        seen.add(video.bvid);
        merged.add(video);
      }
    }

    // 同样是主动挑过的内容，直接放行
    KidsModeService.allowVideos(topicId, merged);
    return merged;
  }

  /// 判断一个视频是不是这个 UP 主的
  ///
  /// 有 UID 就按 UID 比（最准），没有才退回昵称比对。
  static bool _isOwner(Video video, KidsUpOwner owner) {
    if (owner.mid > 0 && video.ownerMid > 0) {
      return video.ownerMid == owner.mid;
    }
    return _isSameOwner(video.ownerName, owner.name);
  }

  /// 判断两个昵称是不是同一个 UP 主
  ///
  /// 昵称可能带前后缀（「怪逗逗」↔「怪逗逗小舞台」），
  /// 所以用“互相包含”来判断，太短的名字不参与，避免误伤。
  static bool _isSameOwner(String author, String target) {
    final a = author.trim().toLowerCase();
    final t = target.trim().toLowerCase();
    if (a.isEmpty || t.isEmpty) return false;
    if (a == t) return true;
    if (a.length < 2 || t.length < 2) return false;
    return a.contains(t) || t.contains(a);
  }

  /// 播放器的“更多视频”与自动连播
  ///
  /// 优先同一 UP 主的其它投稿，其次是官方相关推荐（过滤后），
  /// 最后用同主题搜索兜底。儿童模式下永远不会返回白名单之外的内容。
  static Future<List<Video>> relatedFor(Video current, {int limit = 20}) async {
    if (!KidsModeService.enabled) {
      return BilibiliApi.getRelatedVideos(current.bvid);
    }

    final seen = <String>{current.bvid};
    final result = <Video>[];

    // 当前视频属于哪个主题；用它的排除词继续约束后续推荐，
    // 避免看「盖房子」时从信任 UP 主那里冒出游戏/漫剧
    final currentTopic = KidsModeService.topicOf(current);

    void addAll(Iterable<Video> videos) {
      for (final video in videos) {
        if (video.bvid.isEmpty || seen.contains(video.bvid)) continue;
        if (!KidsModeService.isAllowed(video)) continue;
        if (currentTopic != null &&
            KidsModeService.matchesExclude(video, currentTopic)) {
          continue;
        }
        seen.add(video.bvid);
        result.add(video);
      }
    }

    // 1. 同一 UP 主的其它投稿
    if (current.ownerMid > 0) {
      addAll(await BilibiliApi.getSpaceVideos(mid: current.ownerMid, page: 1));
    }

    // 2. 官方相关推荐（逐个过滤）
    if (result.length < limit) {
      addAll(await BilibiliApi.getRelatedVideos(current.bvid));
    }

    // 3. 同主题搜索兜底
    if (result.length < 8 && currentTopic != null) {
      for (final query in currentTopic.queries.take(2)) {
        if (result.length >= limit) break;
        addAll(await BilibiliApi.searchVideos(query, page: 1));
      }
    }

    return result.take(limit).toList();
  }

  /// 搜索并过滤（儿童模式下会连翻几页，避免整页都是被过滤掉的内容）
  static Future<KidsSearchPage> searchFiltered(
    String query, {
    required int startPage,
    String order = 'totalrank',
    int maxPages = 3,
  }) async {
    if (!KidsModeService.enabled) {
      final raw = await BilibiliApi.searchVideos(
        query,
        page: startPage,
        order: order,
      );
      return KidsSearchPage(
        videos: raw,
        lastPage: startPage,
        rawFull: raw.length >= _pageSize,
      );
    }

    final collected = <String, Video>{};
    var lastPage = startPage;
    var rawFull = false;

    for (var i = 0; i < maxPages; i++) {
      final page = startPage + i;
      lastPage = page;

      final raw = await BilibiliApi.searchVideos(
        query,
        page: page,
        order: order,
      );
      rawFull = raw.length >= _pageSize;

      for (final video in raw) {
        if (video.bvid.isEmpty) continue;
        if (!KidsModeService.isAllowed(video)) continue;
        collected[video.bvid] = video;
      }

      // 已经凑到内容，或原始结果已经见底，就停手
      if (collected.isNotEmpty || !rawFull) break;
    }

    final videos = collected.values.toList();
    return KidsSearchPage(
      videos: videos,
      lastPage: lastPage,
      rawFull: rawFull,
    );
  }

  /// 启动页预加载：儿童模式下预加载第一个主题，否则走原来的推荐流
  static Future<List<Video>> preloadHomeFeed() async {
    if (KidsModeService.enabled) {
      final topics = KidsModeService.topics;
      if (topics.isEmpty) return [];
      return loadTopicFeed(topics.first, page: 1);
    }
    return BilibiliApi.getRecommendVideos(idx: 0);
  }
}
