import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/kids_topics.dart';
import '../config/kids_up_owners.dart';
import '../models/video.dart';
import 'bilibili_api.dart';

/// 儿童模式服务
///
/// 负责三件事：
/// 1. 保存/读取儿童模式开关、启用的主题、自定义主题、指定 UP 主名单；
/// 2. 判断一个视频是否允许出现（白名单过滤）；
/// 3. 把「我的 UP 主」名单里的昵称解析成具体账号（uid）。
///
/// 全应用的内容入口（首页、搜索、播放器相关推荐、自动连播）都应经过
/// [filter] / [isAllowed]，只要儿童模式开启，任何未命中白名单的视频都不会出现。
class KidsModeService {
  KidsModeService._();

  static const String _enabledKey = 'kids_mode_enabled';
  static const String _topicsKey = 'kids_mode_topic_ids';
  static const String _customTopicsKey = 'kids_mode_custom_topics';

  /// 已废弃：早期版本会把命中的 UP 主自动加入信任名单，现在已完全去掉。
  /// 这里在初始化时清掉遗留数据，避免旧配置继续影响过滤结果。
  static const String _legacyTrustedUpsKey = 'kids_mode_trusted_ups';
  static const String _legacyAutoLearnKey = 'kids_mode_auto_learn';

  static SharedPreferences? _prefs;
  static bool _loaded = false;

  /// 配置版本号，任何会改变“哪些内容可见”的改动都会 +1，UI 监听它来刷新
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void _notify() => revision.value++;

