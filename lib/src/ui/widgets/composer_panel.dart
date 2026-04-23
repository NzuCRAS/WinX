import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:xdnmb_api/xdnmb_api.dart' as api;

import '../../app/app_state.dart';
import '../../app/composer_controller.dart';
import '../../app/cookie_controller.dart';
import '../../data/cookie_store.dart';
import '../../data/post_history_store.dart';
import 'composer_editor.dart';
import '../windows/image_viewer_window_helper.dart';

/// The composer shown as an embedded panel (docked to the right side).
/// Contains a header toolbar, the editor form, optional image preview,
/// and bottom action buttons.
final class ComposerPanel extends StatelessWidget {
  final VoidCallback? onSubmitSuccess;

  const ComposerPanel({super.key, this.onSubmitSuccess});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ComposerController>();
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──
          Container(
            color: cs.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    controller.windowTitle,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Pop out to independent window
                IconButton(
                  tooltip: '摘出为独立窗口',
                  onPressed: controller.posting
                      ? null
                      : () => controller.popOutToWindow(),
                  icon: const Icon(Icons.open_in_new_outlined),
                  iconSize: 20,
                ),
                // Close
                IconButton(
                  tooltip: '关闭',
                  onPressed: controller.posting ? null : () => controller.close(),
                  icon: const Icon(Icons.close),
                  iconSize: 20,
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── Image preview (if any) ──
          if (controller.imagePath != null)
            _ImagePreview(
              path: controller.imagePath!,
              onClear: controller.posting
                  ? null
                  : () {
                      controller.setImagePath(null);
                      controller.onImageChanged();
                    },
            ),

          // ── Editor form ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: ComposerEditor(
                controller: controller,
                onSubmit: () => _submit(context),
              ),
            ),
          ),

          // ── Bottom actions ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: controller.posting
                      ? null
                      : () => controller.close(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: controller.posting ? null : () => _submit(context),
                  child: controller.posting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('发送'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showComposerDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _ComposerDialogContent(),
    );
    if (result == true) {
      onSubmitSuccess?.call();
    }
  }

  Future<void> _submit(BuildContext context) async {
    final result = await _doSubmit(context);
    if (result == true) {
      onSubmitSuccess?.call();
    }
  }

  Future<bool?> _doSubmit(BuildContext context) async {
    final controller = context.read<ComposerController>();
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
      return false;
    }

    final content = controller.contentCtrl.text;
    final title = controller.titleCtrl.text.trim().isEmpty
        ? null
        : controller.titleCtrl.text.trim();
    final isReply = controller.isReply;
    final forumId = controller.args?.forumId;
    var mainPostId = controller.args?.mainPostId;

    if (content.trim().isEmpty && controller.imagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('内容不能为空（除非选择了一张图片）')),
      );
      return false;
    }

    controller.setPosting(true);

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

      if (!context.mounted) return null;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('发送成功')));

      // Best-effort history recording
      // ignore: discarded_futures
      _recordPostHistory(
        app: app,
        isReply: isReply,
        forumId: forumId,
        mainPostId: mainPostId,
        content: content,
        title: title,
      );

      // Give user time to read the toast before closing.
      await Future.delayed(const Duration(milliseconds: 600));
      if (!context.mounted) return null;

      await controller.clearDraft();
      controller.resetState();
      controller.close();
      return true;
    } catch (e) {
      if (!context.mounted) return null;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('发送失败：$e')));
      return false;
    } finally {
      controller.setPosting(false);
    }
  }

}

