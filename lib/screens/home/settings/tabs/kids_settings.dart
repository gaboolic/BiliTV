import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../config/kids_topics.dart';
import '../../../../services/bilibili_api.dart';
import '../../../../services/kids_mode_service.dart';
import '../../../../services/local_server.dart';
import '../../../../services/settings_service.dart';
import '../widgets/setting_action_row.dart';
import '../widgets/setting_toggle_row.dart';

/// 儿童模式设置页
///
/// 这里是整个“只看指定内容”功能的总开关：
/// - 打开后首页只显示下面勾选的主题，不再有推荐流；
/// - 搜索、播放器的“同主题视频”、自动连播都会被同一套白名单过滤；
/// - 动态和直播入口会从侧边栏隐藏。
class KidsSettings extends StatefulWidget {
  final VoidCallback? onMoveUp;
  final FocusNode? sidebarFocusNode;

  const KidsSettings({super.key, this.onMoveUp, this.sidebarFocusNode});

  @override
  State<KidsSettings> createState() => _KidsSettingsState();
}

class _KidsSettingsState extends State<KidsSettings> {
  @override
  void initState() {
    super.initState();
    KidsModeService.revision.addListener(_onChanged);
  }

  @override
  void dispose() {
    KidsModeService.revision.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<bool> _confirm(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
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
    return result ?? false;
  }

  /// 主题的副标题（不同来源的说法不一样）
  String _topicSubtitle(KidsTopic topic) {
    switch (topic.kind) {
      case KidsTopicKind.music:
        return '音乐区排行榜：热门流行歌曲';
      case KidsTopicKind.upOwners:
        return '内容来自下面的「我的 UP 主」名单';
      case KidsTopicKind.search:
        return '搜索词：${topic.queries.join(' / ')}';
    }
  }

  /// 添加 UP 主：先输入昵称搜账号，再从候选里挑一个
  Future<void> _addUpOwner() async {
    final controller = TextEditingController();

    final keyword = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('添加 UP 主', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          decoration: const InputDecoration(
            hintText: '输入 UP 主昵称',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFfb7299)),
            ),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('搜索', style: TextStyle(color: Color(0xFFfb7299))),
          ),
        ],
      ),
    );

    final name = keyword?.trim() ?? '';
    if (name.isEmpty || !mounted) return;

    // 搜索候选账号
    final users = await BilibiliApi.searchUsers(name);
    if (!mounted) return;

    if (users.isEmpty) {
      SettingsService.toast(context, '没有找到「$name」这个账号');
      return;
    }

    if (!mounted) return;
    final picked = await _pickUpOwner(users);
    if (picked == null || !mounted) return;

    await KidsModeService.addUpOwner(name: picked.name, mid: picked.mid);
    if (mounted) setState(() {});
  }

  /// 从候选账号里挑一个
  Future<BiliUser?> _pickUpOwner(List<BiliUser> users) {
    return showDialog<BiliUser>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('选择账号', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 420,
          height: 320,
          child: ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              return ListTile(
                focusColor: const Color(0xFFfb7299).withValues(alpha: 0.25),
                title: Text(
                  user.name,
                  style: const TextStyle(color: Colors.white, fontSize: 17),
                ),
                subtitle: Text(
                  'UID ${user.mid} · 粉丝 ${user.fansFormatted}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                onTap: () => Navigator.of(context).pop(user),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = KidsModeService.enabled;
    final topics = kidsTopicCatalog;
    final customTopics = KidsModeService.customTopics;
    final upOwners = KidsModeService.upOwners;
    final serverAddress = LocalServer.instance.address;
    final configUrl = serverAddress == null ? null : '$serverAddress/kids';

    final List<Widget> rows = [
      // 手机配置入口：电视遥控器打中文很痛苦，所以主推网页配置
      Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 二维码：手机直接扫，不用在遥控器上敲网址
            if (configUrl != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: QrImageView(
                  data: configUrl,
                  size: 170,
                  backgroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 18),
            ] else
              const Padding(
                padding: EdgeInsets.only(right: 14),
                child: Icon(Icons.wifi_off, color: Colors.orange, size: 48),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.smartphone,
                        color: Colors.lightBlueAccent,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        '用手机添加主题（推荐）',
                        style: TextStyle(
                          color: Colors.lightBlueAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (configUrl == null)
                    const Text(
                      '电视未联网，暂时无法使用网页配置',
                      style: TextStyle(color: Colors.orange, fontSize: 15),
                    )
                  else ...[
                    const Text(
                      '① 手机连上和电视同一个 Wi-Fi',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),
                    const Text(
                      '② 用相机 / 微信扫左边的二维码',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),
                    const Text(
                      '③ 在网页里勾选主题、输入新主题名',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      configUrl,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  const Text(
                    '改完立即生效，电视上不需要任何操作',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      // 说明
      Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFfb7299).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFfb7299).withValues(alpha: 0.4)),
        ),
        child: const Row(
          children: [
            Icon(Icons.child_care, color: Color(0xFFfb7299), size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '儿童模式开启后，首页只显示下面勾选的主题内容，不显示推荐流；'
                '搜索、播放器“同主题视频”、自动连播同样只允许白名单内容，'
                '动态和直播入口会被隐藏。',
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
              ),
            ),
          ],
        ),
      ),

      // 总开关
      SettingToggleRow(
        label: '儿童模式',
        subtitle: enabled ? '已开启：只播放白名单内容' : '已关闭：恢复原有推荐/分区首页',
        value: enabled,
        isFirst: true,
        onMoveUp: widget.onMoveUp,
        sidebarFocusNode: widget.sidebarFocusNode,
        onChanged: (value) async {
          await KidsModeService.setEnabled(value);
          if (mounted) setState(() {});
        },
      ),

      // ==================== 我的 UP 主 ====================
      Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Row(
          children: [
            const Icon(Icons.person_pin, color: Color(0xFFfb7299), size: 20),
            const SizedBox(width: 8),
            const Text(
              '我的 UP 主名单',
              style: TextStyle(
                color: Color(0xFFfb7299),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          '首页「我的UP主」一行只放这些账号的投稿；'
          '他们的视频在儿童模式下也会直接放行（不受标题关键词限制）。\n'
          '在电视上用遥控器输中文很麻烦，推荐用手机打开设置页里的网址来增删。',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ),

      ...upOwners.map((owner) {
        return SettingActionRow(
          label: owner.name,
          value: owner.mid > 0 ? 'UID ${owner.mid}' : '未找到账号（只按昵称匹配）',
          buttonLabel: '删除',
          sidebarFocusNode: widget.sidebarFocusNode,
          onTap: () async {
            if (await _confirm('删除 UP 主', '确定把「${owner.name}」移出名单吗？')) {
              await KidsModeService.removeUpOwner(name: owner.name);
              if (mounted) setState(() {});
            }
          },
        );
      }),

      SettingActionRow(
        label: '添加 UP 主',
        value: '按昵称搜索账号后从候选里挑一个',
        buttonLabel: '添加',
        sidebarFocusNode: widget.sidebarFocusNode,
        onTap: _addUpOwner,
      ),

      // 自定义主题（网页里添加的，这里可以删）
      ...customTopics.map((topic) {
        return SettingActionRow(
          label: '自定义：${topic.label}',
          value: '搜索词：${topic.queries.join(' / ')}',
          buttonLabel: '删除',
          sidebarFocusNode: widget.sidebarFocusNode,
          onTap: () async {
            if (await _confirm('删除主题', '确定删除「${topic.label}」吗？')) {
              await KidsModeService.removeCustomTopic(topic.id);
              if (mounted) setState(() {});
            }
          },
        );
      }),

      // 主题开关
      ...topics.map((topic) {
        return SettingToggleRow(
          label: topic.label,
          subtitle: _topicSubtitle(topic),
          value: KidsModeService.isTopicEnabled(topic.id),
          isLast: true,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await KidsModeService.setTopicEnabled(topic.id, value);
            if (mounted) setState(() {});
          },
        );
      }),
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: rows,
    );
  }
}
