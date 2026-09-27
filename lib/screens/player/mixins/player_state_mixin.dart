import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import '../player_screen.dart';
import '../widgets/settings_panel.dart';
import '../../../models/video.dart';
import '../../../models/videoshot.dart';

/// 播放器状态 Mixin
/// 包含所有 State 变量
mixin PlayerStateMixin on State<PlayerScreen> {
  // 控制器
  VideoPlayerController? videoController;
  DanmakuController? danmakuController;

  // 插件跳过动作 (如空降助手)
  dynamic currentSkipAction; // SkipActionShowButton?

  // 加载状态
  bool isLoading = true;
  String? errorMessage;
  int? cid;
  int? aid; // 视频 aid (用于点赞/投币/收藏)

  // 完整视频信息 (从 API 获取，统一数据来源)
  Map<String, dynamic>? fullVideoInfo;

  // 在线观看人数
  String? onlineCount;
  Timer? onlineCountTimer;

  // 当前播放的音频 URL (DASH 模式)
  String? currentAudioUrl;

  // 播放器流订阅
  List<StreamSubscription> playerSubscriptions = [];

  // 弹幕设置
  bool danmakuEnabled = true;
  double danmakuOpacity = 0.6;
  double danmakuFontSize = 17.0;
  double danmakuArea = 0.25;
  double danmakuSpeed = 10.0;
  bool hideTopDanmaku = false;
  bool hideBottomDanmaku = false;

  // 播放设置
  double playbackSpeed = 1.0;
  final List<double> availableSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  // UI 控制
  bool showControls = true;

  /// 控制栏里当前选中的按钮：-1 表示「只是把菜单唤出来、还没选任何按钮」。
  ///
  /// 这个状态下按 OK 是暂停/继续（见 player_event_mixin），
  /// 用左右键才会真正选中某个按钮。
  int focusedButtonIndex = -1;
  bool showSettingsPanel = false;
  SettingsMenuType settingsMenuType = SettingsMenuType.main;
  Timer? hideTimer;
  Timer? progressReportTimer;
  int focusedSettingIndex = 0;

  // 分辨率
  List<Map<String, dynamic>> qualities = [];
  int currentQuality = 80;
  String currentCodec = ''; // 当前编解码器 (avc/hev/av01)

  // 双击返回
  DateTime? lastBackPressed;

  // 选集
  List<dynamic> episodes = [];
  bool showEpisodePanel = false;
  int focusedEpisodeIndex = 0;

  // 弹幕数据
  List<dynamic> danmakuList = [];
  int lastDanmakuIndex = 0;

  // 新面板
  bool showUpPanel = false;
  bool showRelatedPanel = false;
  bool showActionButtons = false;

  // 进度条聚焦模式
  bool isProgressBarFocused = false;
  Duration? previewPosition; // 拖动预览位置

  // 自动续播
  int? initialProgress; // 从历史记录恢复的进度

  // ==================== 播放列表（自动连播用）====================
  //
  // 列表就是用户当前在浏览的那一屏：首页某个主题的网格，或搜索结果。
  // 播完一个 / 按下键，都顺着它往下走。

  /// 当前视频在播放列表中的下标，找不到返回 -1
  int get currentPlaylistIndex {
    final list = widget.playlist;
    if (list == null || list.isEmpty) return -1;

    // 优先按 bvid 定位，这样调用方只需传列表，不必算下标
    final byBvid = list.indexWhere((v) => v.bvid == widget.video.bvid);
    if (byBvid >= 0) return byBvid;

    final i = widget.playlistIndex;
    return (i >= 0 && i < list.length) ? i : -1;
  }

  /// 播放列表里是否还有下一个
  bool get hasNextInPlaylist {
    final list = widget.playlist;
    final i = currentPlaylistIndex;
    return list != null && i >= 0 && i + 1 < list.length;
  }

  /// 播放列表里的下一个视频
  Video? get nextInPlaylist =>
      hasNextInPlaylist ? widget.playlist![currentPlaylistIndex + 1] : null;

  // 返回键处理标志 - 防止 handleGlobalKeyEvent 和 onPopInvoked 重复处理
  bool backKeyJustHandled = false;

  // 快进快退指示器
  bool showSeekIndicator = false;
  Timer? seekIndicatorTimer;

  // 快进预览模式 (雪碧图)
  VideoshotData? videoshotData;
  bool isSeekPreviewMode = false; // 当前是否处于预览快进模式
  int precachedSpriteIndex = -1; // 已预缓存的雪碧图最大索引 (滑动窗口)
  bool hasShownVideoshotFailToast = false; // 是否已显示过预览图失败提示
  bool hasHandledVideoComplete = false; // 防止重复触发视频完成回调

  // 获取编解码器简称
  String get _codecLabel {
    if (currentCodec.startsWith('av01')) {
      return 'AV1';
    }
    if (currentCodec.startsWith('hev') ||
        currentCodec.startsWith('hvc') ||
        currentCodec.startsWith('dvh')) {
      return 'H.265';
    }
    if (currentCodec.startsWith('avc')) {
      return 'H.264';
    }
    return '';
  }

  // 获取当前画质描述 (含编解码器)
  String get currentQualityDesc {
    String desc = '${currentQuality}P';
    for (var q in qualities) {
      if (q['qn'] == currentQuality) {
        desc = q['desc'] ?? desc;
        break;
      }
    }
    if (_codecLabel.isNotEmpty) {
      return '$desc ($_codecLabel)';
    }
    return desc;
  }
}
