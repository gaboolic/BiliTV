import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import 'settings/settings_view.dart';

/// 用户 / 设置 Tab
///
/// 注意：未登录也直接进入设置页（登录入口移到了「账号」分类里）。
/// 否则没登录 bilibili 就进不去设置，儿童模式的主题就没法改。
class LoginTab extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final VoidCallback? onLoginSuccess;

  const LoginTab({super.key, this.sidebarFocusNode, this.onLoginSuccess});

  @override
  State<LoginTab> createState() => LoginTabState();
}

class LoginTabState extends State<LoginTab> {
  final GlobalKey<SettingsViewState> _settingsKey =
      GlobalKey<SettingsViewState>();

  /// 请求第一个分类标签的焦点（用于从侧边栏导航）
  void focusFirstCategory() {
    _settingsKey.currentState?.focusFirstCategory();
  }

  Future<void> _handleLogout() async {
    await AuthService.logout();
    if (mounted) setState(() {});
    widget.onLoginSuccess?.call();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsView(
      key: _settingsKey,
      sidebarFocusNode: widget.sidebarFocusNode,
      onLogout: _handleLogout,
    );
  }
}
