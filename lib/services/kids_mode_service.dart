import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/kids_topics.dart';
import '../models/video.dart';

/// 儿童模式服务
///
/// 负责三件事：
/// 1. 保存/读取儿童模式开关、启用的主题、信任的 UP 主；
/// 2. 判断一个视频是否允许出现（白名单过滤）；
/// 3. 在主题内容中自动学习“可信 UP 主”。
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
    // 清掉旧的“信任 UP 主”数据（该机制已移除）
    await _prefs!.remove(_legacyTrustedUpsKey);
    await _prefs!.remove(_legacyAutoLearnKey);
    _loaded = true;
    _notify();
  }

  /// 儿童模式是否开启（默认开启，符合“只给孩子看固定内容”的定位）
  static bool get enabled => _prefs?.getBool(_enabledKey) ?? true;

  static Future<void> setEnabled(bool value) async {
    await init();
    await _prefs!.setBool(_enabledKey, value);
    _notify();
  }

  // ==================== 主题 ====================

  static Set<String> get _enabledTopicIds {
    final saved = _prefs?.getStringList(_topicsKey);
    if (saved == null) return defaultEnabledTopicIds.toSet();
    return saved.toSet();
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

  // ==================== 过滤 ====================

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
  /// 儿童模式关闭时一律放行；开启时**必须是标题命中某个已启用主题的关键词**。
  /// 没有任何按 UP 主放行的通道：白名单只由关键词决定，
  /// 也不会因为“看得多”而自动放宽。
  static bool isAllowed(Video video) {
    if (!enabled) return true;
    if (isGloballyBlocked(video)) return false;
    return topicOf(video) != null;
  }

  /// 批量过滤
  static List<Video> filter(Iterable<Video> videos) {
    if (!enabled) return List<Video>.from(videos);
    return videos.where(isAllowed).toList();
  }
}
