import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:xdnmb_api/xdnmb_api.dart' as api;

import '../../app/app_state.dart';
import '../../app/cookie_controller.dart';
import '../../data/cookie_store.dart';
import '../widgets/advanced_dice.dart';
import '../widgets/composer_editor.dart';
import 'composer_window_controller.dart';
import 'image_viewer_window_helper.dart';

final class ComposerWindowPage extends StatefulWidget {
  const ComposerWindowPage({super.key});

  @override
  State<ComposerWindowPage> createState() => _ComposerWindowPageState();
}

final class _ComposerWindowPageState extends State<ComposerWindowPage> {
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<WindowComposerController>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RibbonToolbar(),
          const Divider(height: 1),
          if (controller.imagePath != null)
            _ImagePreview(
              path: controller.imagePath!,
              onClear: controller.posting
                  ? null
                  : () => controller.setImagePath(null),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _PaperEditor(),
            ),
          ),
          _StatusBar(),
        ],
      ),
    );
  }
}

// ── Ribbon Toolbar: quote, image, watermark, emoticon, pin ───────────────

final class _RibbonToolbar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<WindowComposerController>();
    final cs = Theme.of(context).colorScheme;

    return Container(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _ToolButton(
            icon: Icons.format_quote,
            tooltip: '引用',
            onPressed: controller.posting
                ? null
                : () => controller.insertAroundSelection('> ', ''),
          ),
          _ToolButton(
            icon: Icons.image_outlined,
            tooltip: '插入图片',
            onPressed: controller.posting ? null : () => _pickImage(context),
          ),
          _ToolButton(
            icon: controller.watermark
                ? Icons.water_drop
                : Icons.water_drop_outlined,
            tooltip: controller.watermark ? '关闭水印' : '开启水印',
            color: controller.watermark ? cs.primary : null,
            onPressed: controller.posting
                ? null
                : () => controller.setWatermark(!controller.watermark),
          ),
          _ToolButton(
            icon: Icons.shield_outlined,
            tooltip: '防剧透',
            onPressed: controller.posting
                ? null
                : () => controller.insertAroundSelection('[h]', '[/h]'),
          ),
          _ToolButton(
            icon: Icons.casino_outlined,
            tooltip: '高级骰子',
            onPressed: controller.posting
                ? null
                : () async {
                    final result = await showAdvancedDiceDialog(context);
                    if (result != null) controller.insertText(result);
                    if (controller.focusNode.canRequestFocus) {
                      controller.focusNode.requestFocus();
                    }
                  },
          ),
          _EmoticonButton(),
          _ToolButton(
            icon: controller.isAlwaysOnTop
                ? Icons.push_pin
                : Icons.push_pin_outlined,
            tooltip: controller.isAlwaysOnTop ? '取消置顶' : '置顶',
            color: controller.isAlwaysOnTop ? cs.primary : null,
            onPressed: controller.posting
                ? null
                : () async {
                    controller.isAlwaysOnTop = !controller.isAlwaysOnTop;
                    await windowManager.setAlwaysOnTop(
                      controller.isAlwaysOnTop,
                    );
                  },
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage(BuildContext context) async {
    final controller = context.read<WindowComposerController>();
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'],
    );
    final path = res?.files.single.path;
    if (path == null || path.trim().isEmpty) return;
    controller.setImagePath(path);
  }
}

final class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  const _ToolButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 20, color: color),
          ),
        ),
      ),
    );
  }
}

// ── Paper Editor ──────────────────────────────────────────────────────────