  /// 初始化（幂等）
  static Future<void> init() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();
    // 清掉可能在 init 之前读到的空缓存，让自定义主题按真实 prefs 重新解析
    _customCache = null;
    _upOwnersCache = null;
    _knownTopicIdsCache = null;
    // 清掉旧的“信任 UP 主”数据（该机制已移除）
    await _prefs!.remove(_legacyTrustedUpsKey);
    await _prefs!.remove(_legacyAutoLearnKey);
    _loaded = true;
    _notify();
  }

  /// 仅测试用：清掉内部缓存，让每个用例都从干净的 prefs 开始
  @visibleForTesting
  static void resetForTest() {
    _prefs = null;
    _loaded = false;
    _customCache = null;
    _upOwnersCache = null;
    _knownTopicIdsCache = null;
    _curatedBvids.clear();
  }

  /// 儿童模式是否开启（默认开启，符合“只给孩子看固定内容”的定位）
  static bool get enabled => _prefs?.getBool(_enabledKey) ?? true;

  static Future<void> setEnabled(bool value) async {
    await init();
    await _prefs!.setBool(_enabledKey, value);
    _notify();
  }

  // ==================== 主题 ====================

  /// 记录“用户已经见过”的内置主题 id
  ///
  /// 版本升级后新加的内置主题要自动打开一次，
  /// 但用户手动关掉之后就不要再自动打开，所以要记下它已经被见过。
  /// 老版本还没有这个记录时按“空”处理：所有默认主题都补开一次。
  static const String _knownTopicIdsKey = 'kids_mode_known_topic_ids';

  static Set<String>? _knownTopicIdsCache;

  static Set<String> get _knownTopicIds {
    if (_knownTopicIdsCache != null) return _knownTopicIdsCache!;
    final raw = _prefs?.getStringList(_knownTopicIdsKey);
    _knownTopicIdsCache = raw?.toSet() ?? <String>{};
    return _knownTopicIdsCache!;
  }

  static void _saveKnownTopicIds(Set<String> ids) {
    _knownTopicIdsCache = Set<String>.from(ids);
    _prefs?.setStringList(_knownTopicIdsKey, ids.toList());
  }

  static Set<String> get _enabledTopicIds {
    final allIds = kidsTopicCatalog.map((t) => t.id).toSet();
    final saved = _prefs?.getStringList(_topicsKey);

    if (saved == null) {
      // 从来没配过：用默认名单，并把当前目录记成“都见过”
      _saveKnownTopicIds(allIds);
      return defaultEnabledTopicIds.toSet();
    }

    final result = saved.toSet();
    final known = _knownTopicIds;

    var changed = false;
    for (final topic in kidsTopicCatalog) {
      if (!known.contains(topic.id) &&
          topic.defaultEnabled &&
          !result.contains(topic.id)) {
        result.add(topic.id);
        changed = true;
      }
    }

    if (changed) {
      // 把自动补上的主题存回去，不然下次读取又会被当成“还没配置过”
      _prefs?.setStringList(_topicsKey, result.toList());
    }

    if (changed || !setEquals(known, allIds)) {
      _saveKnownTopicIds(allIds);
    }

    return result;
  }

  static bool isTopicEnabled(String id) => _enabledTopicIds.contains(id);

  /// 当前启用的主题 = 开启的内置主题 + 全部自定义主题
  ///
  /// 自定义主题是用户显式添加的，始终生效，想停用就直接删除。
  static List<KidsTopic> get topics {
    final ids = _enabledTopicIds;
    return [
      ...kidsTopicCatalog.where((t) => ids.contains(t.id)),
      ...customTopics,
    ];
  }

  static Future<void> setTopicEnabled(String id, bool value) async {
    await init();
    final current = _enabledTopicIds;
    if (value) {
      current.add(id);
    } else {
      current.remove(id);
    }
    await _prefs!.setStringList(_topicsKey, current.toList());
    _notify();
  }

  /// 一次性设置所有内置主题的启用状态（网页配置用，只通知一次避免首页反复重建）
  static Future<void> setPresetTopics(Set<String> enabledIds) async {
    await init();
    await _prefs!.setStringList(_topicsKey, enabledIds.toList());
    _notify();
  }

  // ==================== 自定义主题 ====================

  static List<KidsTopic>? _customCache;

  /// 用户自己添加的主题
  static List<KidsTopic> get customTopics {
    if (_customCache != null) return _customCache!;

    final raw = _prefs?.getStringList(_customTopicsKey) ?? const <String>[];
    final result = <KidsTopic>[];
    for (final item in raw) {
      try {
        final json = jsonDecode(item);
        if (json is Map<String, dynamic>) {
          final topic = KidsTopic.fromJson(json);
          if (topic.id.isNotEmpty && topic.label.isNotEmpty) result.add(topic);
        }
      } catch (e) {
        // 单条损坏就跳过，不影响其它主题
      }
    }
    _customCache = result;
    return result;
  }

  static Future<void> _saveCustomTopics(List<KidsTopic> list) async {
    await init();
    _customCache = list;
    await _prefs!.setStringList(
      _customTopicsKey,
      list.map((t) => jsonEncode(t.toJson())).toList(),
    );
    _notify();
  }

  /// 添加自定义主题
  ///
  /// [label] 主题名（同时作为默认搜索词和标题匹配词），
  /// [extraQueries] / [extraKeywords] 可选，用于补充搜索词或匹配词，
  /// [extraExcludes] 可选，标题命中这些词的视频不显示。
  /// 同名主题会直接覆盖，避免重复添加。
  static Future<KidsTopic> addCustomTopic({
    required String label,
    List<String> extraQueries = const [],
    List<String> extraKeywords = const [],
    List<String> extraExcludes = const [],
  }) async {
    await init();

    final name = label.trim();
    final queries = <String>{name, ...extraQueries.map((e) => e.trim())}
      ..removeWhere((e) => e.isEmpty);
    final keywords = <String>{name, ...extraKeywords.map((e) => e.trim())}
      ..removeWhere((e) => e.isEmpty);
    final excludes = <String>{...extraExcludes.map((e) => e.trim())}
      ..removeWhere((e) => e.isEmpty);

    final topic = KidsTopic(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      label: name,
      queries: queries.toList(),
      matchKeywords: keywords.toList(),
      excludeKeywords: excludes.toList(),
    );

    final list = List<KidsTopic>.from(customTopics)
      ..removeWhere((t) => t.label == name)
      ..add(topic);

    await _saveCustomTopics(list);
    return topic;
  }

  /// 删除自定义主题
  static Future<void> removeCustomTopic(String id) async {
    await init();
    final list = List<KidsTopic>.from(customTopics)
      ..removeWhere((t) => t.id == id);
    await _saveCustomTopics(list);
  }

  /// 整体替换自定义主题（网页配置用）
  static Future<void> setCustomTopics(List<KidsTopic> list) =>
      _saveCustomTopics(list);

  // ==================== 指定 UP 主 ====================

  static const String _upOwnersKey = 'kids_mode_up_owners';

  static List<KidsUpOwner>? _upOwnersCache;

  /// 「我的 UP 主」名单
  ///
  /// 这些 UP 主的投稿在儿童模式下直接放行（不受标题关键词限制），
  /// 同时也是首页「我的 UP 主」一行的内容来源。
  static List<KidsUpOwner> get upOwners {
    if (_upOwnersCache != null) return _upOwnersCache!;

    final raw = _prefs?.getStringList(_upOwnersKey);
    if (raw == null) {
      // 从来没配过：给出默认名单（怪逗逗、麦琪…）
      _upOwnersCache = List<KidsUpOwner>.from(defaultKidsUpOwners);
      return _upOwnersCache!;
    }

    final result = <KidsUpOwner>[];
    for (final item in raw) {
      try {
        final json = jsonDecode(item);
        if (json is Map<String, dynamic>) {
          final owner = KidsUpOwner.fromJson(json);
          if (owner.name.isNotEmpty) result.add(owner);
        }
      } catch (e) {
        // 单条损坏就跳过
      }
    }
    _upOwnersCache = result;
    return result;
  }

  /// 保存 UP 主名单
  static Future<void> setUpOwners(List<KidsUpOwner> list) async {
    await init();
    _upOwnersCache = List<KidsUpOwner>.from(list);
    await _prefs!.setStringList(
      _upOwnersKey,
      list.map((o) => jsonEncode(o.toJson())).toList(),
    );
    _notify();
  }

  /// 添加一个 UP 主
  ///
  /// [mid] 传 0 表示只知道昵称，运行时再按昵称找账号。
  static Future<void> addUpOwner({
    required String name,
    int mid = 0,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final list = List<KidsUpOwner>.from(upOwners);
    // 同一个账号不重复添加（按 uid 或昵称判断）
    list.removeWhere(
      (o) => (mid > 0 && o.mid == mid) || o.name == trimmed,
    );
    list.add(KidsUpOwner(name: trimmed, mid: mid));
    await setUpOwners(list);
  }

  /// 删除一个 UP 主
  static Future<void> removeUpOwner({String? name, int? mid}) async {
    final list = List<KidsUpOwner>.from(upOwners)
      ..removeWhere((o) {
        if (mid != null && mid > 0 && o.mid == mid) return true;
        if (name != null && o.name == name) return true;
        return false;
      });
    await setUpOwners(list);
  }

  /// 视频作者是不是名单里的 UP 主
  static bool isAllowedUp(Video video) {
    if (video.ownerName.isEmpty && video.ownerMid == 0) return false;

    for (final owner in upOwners) {
      if (video.ownerMid > 0 && owner.mid > 0) {
        if (video.ownerMid == owner.mid) return true;
        continue;
      }
      if (owner.name.isNotEmpty &&
          video.ownerName.toLowerCase() == owner.name.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  /// 按昵称把 UP 主解析成具体账号（uid），结果会缓存下来
  ///
  /// 规则：先找昵称完全相同且粉丝数上得去的账号，
  /// 找不到就取“昵称包含关键词”里粉丝最多的那个。
  static Future<KidsUpOwner> resolveUpOwner(KidsUpOwner owner) async {
    if (owner.mid > 0) return owner;

    final keyword = owner.name.trim();
    if (keyword.isEmpty) return owner;

    final candidates = await BilibiliApi.searchUsers(keyword);
    if (candidates.isEmpty) return owner;

    final lower = keyword.toLowerCase();
    final matched = candidates
        .where((u) => u.name.toLowerCase().contains(lower))
        .toList();
    final pool = matched.isEmpty ? candidates : matched;

    // 完全同名且粉丝数 >= 1000 的账号优先（避免选到同名小号）
    final exact = pool.where(
      (u) =>
          u.name.toLowerCase() == lower &&
          u.fans >= 1000,
    );
    final picked = exact.isNotEmpty
        ? exact.first
        : pool.reduce((a, b) => a.fans >= b.fans ? a : b);

    return KidsUpOwner(name: picked.name, mid: picked.mid);
  }

  /// 解析名单里的所有 UP 主，并把结果写回名单
  ///
  /// 解析过的账号下次就不用再搜了。
  static Future<List<KidsUpOwner>> resolveUpOwners() async {
    final list = List<KidsUpOwner>.from(upOwners);
    if (list.isEmpty) return list;

    final resolved = <KidsUpOwner>[];
    var changed = false;
    for (final owner in list) {
      final result = await resolveUpOwner(owner);
      resolved.add(result);
      if (result.mid != owner.mid) changed = true;
    }

    if (changed) {
      _upOwnersCache = List<KidsUpOwner>.from(resolved);
      await _prefs!.setStringList(
        _upOwnersKey,
        resolved.map((o) => jsonEncode(o.toJson())).toList(),
      );
    }
    return resolved;
  }

  // ==================== 过滤 ====================

  /// 已经“精选过”的视频（音乐排行榜、我的 UP 主频道拉回来的内容）
  ///
  /// 这些内容不是靠标题关键词命中的，但它们来自我们主动挑过的来源，
  /// 所以直接放行，避免刚拉回来就被白名单过滤掉。
  /// 记录时带上主题 id，主题被关掉后就不再放行。
  static final Map<String, String> _curatedBvids = <String, String>{};

  /// 登记精选内容
  static void allowVideos(String topicId, Iterable<Video> videos) {
    for (final video in videos) {
      if (video.bvid.isNotEmpty) _curatedBvids[video.bvid] = topicId;
    }
  }

  /// 是否是精选内容（对应的主题还开着才算）
  static bool isCurated(String bvid) {
    final topicId = _curatedBvids[bvid];
    if (topicId == null) return false;
    return _enabledTopicIds.contains(topicId);
  }

  /// 标题是否命中全局硬屏蔽词（投流漫剧/广告）
  static bool isGloballyBlocked(Video video) {
    final title = video.title.toLowerCase();
    for (final keyword in kidsGlobalBlockKeywords) {
      if (keyword.isEmpty) continue;
      if (title.contains(keyword.toLowerCase())) return true;
    }
    return false;
  }

  /// 标题是否命中该主题的排除词（含全局屏蔽词）
  static bool matchesExclude(Video video, KidsTopic topic) {
    if (isGloballyBlocked(video)) return true;
    final title = video.title.toLowerCase();
    for (final keyword in topic.excludeKeywords) {
      if (keyword.isEmpty) continue;
      if (title.contains(keyword.toLowerCase())) return true;
    }
    return false;
  }

  /// 视频标题是否命中指定主题
  ///
  /// 命中排除词的直接否决，避免“标题里确实有这个词但内容是漫剧/游戏/广告”。
  static bool matchesTopic(Video video, KidsTopic topic) {
    if (matchesExclude(video, topic)) return false;

    final title = video.title.toLowerCase();
    for (final keyword in topic.matchKeywords) {
      if (keyword.isEmpty) continue;
      if (title.contains(keyword.toLowerCase())) return true;
    }
    return false;
  }

  /// 视频命中的第一个主题，没有命中返回 null
  static KidsTopic? topicOf(Video video) {
    for (final topic in topics) {
      if (matchesTopic(video, topic)) return topic;
    }
    return null;
  }

  /// 视频是否允许出现
  ///
  /// 儿童模式关闭时一律放行；开启时必须满足下面任意一条：
  /// - 标题命中某个已启用主题的关键词；
  /// - 作者是「我的 UP 主」名单里的账号；
  /// - 属于音乐区的流行歌曲（且「流行音乐」主题开着）；
  /// - 是我们主动挑过的内容（音乐排行榜 / UP 主频道）。
  ///
  /// 全局硬屏蔽词（投流漫剧、广告）优先级最高，名单里的账号也一样挡。
  static bool isAllowed(Video video) {
    if (!enabled) return true;
    if (isGloballyBlocked(video)) return false;
    if (isAllowedUp(video)) return true;
    if (isMusicSong(video)) return true;
    if (isCurated(video.bvid)) return true;
    return topicOf(video) != null;
  }

  /// 是不是音乐区里“唱出来的歌”
  ///
  /// 只有「流行音乐」主题开着的时候才放行，
  /// 这样搜索「周杰伦」之类也能搜到歌，而不会把整个音乐区都放进来。
  static bool isMusicSong(Video video) {
    if (video.areaName.isEmpty) return false;
    if (!musicSongAreaNames.contains(video.areaName)) return false;
    return _enabledTopicIds.contains('pop_music');
  }

  /// 批量过滤
  static List<Video> filter(Iterable<Video> videos) {
    if (!enabled) return List<Video>.from(videos);
    return videos.where(isAllowed).toList();
  }
}
