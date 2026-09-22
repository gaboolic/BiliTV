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
  static const String _trustedUpsKey = 'kids_mode_trusted_ups';
  static const String _autoLearnKey = 'kids_mode_auto_learn';

  static SharedPreferences? _prefs;
  static bool _loaded = false;

  /// 配置版本号，任何会改变“哪些内容可见”的改动都会 +1，UI 监听它来刷新
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// 信任名单版本号
  ///
  /// 单独一个通知源：自动学习 UP 主只影响设置页的数字显示，
  /// 不应该触发首页重建（否则浏览过程中会被强制拉回第一个主题）。
  static final ValueNotifier<int> trustRevision = ValueNotifier<int>(0);

  static void _notify() => revision.value++;

  /// 初始化（幂等）
  static Future<void> init() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();
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

  /// 是否自动把通过的 UP 主加入信任名单
  static bool get autoLearnUps => _prefs?.getBool(_autoLearnKey) ?? true;

  static Future<void> setAutoLearnUps(bool value) async {
    await init();
    await _prefs!.setBool(_autoLearnKey, value);
    _notify();
  }

  // ==================== 主题 ====================

  static Set<String> get _enabledTopicIds {
    final saved = _prefs?.getStringList(_topicsKey);
    if (saved == null) return defaultEnabledTopicIds.toSet();
    return saved.toSet();
  }

  static bool isTopicEnabled(String id) => _enabledTopicIds.contains(id);

  /// 当前启用的主题（按内置目录顺序）
  static List<KidsTopic> get topics {
    final ids = _enabledTopicIds;
    return kidsTopicCatalog.where((t) => ids.contains(t.id)).toList();
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

  // ==================== UP 主白名单 ====================

  static Set<int> get trustedUpMids {
    final saved = _prefs?.getStringList(_trustedUpsKey) ?? const <String>[];
    return saved.map(int.tryParse).whereType<int>().toSet();
  }

  static bool isTrustedUp(int mid) => mid > 0 && trustedUpMids.contains(mid);

  static Future<void> clearTrustedUps() async {
    await init();
    await _prefs!.remove(_trustedUpsKey);
    trustRevision.value++;
    _notify();
  }

  /// 从一批主题内容中学习可信 UP 主
  ///
  /// 只学习“标题命中主题关键词”的视频作者，避免把无关内容带进来。
  static void learnFrom(Iterable<Video> videos) {
    if (!enabled || !autoLearnUps) return;

    final current = trustedUpMids;
    final before = current.length;

    for (final video in videos) {
      if (video.ownerMid <= 0) continue;
      if (topicOf(video) == null) continue;
      current.add(video.ownerMid);
    }

    if (current.length == before) return;
    // 异步写盘，不阻塞 UI；只通知信任名单变化，不触发首页重建
    _prefs
        ?.setStringList(_trustedUpsKey, current.map((e) => e.toString()).toList())
        .then((_) => trustRevision.value++);
  }

  // ==================== 过滤 ====================

  /// 视频标题是否命中指定主题
  static bool matchesTopic(Video video, KidsTopic topic) {
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
  /// 儿童模式关闭时一律放行；开启时必须是命中主题关键词，
  /// 或者作者在信任 UP 主名单中。
  static bool isAllowed(Video video) {
    if (!enabled) return true;
    if (isTrustedUp(video.ownerMid)) return true;
    return topicOf(video) != null;
  }

  /// 批量过滤
  static List<Video> filter(Iterable<Video> videos) {
    if (!enabled) return List<Video>.from(videos);
    return videos.where(isAllowed).toList();
  }
}
