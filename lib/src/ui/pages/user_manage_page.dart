import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import 'qr_import_page.dart';

final class UserManagePage extends StatefulWidget {
  const UserManagePage({super.key});

  @override
  State<UserManagePage> createState() => _UserManagePageState();
}

final class _UserManagePageState extends State<UserManagePage> {
  Future<void> _editCookieSlot(BuildContext context, String slotId) async {
    final app = context.read<AppState>();
    final slot = app.cookieSlots.firstWhere((s) => s.id == slotId);
    final noteCtrl = TextEditingController(text: slot.note ?? '');
    final nav = Navigator.of(context);

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
      await app.updateCookieSlotMeta(
        slotId,
        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('用户管理')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: Icon(app.hasCookie
                  ? Icons.verified_user_outlined
                  : Icons.no_accounts_outlined),
              title: Text(app.hasCookie ? '已导入饼干' : '未导入饼干'),
              subtitle:
                  Text(app.cookieName == null ? '（无饼干名）' : app.cookieName!),
            ),
          ),
          if (app.cookieSlots.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('饼干槽', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Card(
              child: Column(
                children: [
                  for (final slot in app.cookieSlots)
                    ListTile(
                      leading: Icon(
                        slot.id == app.activeCookieSlotId
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
                          if (slot.id == app.defaultPostCookieSlotId) '默认发言',
                          if (slot.id == app.defaultAuthCookieSlotId) '鉴权',
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => context
                          .read<AppState>()
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
                            onPressed: slot.id == app.defaultPostCookieSlotId
                                ? null
                                : () => context
                                    .read<AppState>()
                                    .setDefaultPostCookieSlot(slot.id),
                            icon: const Icon(Icons.mode_comment_outlined),
                          ),
                          IconButton(
                            tooltip: '设为鉴权饼干',
                            onPressed: slot.id == app.defaultAuthCookieSlotId
                                ? null
                                : () => context
                                    .read<AppState>()
                                    .setDefaultAuthCookieSlot(slot.id),
                            icon: const Icon(Icons.verified_outlined),
                          ),
                          IconButton(
                            tooltip: '删除',
                            onPressed: () async {
                              final nav = Navigator.of(context);
                              final appState = context.read<AppState>();
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
                                await appState.deleteCookieSlot(slot.id);
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
            onPressed: app.cookieSlots.isNotEmpty
                ? () async {
                    final nav = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    final appState = context.read<AppState>();
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
                      await appState.clearAllCookies();
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