/// Best-effort post history recording (shared between panel and dialog).
Future<void> _recordPostHistory({
  required AppState app,
  required bool isReply,
  required int? forumId,
  required int? mainPostId,
  required String content,
  required String? title,
}) async {
  api.Thread? threadHead;
  if (mainPostId != null) {
    try {
      threadHead =
          await app.repo.getThreadPage(mainPostId, 1, forceRefresh: true);
    } catch (_) {
      // ignore: best-effort only
    }
  }

  int? replyPostId;
  int? replyPage;
  if (isReply && mainPostId != null) {
    try {
      final rc = threadHead?.mainPost.replyCount ?? 0;
      // xdnmb API returns 19 replies per page. The new reply is the
      // (rc + 1)-th reply, so its page is (rc ~/ 19 + 1).
      final lastPage = rc ~/ 19 + 1;
      replyPage = lastPage;
      final lastThread = await app.repo
          .getThreadPage(mainPostId, lastPage, forceRefresh: true);
      if (lastThread.replies.isNotEmpty) {
        replyPostId = lastThread.replies
            .reduce((a, b) => a.id > b.id ? a : b)
            .id;
      }
    } catch (_) {
      // ignore: best-effort only
    }
  }

  final store = PostHistoryStore();
  await store.record(
    PostHistoryEntry(
      isReply: isReply,
      forumId: forumId,
      mainPostId: mainPostId,
      replyPostId: replyPostId,
      title: title,
      content: content,
      postedAt: DateTime.now(),
      threadUserHash: threadHead?.mainPost.userHash.trim().isEmpty == true
          ? null
          : threadHead?.mainPost.userHash.trim(),
      threadIsAdmin: threadHead?.mainPost.isAdmin,
      threadPostTime: threadHead?.mainPost.postTime,
      threadReplyCount: threadHead?.mainPost.replyCount,
      threadThumbImageUrl: threadHead?.mainPost.thumbImageUrl,
      threadContent: threadHead?.mainPost.content,
      replyPage: replyPage,
    ),
  );
}

/// Compact image preview shown inside the panel.
/// Tapping the thumbnail opens the image in a standalone editor window.
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
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
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

/// Dialog content for the "pop out" flow.
final class _ComposerDialogContent extends StatefulWidget {
  const _ComposerDialogContent();

  @override
  State<_ComposerDialogContent> createState() => _ComposerDialogContentState();
}

final class _ComposerDialogContentState extends State<_ComposerDialogContent> {
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ComposerController>();
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Material(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                color: cs.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        controller.windowTitle,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Always on top
                    IconButton(
                      tooltip: controller.isAlwaysOnTop ? '取消置顶' : '置顶',
                      onPressed: () async {
                        controller.toggleAlwaysOnTop();
                        await windowManager.setAlwaysOnTop(
                          controller.isAlwaysOnTop,
                        );
                      },
                      icon: Icon(
                        controller.isAlwaysOnTop
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                        size: 20,
                      ),
                    ),
                    // Embed back
                    IconButton(
                      tooltip: '嵌入回面板',
                      onPressed: controller.posting
                          ? null
                          : () {
                              controller.toggleFloat();
                              Navigator.of(context).pop(false);
                            },
                      icon: const Icon(Icons.close_fullscreen_outlined, size: 20),
                    ),
                    // Close
                    IconButton(
                      tooltip: '关闭',
                      onPressed: controller.posting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),

              // Image preview
              if (controller.imagePath != null)
                _ImagePreview(
                  path: controller.imagePath!,
                  onClear: controller.posting
                      ? null
                      : () {
                          controller.setImagePath(null);
                          controller.onImageChanged();
                        },
                ),

              // Editor
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: ComposerEditor(
                    controller: controller,
                    onSubmit: () => _submitDialog(context),
                  ),
                ),
              ),

              // Actions
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: controller.posting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: controller.posting
                          ? null
                          : () => _submitDialog(context),
                      child: controller.posting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('发送'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitDialog(BuildContext context) async {
    final result = await _doSubmit(context);
    if (result == true && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<bool?> _doSubmit(BuildContext context) async {
    final controller = context.read<ComposerController>();
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
      return false;
    }

    final content = controller.contentCtrl.text;
    final title = controller.titleCtrl.text.trim().isEmpty
        ? null
        : controller.titleCtrl.text.trim();
    final isReply = controller.isReply;
    final forumId = controller.args?.forumId;
    var mainPostId = controller.args?.mainPostId;

    if (content.trim().isEmpty && controller.imagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('内容不能为空（除非选择了一张图片）')),
      );
      return false;
    }

    controller.setPosting(true);

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

      if (!context.mounted) return null;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('发送成功')));

      // Best-effort history recording
      // ignore: discarded_futures
      _recordPostHistory(
        app: app,
        isReply: isReply,
        forumId: forumId,
        mainPostId: mainPostId,
        content: content,
        title: title,
      );

      // Give user time to read the toast before closing.
      await Future.delayed(const Duration(milliseconds: 600));
      if (!context.mounted) return null;

      await controller.clearDraft();
      controller.resetState();
      controller.close();
      return true;
    } catch (e) {
      if (!context.mounted) return null;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('发送失败：$e')));
      return false;
    } finally {
      controller.setPosting(false);
    }
  }
}