final class _PaperEditor extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<WindowComposerController>();
    final cs = Theme.of(context).colorScheme;
    final isReply = controller.isReply;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isReply)
            TextField(
              controller: controller.titleCtrl,
              textInputAction: TextInputAction.next,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              decoration: InputDecoration(
                hintText: '标题（可选）',
                hintStyle: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          if (!isReply)
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
          Expanded(
            child: TextField(
              controller: controller.contentCtrl,
              focusNode: controller.focusNode,
              minLines: null,
              maxLines: null,
              expands: true,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    height: 1.6,
                    letterSpacing: 0.2,
                  ),
              decoration: InputDecoration(
                hintText: '在此输入内容...',
                hintStyle: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  height: 1.6,
                ),
                contentPadding: const EdgeInsets.all(16),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Status Bar: char count, cookie picker, send ───────────────────────────

final class _StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<WindowComposerController>();
    final cookie = context.watch<CookieController>();
    final cs = Theme.of(context).colorScheme;

    return Container(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          Text(
            '${controller.wordCount} 字符',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(width: 12),
          Icon(Icons.cookie_outlined, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          _CookieSelector(),
          const Spacer(),
          if (controller.showDraftSaved)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '已保存',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.primary,
                    ),
              ),
            ),
          if (controller.watermark)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.water_drop, size: 14, color: cs.primary),
            ),
          FilledButton.icon(
            onPressed: controller.posting ? null : () => _submit(context),
            icon: controller.posting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send, size: 16),
            label: Text(controller.posting ? '发送中...' : '发送'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(80, 30),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    final controller = context.read<WindowComposerController>();
    final app = context.read<AppState>();
    final cookieCtrl = context.read<CookieController>();

    final selectedSlot = cookieCtrl.slots.cast<CookieSlot?>().firstWhere(
          (s) => s?.id == controller.selectedCookieSlotId,
          orElse: () => null,
        );
    final cookie = selectedSlot == null
        ? null
        : api.XdnmbCookie(selectedSlot.userHash, name: selectedSlot.name).cookie;

    if (cookie == null || cookie.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('发言需要设置"默认发言饼干"')),
      );
      return;
    }

    final content = controller.contentCtrl.text;
    final title = controller.titleCtrl.text.trim().isEmpty
        ? null
        : controller.titleCtrl.text.trim();
    final isReply = controller.isReply;
    final forumId = controller.forumId;
    var mainPostId = controller.mainPostId;

    if (content.trim().isEmpty && controller.imagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('内容不能为空（除非选择了一张图片）')),
      );
      return;
    }

    controller.posting = true;

    try {
      if (!isReply) {
        final fid = forumId!;
        if (controller.imagePath == null) {
          await app.api.postNewThread(
            forumId: fid,
            content: content,
            title: title,
            watermark: controller.watermark,
            cookie: cookie,
          );
        } else {
          await app.api.postNewThreadWithImage(
            forumId: fid,
            content: content,
            imageFile: controller.imagePath!,
            title: title,
            watermark: controller.watermark,
            cookie: cookie,
          );
        }
        try {
          final last = await app.api.getLastPost(cookie: cookie);
          if (last?.id != null) mainPostId = last!.id;
        } catch (_) {}
      } else {
        final mid = mainPostId!;
        if (controller.imagePath == null) {
          await app.api.replyThread(
            mainPostId: mid,
            content: content,
            title: title,
            watermark: controller.watermark,
            cookie: cookie,
          );
        } else {
          await app.api.replyThreadWithImage(
            mainPostId: mid,
            content: content,
            imageFile: controller.imagePath!,
            title: title,
            watermark: controller.watermark,
            cookie: cookie,
          );
        }
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('发送成功')));
      await controller.clearDraft();

      // Notify main window to refresh.
      try {
        final mainWindow = WindowController.fromWindowId('0');
        await mainWindow.invokeMethod('refresh', mainPostId?.toString());
      } catch (_) {
        // ignore: best-effort only
      }

      await windowManager.close();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('发送失败：$e')));
    } finally {
      controller.posting = false;
    }
  }
}

// ── Cookie Selector (compact dropdown in status bar) ─────────────────────

final class _CookieSelector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<WindowComposerController>();
    final cookie = context.watch<CookieController>();
    final cs = Theme.of(context).colorScheme;

    final items = cookie.slots.map((s) {
      return DropdownMenuItem<String>(
        value: s.id,
        child: Text(s.name ?? '未命名', overflow: TextOverflow.ellipsis),
      );
    }).toList();

    return IntrinsicWidth(
      child: DropdownButton<String>(
        value: controller.selectedCookieSlotId,
        isDense: true,
        underline: const SizedBox.shrink(),
        icon: Icon(Icons.arrow_drop_down, size: 16, color: cs.onSurfaceVariant),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
        items: items.isEmpty
            ? [
                const DropdownMenuItem(
                  value: null,
                  child: Text('未导入饼干'),
                ),
              ]
            : items,
        onChanged: controller.posting
            ? null
            : (id) => controller.setSelectedCookieSlotId(id),
      ),
    );
  }
}

// ── Image Preview (compact thumbnail) ────────────────────────────────────

final class _ImagePreview extends StatelessWidget {
  final String path;
  final VoidCallback? onClear;

  const _ImagePreview({required this.path, this.onClear});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final file = File(path);
    final name = file.uri.pathSegments.isEmpty
        ? path
        : file.uri.pathSegments.last;

    return Container(
      color: cs.surfaceContainerLowest,
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Row(
        children: [
          InkWell(
            onTap: () => openImageEditorWindow(path),
            borderRadius: BorderRadius.circular(6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                file,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (onClear != null)
            IconButton(
              tooltip: '移除图片',
              onPressed: onClear,
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
        ],
      ),
    );
  }
}

// ── Emoticon Button (opens bottom sheet with full list) ───────────────────

final class _EmoticonButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _ToolButton(
      icon: Icons.emoji_emotions_outlined,
      tooltip: '颜文字',
      onPressed: () => _showEmoticonSheet(context),
    );
  }

  void _showEmoticonSheet(BuildContext context) {
    final controller = context.read<WindowComposerController>();
    final items = api.Emoticon.list;
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      constraints: const BoxConstraints(maxHeight: 400),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '颜文字',
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 2.5,
                  ),
                  itemCount: items.length,
                  itemBuilder: (_, index) {
                    final e = items[index];
                    return EmoticonButton(
                      name: e.name,
                      text: e.text,
                      fontSize: 13,
                      onInsert: (text) {
                        Navigator.of(ctx).pop();
                        controller.insertText(text);
                        if (controller.focusNode.canRequestFocus) {
                          controller.focusNode.requestFocus();
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
