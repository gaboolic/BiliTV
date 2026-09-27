import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 播放期间的屏幕常亮管理
///
/// 为什么不能直接用 WakelockPlus.enable/disable：
/// 播放器切下一个视频用的是 pushReplacement，**新页面的 initState 会先于
/// 旧页面的 dispose 执行**。于是旧页面的 disable() 会把新页面刚申请的常亮
/// 又清掉，从第二个视频开始屏幕就会被电视系统息屏。
/// 这里做引用计数，谁最后一个走谁才真正关闭。
///
/// 另外还会定期补一次申请：部分电视系统（小米等）会自己清掉这个标志。
class KeepAwake {
  KeepAwake._();

  static int _refs = 0;
  static Timer? _reassertTimer;

  /// 每隔一段时间重新申请一次，兜底那些会自行清除标志的电视系统
  static const Duration _reassertInterval = Duration(seconds: 60);

  /// 申请常亮（进入播放器时调用）
  static void acquire() {
    _refs++;
    _apply(true);
    _startReassert();
  }

  /// 释放常亮（退出播放器时调用）
  static void release() {
    if (_refs > 0) _refs--;
    if (_refs == 0) {
      _stopReassert();
      _apply(false);
    }
  }

  /// 重新申请一次（回到前台、视频开始播放时调用）
  static void reassert() {
    if (_refs > 0) _apply(true);
  }

  /// 当前是否处于常亮状态（排查问题用）
  static Future<bool> isEnabled() => WakelockPlus.enabled;

  static void _apply(bool enable) {
    final Future<void> action = enable
        ? WakelockPlus.enable()
        : WakelockPlus.disable();

    action
        .then((_) async {
          if (!enable) return;
          // 把真实状态打出来：电视上排查「为什么还是黑屏」时看这行
          final on = await WakelockPlus.enabled;
          debugPrint('🔆 KeepAwake: 常亮=$on (引用数=$_refs)');
        })
        .catchError((Object e) {
          debugPrint('⚠️ KeepAwake 设置失败: $e');
        });
  }

  static void _startReassert() {
    _reassertTimer ??= Timer.periodic(_reassertInterval, (_) {
      if (_refs > 0) _apply(true);
    });
  }

  static void _stopReassert() {
    _reassertTimer?.cancel();
    _reassertTimer = null;
  }
}
