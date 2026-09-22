import '../config/kids_topics.dart';
import '../models/video.dart';
import 'bilibili_api.dart';
import 'kids_mode_service.dart';

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
    final queries = topic.queries.isEmpty ? [topic.label] : topic.queries;
    final queryIndex = (page - 1) % queries.length;
    final subPage = ((page - 1) ~/ queries.length) + 1;

    final raw = await BilibiliApi.searchVideos(queries[queryIndex], page: subPage);

    final matched = <String, Video>{};
    for (final video in raw) {
      if (video.bvid.isEmpty) continue;
      if (!KidsModeService.matchesTopic(video, topic)) continue;
      matched[video.bvid] = video;
    }

    // 结果太少时，补充该主题里已经学到、被信任的 UP 主内容
    if (matched.length < 8) {
      for (final video in raw) {
        if (video.bvid.isEmpty) continue;
        if (matched.containsKey(video.bvid)) continue;
        if (!KidsModeService.isTrustedUp(video.ownerMid)) continue;
        matched[video.bvid] = video;
      }
    }

    final videos = matched.values.toList();
    KidsModeService.learnFrom(videos);
    return videos;
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

    void addAll(Iterable<Video> videos) {
      for (final video in videos) {
        if (video.bvid.isEmpty || seen.contains(video.bvid)) continue;
        if (!KidsModeService.isAllowed(video)) continue;
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
    if (result.length < 8) {
      final topic = KidsModeService.topicOf(current);
      if (topic != null) {
        for (final query in topic.queries.take(2)) {
          if (result.length >= limit) break;
          addAll(await BilibiliApi.searchVideos(query, page: 1));
        }
      }
    }

    KidsModeService.learnFrom(result);
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
    KidsModeService.learnFrom(videos);
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
