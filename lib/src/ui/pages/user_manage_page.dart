import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/cookie_controller.dart';
import 'qr_import_page.dart';

final class UserManagePage extends StatefulWidget {
  const UserManagePage({super.key});

  @override
  State<UserManagePage> createState() => _UserManagePageState();
}

final class _UserManagePageState extends State<UserManagePage> {
  Future<void> _editCookieSlot(BuildContext context, String slotId) async {
    final cookie = context.read<CookieController>();
    final slot = cookie.slots.firstWhere((s) => s.id == slotId);
    final noteCtrl = TextEditingController(text: slot.note ?? '');
    final nav = Navigator.of(context);

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('编辑饼干槽'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: '备注名（可选）',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => nav.pop(false), child: const Text('取消')),
            FilledButton(
              onPressed: () => nav.pop(true),
              child: const Text('保存'),
            ),
          ],
        ),
      );

      if (ok == true) {
        await cookie.updateSlotMeta(
          slotId,
          note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
        );
      }
    } finally {
      noteCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cookie = context.watch<CookieController>();

    return Scaffold(
      appBar: AppBar(title: const Text('用户管理')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: Icon(cookie.hasCookie
                  ? Icons.verified_user_outlined
                  : Icons.no_accounts_outlined),
              title: Text(cookie.hasCookie ? '已导入饼干' : '未导入饼干'),
              subtitle:
                  Text(cookie.cookieName == null ? '（无饼干名）' : cookie.cookieName!),
            ),
          ),
          if (cookie.slots.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('饼干槽', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Card(
              child: Column(
                children: [
                  for (final slot in cookie.slots)
                    ListTile(
                      leading: Icon(
                        slot.id == cookie.activeSlotId
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                      title: Text(
                        (slot.name == null || slot.name!.trim().isEmpty)
                            ? '（未命名）'
                            : slot.name!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [
                          if (slot.note != null && slot.note!.trim().isNotEmpty)
                            '备注：${slot.note!.trim()}',
                          if (slot.id == cookie.defaultPostSlotId) '默认发言',
                          if (slot.id == cookie.defaultAuthSlotId) '鉴权',
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => context
                          .read<CookieController>()
                          .switchCookieSlot(slot.id),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: '编辑',
                            onPressed: () => _editCookieSlot(context, slot.id),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: '设为默认发言饼干',
                            onPressed: slot.id == cookie.defaultPostSlotId
                                ? null
                                : () => context
                                    .read<CookieController>()
                                    .setDefaultPostSlot(slot.id),
                            icon: const Icon(Icons.mode_comment_outlined),
                          ),
                          IconButton(
                            tooltip: '设为鉴权饼干',
                            onPressed: slot.id == cookie.defaultAuthSlotId
                                ? null
                                : () => context
                                    .read<CookieController>()
                                    .setDefaultAuthSlot(slot.id),
                            icon: const Icon(Icons.verified_outlined),
                          ),
                          IconButton(
                            tooltip: '删除',
                            onPressed: () async {
                              final nav = Navigator.of(context);
                              final cookieController = context.read<CookieController>();
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('删除饼干槽？'),
                                  content: const Text('删除后无法恢复。'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            nav.pop(false),
                                        child: const Text('取消')),
                                    FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('删除')),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                if (!mounted) return;
                                await cookieController.deleteSlot(slot.id);
                              }
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    )
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const QrImportPage()),
              );
            },
            icon: const Icon(Icons.image_search_outlined),
            label: const Text('导入饼干（二维码图片）'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: cookie.slots.isNotEmpty
                ? () async {
                    final nav = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    final cookieController = context.read<CookieController>();
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('清除全部饼干？'),
                        content: const Text('将删除所有饼干槽，并退出饼干状态。'),
                        actions: [
                          TextButton(
                              onPressed: () => nav.pop(false),
                              child: const Text('取消')),
                          FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('清除')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      if (!mounted) return;
                      await cookieController.clearAll();
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(content: Text('已清除全部饼干')),
                      );
                    }
                  }
                : null,
            icon: const Icon(Icons.delete_outline),
            label: const Text('清除全部饼干'),
          ),
        ],
      ),
    );
  }
}
