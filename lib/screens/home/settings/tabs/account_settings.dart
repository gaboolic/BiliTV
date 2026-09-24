import 'package:flutter/material.dart';

import '../../../../services/auth_service.dart';
import '../../../../widgets/vip_avatar_badge.dart';
import '../../login/login_view.dart';
import '../widgets/setting_action_row.dart';

/// 账号设置
///
/// 未登录时显示扫码登录（这样未登录也能进入设置页，儿童模式不再被登录挡住），
/// 已登录时显示账号信息与退出登录。
class AccountSettings extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final VoidCallback? onMoveUp;
  final VoidCallback? onLogout;
  final VoidCallback? onChanged;

  const AccountSettings({
    super.key,
    this.sidebarFocusNode,
    this.onMoveUp,
    this.onLogout,
    this.onChanged,
  });

  @override
  State<AccountSettings> createState() => _AccountSettingsState();
}

class _AccountSettingsState extends State<AccountSettings> {
  @override
  Widget build(BuildContext context) {
    if (!AuthService.isLoggedIn) {
      return LoginView(
        sidebarFocusNode: widget.sidebarFocusNode,
        onLoginSuccess: () {
          if (mounted) setState(() {});
          widget.onChanged?.call();
        },
      );
    }

    final face = AuthService.face;
    final isVip = AuthService.isVip;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (face != null && face.isNotEmpty)
              VipAvatarBadge(
                size: 60,
                child: ClipOval(
                  child: Image.network(
                    face,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _defaultAvatar(),
                  ),
                ),
              )
            else
              _defaultAvatar(),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AuthService.uname ?? '已登录',
                    style: TextStyle(
                      color: isVip ? const Color(0xFFfb7299) : Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'UID: ${AuthService.mid ?? ""}${isVip ? "   ·   大会员" : ""}',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            '登录后可以看更高清晰度、同步观看历史与收藏。'
            '儿童模式本身不需要登录也能正常使用。',
            style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
          ),
        ),
        SettingActionRow(
          label: '退出登录',
          value: '',
          buttonLabel: '退出',
          isFirst: true,
          isLast: true,
          autofocus: true,
          sidebarFocusNode: widget.sidebarFocusNode,
          onMoveUp: widget.onMoveUp,
          onTap: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF2A2A2A),
                title: const Text('确认退出', style: TextStyle(color: Colors.white)),
                content: const Text(
                  '确定要退出登录吗？',
                  style: TextStyle(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消', style: TextStyle(color: Colors.white54)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('确认', style: TextStyle(color: Color(0xFFfb7299))),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              widget.onLogout?.call();
              if (mounted) setState(() {});
            }
          },
        ),
      ],
    );
  }

  Widget _defaultAvatar() {
    return Container(
      width: 60,
      height: 60,
      decoration: const BoxDecoration(
        color: Color(0xFF3A3A3A),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.person, size: 34, color: Colors.white54),
    );
  }
}
