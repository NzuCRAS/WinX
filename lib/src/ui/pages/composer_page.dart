import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:xdnmb_api/xdnmb_api.dart' as api;
import 'package:desktop_drop/desktop_drop.dart';

import '../../app/app_state.dart';
import '../../app/cookie_controller.dart';
import '../../data/cookie_store.dart';
import '../../data/draft_store.dart';
import '../../data/post_history_store.dart';

enum ComposerMode {
  newThread,
  reply,
}

final class ComposerPage extends StatefulWidget {
  final ComposerMode mode;

  /// Required for new thread.
  final int? forumId;

  /// Required for reply.
  final int? mainPostId;

  final String title;
  /// Initial text written into the content editor when the dialog opens.
  ///
  /// Used for quick quoting flows, e.g. clicking `No.xxx` in a thread to open
  /// reply composer with `>>No.xxx` pre-filled.
  final String? initialContent;

  const ComposerPage.newThread({
    super.key,
  required this.forumId,
    String? forumName,
  this.initialContent,
  })  : mode = ComposerMode.newThread,
        mainPostId = null,
        title = '发串${forumName == null ? '' : ' · $forumName'}';

  const ComposerPage.reply({
    super.key,
  required this.mainPostId,
  this.initialContent,
  })  : mode = ComposerMode.reply,
        forumId = null,
        title = '回串 · No.$mainPostId';

  @override
  State<ComposerPage> createState() => _ComposerPageState();
}

final class _ComposerPageState extends State<ComposerPage> {
  final _contentCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _focusNode = FocusNode();

  final _draftStore = const DraftStore();
  final _postHistoryStore = PostHistoryStore();
  bool _draftLoaded = false;
  bool _restoringDraft = false;
  bool _draftClearedOnSuccess = false;
  int _draftTicket = 0;
  bool _showDraftSaved = false;

  bool _watermark = false;
  bool _posting = false;

  String? _imagePath;
  void _setImagePath(String? p) {
    if (p == null || p.trim().isEmpty) return;
    setState(() => _imagePath = p);
  _scheduleSaveDraft();
  }

  String? _selectedPostCookieSlotId;
  bool _emoticonExpanded = false;

  @override
  void initState() {
    super.initState();

  _contentCtrl.addListener(_onDraftRelevantChanged);
  _titleCtrl.addListener(_onDraftRelevantChanged);

  // Restore draft after first build so AppState is ready.
  // ignore: discarded_futures
  Future.microtask(_restoreDraftIfAny);
  }

  @override
  void dispose() {
    _contentCtrl.removeListener(_onDraftRelevantChanged);
    _titleCtrl.removeListener(_onDraftRelevantChanged);
    _contentCtrl.dispose();
    _titleCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isReply => widget.mode == ComposerMode.reply;

  void _onDraftRelevantChanged() {
    if (_restoringDraft) return;
    _scheduleSaveDraft();
  }

  void _scheduleSaveDraft() {
    if (_posting) return;
    if (_draftClearedOnSuccess) return;

    final ticket = ++_draftTicket;
    Future<void>.delayed(const Duration(milliseconds: 450)).then((_) async {
      if (!mounted) return;
      if (ticket != _draftTicket) return;
      if (_restoringDraft) return;
      await _saveDraftNow();
    });
  }

  Future<void> _saveDraftNow() async {
    if (!mounted) return;
    if (_draftClearedOnSuccess) return;

    final draft = ComposerDraft(
      title: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
      content: _contentCtrl.text,
      watermark: _watermark,
      imagePath: _imagePath,
      selectedPostCookieSlotId: _selectedPostCookieSlotId,
    );
    await _draftStore.write(isReply: _isReply, draft: draft);
    if (mounted) {
      setState(() => _showDraftSaved = true);
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showDraftSaved = false);
      });
    }
  }

  Future<void> _restoreDraftIfAny() async {
    if (!mounted) return;
    if (_draftLoaded) return;
    _draftLoaded = true;

    final draft = await _draftStore.read(isReply: _isReply);
    final initial = (widget.initialContent ?? '').trimRight();
    if (draft == null && initial.isEmpty) return;

    _restoringDraft = true;
    try {
      if (widget.mode == ComposerMode.newThread) {
        final t = draft?.title;
        if (t != null && t.trim().isNotEmpty) {
          _titleCtrl.text = t;
        }
      }

      final restoredContent = (draft?.content ?? '').trimRight();
      final merged = _mergeInitialIntoDraft(
        draftContent: restoredContent,
        initialContent: initial,
      );
      if (merged.isNotEmpty) {
        _contentCtrl.text = merged;
        _contentCtrl.selection =
            TextSelection.collapsed(offset: _contentCtrl.text.length);
      }

      final img = draft?.imagePath;
      if (img != null && img.trim().isNotEmpty) {
        _imagePath = img;
      }
      _watermark = draft?.watermark ?? _watermark;
      _selectedPostCookieSlotId =
          draft?.selectedPostCookieSlotId ?? _selectedPostCookieSlotId;
    } finally {
      _restoringDraft = false;
    }

    if (mounted) setState(() {});
    await _saveDraftNow();
  }

  String _mergeInitialIntoDraft({
    required String draftContent,
    required String initialContent,
  }) {
    if (initialContent.isEmpty) return draftContent;
    if (draftContent.isEmpty) return '$initialContent\n';
    if (draftContent.contains(initialContent)) return draftContent;
    return '$initialContent\n$draftContent';
  }

  Future<void> _clearDraft() async {
    _draftClearedOnSuccess = true;
    await _draftStore.clear(isReply: _isReply);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Default to user's configured default post cookie, but allow override.
    final cookie = context.read<CookieController>();
    _selectedPostCookieSlotId ??= cookie.defaultPostSlotId;
  }

  Future<void> _pickImage() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'],
    );
    final path = res?.files.single.path;
  if (path == null || path.trim().isEmpty) return;
  _setImagePath(path);
  }

  void _insertText(String text) {
    final v = _contentCtrl.value;
    final start = v.selection.start;
    final end = v.selection.end;
    final selectionValid = start >= 0 && end >= 0;

    if (!selectionValid) {
      _contentCtrl.text += text;
      _contentCtrl.selection = TextSelection.collapsed(offset: _contentCtrl.text.length);
      return;
    }

    final newText = v.text.replaceRange(start, end, text);
    final newOffset = start + text.length;
    _contentCtrl.value = v.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
      composing: TextRange.empty,
    );
  }

  Future<void> _submit() async {
    if (_posting) return;

    final app = context.read<AppState>();
    final cookieCtrl = context.read<CookieController>();

  final selectedSlot = cookieCtrl.slots.cast<CookieSlot?>().firstWhere(
      (s) => s?.id == _selectedPostCookieSlotId,
      orElse: () => null,
    );
  final cookie = selectedSlot == null
    ? null
    : api.XdnmbCookie(selectedSlot.userHash, name: selectedSlot.name).cookie;

  if (cookie == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('发言需要设置“默认发言饼干”')));
      return;
    }

    final content = _contentCtrl.text;
    final title = _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim();
  final isReply = _isReply;
  final forumId = widget.forumId;
  var mainPostId = widget.mainPostId;
  const String? name = null;
  const String? email = null;

    if (content.trim().isEmpty && _imagePath == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('内容不能为空（除非选择了一张图片）')));
      return;
    }

    setState(() => _posting = true);

    try {
      if (widget.mode == ComposerMode.newThread) {
        final fid = widget.forumId!;
        if (_imagePath == null) {
          await app.api.postNewThread(
            forumId: fid,
            content: content,
            title: title,
            name: name,
            email: email,
            watermark: _watermark,
            cookie: cookie,
          );
        } else {
          await app.api.postNewThreadWithImage(
            forumId: fid,
            content: content,
            imageFile: _imagePath!,
            title: title,
            name: name,
            email: email,
            watermark: _watermark,
            cookie: cookie,
          );
        }

        // Best-effort: resolve newly created thread id.
        // According to API doc: getLastPost() returns the newest thread once
        // after posting, then returns null.
        try {
          final last = await app.api.getLastPost(cookie: cookie);
          if (last?.id != null) {
            mainPostId = last!.id;
          }
        } catch (_) {
          // ignore
        }
      } else {
        final mid = widget.mainPostId!;
        if (_imagePath == null) {
          await app.api.replyThread(
            mainPostId: mid,
            content: content,
            title: title,
            name: name,
            email: email,
            watermark: _watermark,
            cookie: cookie,
          );
        } else {
          await app.api.replyThreadWithImage(
            mainPostId: mid,
            content: content,
            imageFile: _imagePath!,
            title: title,
            name: name,
            email: email,
            watermark: _watermark,
            cookie: cookie,
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('发送成功')));

      api.Thread? threadHead;
      if (mainPostId != null) {
        try {
          threadHead =
              await app.repo.getThreadPage(mainPostId, 1, forceRefresh: true);
        } catch (_) {
          // ignore: best-effort only
        }
      }

      // Best-effort: resolve newly created reply post id and page.
      // Fetch the last page of the thread and pick the reply with the
      // highest id – that is almost certainly the one we just posted.
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

      // Record post history (successful submit only).
      // ignore: discarded_futures
      _postHistoryStore.record(
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
  await _clearDraft();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('发送失败：$e')));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cookie = context.watch<CookieController>();
    final slotItems = cookie.slots;

    final selectedSlot = slotItems.cast<CookieSlot?>().firstWhere(
          (s) => s?.id == _selectedPostCookieSlotId,
          orElse: () => null,
        );

    final postSlotLabel = selectedSlot?.name ??
        cookie.defaultPostCookieSlot?.name ??
        (slotItems.isEmpty ? '（未导入饼干）' : '（未选择）');

    final viewInsets = MediaQuery.viewInsetsOf(context);
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_posting,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) return;
        if (_draftClearedOnSuccess) return;
        await _saveDraftNow();
      },
      child: _DraggableScalableDialog(
        title: widget.title,
        minSize: const Size(520, 420),
        maxWidth: 980,
        maxHeight: 820,
        paddingBottom: viewInsets.bottom,
        showImagePreview: _imagePath != null,
        imagePath: _imagePath,
        onClearImage: _posting || _imagePath == null
            ? null
            : () => setState(() => _imagePath = null),
        onReplaceImage: _posting ? null : _setImagePath,
        onSubmit: _posting ? null : _submit,
        onCancel: _posting
            ? null
            : () async {
                await _saveDraftNow();
                if (mounted) Navigator.of(context).pop(false);
              },
        actions: [
        TextButton(
          onPressed: _posting
              ? null
              : () async {
                  await _saveDraftNow();
                  if (context.mounted) Navigator.of(context).pop(false);
                },
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _posting ? null : _submit,
          child: _posting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('发送'),
        ),
      ],
  child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.cookie_outlined),
                  const SizedBox(width: 8),
                  const Text('发言饼干：'),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _selectedPostCookieSlotId,
                      items: slotItems
                          .map(
                            (s) => DropdownMenuItem(
                              value: s.id,
                              child: Text(s.name ?? '未命名饼干'),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _posting
                          ? null
                          : (v) {
                              setState(() => _selectedPostCookieSlotId = v);
                              _scheduleSaveDraft();
                            },
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        isDense: true,
                        hintText: postSlotLabel,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (widget.mode == ComposerMode.newThread) ...[
                TextField(
                  controller: _titleCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '标题（可选）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 200, maxHeight: 480),
                child: TextField(
                  controller: _contentCtrl,
                  focusNode: _focusNode,
                  minLines: 8,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    labelText: '内容',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _posting ? null : _pickImage,
                      icon: const Icon(Icons.image_outlined),
                      label: Text(
                        _imagePath == null
                            ? '选择图片（最多1张）'
                            : '已选择：${File(_imagePath!).uri.pathSegments.last}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '移除图片',
                    onPressed: _posting || _imagePath == null
                        ? null
                        : () => setState(() => _imagePath = null),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  InkWell(
                    onTap: _posting
                        ? null
                        : () {
                            setState(() => _watermark = !_watermark);
                            _scheduleSaveDraft();
                          },
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _watermark,
                            onChanged: _posting
                                ? null
                                : (v) {
                                    setState(() => _watermark = v ?? false);
                                    _scheduleSaveDraft();
                                  },
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 4),
                          const Text('水印'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_showDraftSaved)
                    Text(
                      '已自动保存',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  const Spacer(),
                  Flexible(
                    flex: 1,
                    child: _EmoticonDropdown(
                      expanded: _emoticonExpanded,
                      onExpandedChanged: _posting
                          ? null
                          : (v) => setState(() => _emoticonExpanded = v),
                      onInsert: (t) {
                        _insertText(t);
                        if (_focusNode.canRequestFocus) {
                          _focusNode.requestFocus();
                        }
                      },
                      backgroundColor: cs.surface,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
  ),
  );
  }
}

final class _EmoticonDropdown extends StatelessWidget {
  final bool expanded;
  final ValueChanged<bool>? onExpandedChanged;
  final void Function(String text) onInsert;
  final Color backgroundColor;

  const _EmoticonDropdown({
    required this.expanded,
    required this.onExpandedChanged,
    required this.onInsert,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final items = api.Emoticon.list;
    final cs = Theme.of(context).colorScheme;

  return ExpansionTile(
      initiallyExpanded: expanded,
      onExpansionChanged: onExpandedChanged,
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      collapsedBackgroundColor: backgroundColor,
      backgroundColor: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      title: Row(
        children: [
          Icon(Icons.emoji_emotions_outlined, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          const Text('颜文字'),
        ],
      ),
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final maxW = c.maxWidth;
            // Show full emoticon names (no ellipsis). We dynamically compute a
            // column count and then auto-scale font size per-cell based on name
            // length.
            const baseFontSize = 13.0;
            const cellH = 36.0;
            const minCellW = 92.0;
            final crossAxisCount = math.max(2, (maxW / minCellW).floor());
            // Keep it compact: show at most 6 rows.
            final maxH = math.min(6 * (cellH + 6), 320.0);

            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH),
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  mainAxisExtent: cellH,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final e = items[index];
                  final colW = (maxW - 6 * (crossAxisCount - 1)) / crossAxisCount;
                  // Heuristic: shrink font to fit longer names while keeping
                  // buttons consistent width.
                  final estCharW = 0.62;
                  final maxChars = math.max(4.0, (colW - 18) / (baseFontSize * estCharW));
                  final scale = (maxChars / e.name.length).clamp(0.72, 1.0);
                  final fontSize = baseFontSize * scale;
                  return _EmoticonButton(
                      name: e.name,
                      text: e.text,
                      fontSize: fontSize,
                      onInsert: onInsert,
                    );
                },
              ),
            );
          },
        )
      ],
    );
  }
}

final class _EmoticonButton extends StatefulWidget {
  final String name;
  final String text;
  final double fontSize;
  final void Function(String text) onInsert;

  const _EmoticonButton({
    required this.name,
    required this.text,
    required this.fontSize,
    required this.onInsert,
  });

  @override
  State<_EmoticonButton> createState() => _EmoticonButtonState();
}

final class _EmoticonButtonState extends State<_EmoticonButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onLongPressStart(LongPressStartDetails _) {
    _ctrl.forward(from: 0);
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    if (_ctrl.isCompleted) {
      Clipboard.setData(ClipboardData(text: widget.text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已复制: ${widget.name}'),
            duration: const Duration(milliseconds: 800),
          ),
        );
      }
    }
    _ctrl.reset();
  }

  void _onLongPressCancel() {
    _ctrl.reset();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress = _ctrl.value;

    return GestureDetector(
      onTap: () => widget.onInsert(widget.text),
      onLongPressStart: _onLongPressStart,
      onLongPressEnd: _onLongPressEnd,
      onLongPressCancel: _onLongPressCancel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: [progress, progress],
            colors: [
              cs.outlineVariant.withValues(alpha: 0.35),
              Colors.transparent,
            ],
          ),
          border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              widget.name,
              softWrap: false,
              overflow: TextOverflow.visible,
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'Microsoft YaHei',
                fontSize: widget.fontSize,
                color: cs.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Desktop shortcuts for the composer dialog.
class _SendIntent extends Intent {
  const _SendIntent();
}

class _CancelIntent extends Intent {
  const _CancelIntent();
}

final class _DraggableScalableDialog extends StatefulWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;
  final Size minSize;
  final double maxWidth;
  final double maxHeight;
  final double paddingBottom;
  final bool showImagePreview;
  final String? imagePath;
  final VoidCallback? onClearImage;
  final ValueChanged<String>? onReplaceImage;
  final Future<void> Function()? onSubmit;
  final VoidCallback? onCancel;

  const _DraggableScalableDialog({
    required this.title,
    required this.child,
    required this.actions,
    required this.minSize,
    required this.maxWidth,
    required this.maxHeight,
    required this.paddingBottom,
  required this.showImagePreview,
  required this.imagePath,
  required this.onClearImage,
  required this.onReplaceImage,
    this.onSubmit,
    this.onCancel,
  });

  @override
  State<_DraggableScalableDialog> createState() => _DraggableScalableDialogState();
}

final class _DraggableScalableDialogState extends State<_DraggableScalableDialog> {
  Offset _offset = Offset.zero;
  double _scale = 1.0;

  double? _widthOverride;
  double? _heightOverride;

  Offset? _resizeStartGlobal;
  double? _resizeStartW;
  double? _resizeStartH;

  Offset? _lastMousePos;

  Offset? _dragStartLocal;
  Offset? _dragStartOffset;
  double? _scaleStart;
  double? _pinchStart;

  int? _imgW;
  int? _imgH;

  void _reset() {
    setState(() {
      _offset = Offset.zero;
      _scale = 1.0;
      _widthOverride = null;
      _heightOverride = null;
      _imgW = null;
      _imgH = null;
    });
  }

  double _computePreviewWidth(double baseH) {
    final w = _imgW;
    final h = _imgH;
    if (w == null || h == null || h <= 0) return 300;
    return (baseH * w / h).clamp(160.0, 420.0);
  }

  void _startResize(DragStartDetails d, double baseW, double baseH) {
    _resizeStartGlobal = d.globalPosition;
    _resizeStartW = _widthOverride ?? baseW;
    _resizeStartH = _heightOverride ?? baseH;
  }

  void _updateResize(DragUpdateDetails d, double minW, double minH, double maxW, double maxH,
      {required bool handleOnLeft}) {
    final start = _resizeStartGlobal;
    if (start == null) return;
    final dx = d.globalPosition.dx - start.dx;
    final dy = d.globalPosition.dy - start.dy;
    // When the handle is on the left, moving the pointer to the left should
    // increase width (negative dx => expand).
    final signedDx = handleOnLeft ? -dx : dx;
    final newW = ((_resizeStartW ?? minW) + signedDx).clamp(minW, maxW);
    final newH = ((_resizeStartH ?? minH) + dy).clamp(minH, maxH);
    setState(() {
      _widthOverride = newW;
      _heightOverride = newH;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final cs = Theme.of(context).colorScheme;

  final maxBaseW = math.min(widget.maxWidth, size.width - 24);
  final maxBaseH = math.min(widget.maxHeight, size.height - 24 - widget.paddingBottom);

  final baseW = (_widthOverride ?? maxBaseW).clamp(widget.minSize.width, maxBaseW);
  final baseH = (_heightOverride ?? maxBaseH).clamp(widget.minSize.height, maxBaseH);

  final minScale = 0.30;
  final maxScale = 3.00;
    final clampedScale = _scale.clamp(minScale, maxScale);

    final dialogW = baseW * clampedScale;
    final dialogH = baseH * clampedScale;

    final maxDx = math.max(0.0, (size.width - dialogW) / 2);
    final maxDy = math.max(0.0, (size.height - widget.paddingBottom - dialogH) / 2);
    final clampedOffset = Offset(
      _offset.dx.clamp(-maxDx, maxDx),
      _offset.dy.clamp(-maxDy, maxDy),
    );

    // Keep internal state synced with clamped values.
    _scale = clampedScale;
    _offset = clampedOffset;

    return Actions(
      actions: {
        _SendIntent: CallbackAction<_SendIntent>(
          onInvoke: (_) {
            // ignore: discarded_futures
            widget.onSubmit?.call();
            return null;
          },
        ),
        _CancelIntent: CallbackAction<_CancelIntent>(
          onInvoke: (_) {
            widget.onCancel?.call();
            return null;
          },
        ),
      },
      child: Shortcuts(
        shortcuts: {
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.enter):
              const _SendIntent(),
          const SingleActivator(LogicalKeyboardKey.escape):
              const _CancelIntent(),
        },
        child: Focus(
          autofocus: true,
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: Container(color: Colors.black54),
                  ),
                ),
                Center(
                  child: Listener(
                    onPointerSignal: (sig) {
                      if (!HardwareKeyboard.instance.isControlPressed) return;
                      if (sig is PointerScrollEvent) {
                        final dy = sig.scrollDelta.dy;
                        // Ctrl+wheel zoom: up => zoom in, down => zoom out.
                        final factor = math.exp((-dy) / 300.0);
                        setState(() {
                          // Zoom around mouse pointer (if we have one).
                          final before = _scale;
                          final after = (_scale * factor).clamp(minScale, maxScale);
                          final p = _lastMousePos;
                          if (p != null) {
                            final center = Offset(size.width / 2, (size.height - widget.paddingBottom) / 2);
                            final world = (p - center - _offset) / before;
                            _offset = p - center - world * after;
                          }
                          _scale = after;
                        });
                      }
                    },
              onPointerHover: (e) => _lastMousePos = e.position,
              child: GestureDetector(
              onScaleStart: (d) {
                _dragStartLocal = d.localFocalPoint;
                _dragStartOffset = _offset;
                _scaleStart = _scale;
                _pinchStart = 1.0;
              },
              onScaleUpdate: (d) {
                final startLocal = _dragStartLocal;
                final startOffset = _dragStartOffset;
                if (startLocal == null || startOffset == null) return;

                final delta = d.localFocalPoint - startLocal;
                final newOffset = startOffset + delta;

                final s0 = _scaleStart ?? _scale;
                final p0 = _pinchStart ?? 1.0;
                final newScale = (s0 * (d.scale / p0));

                setState(() {
                  _offset = newOffset;
                  _scale = newScale;
                });
              },
              child: Transform(
                // ignore: deprecated_member_use
                transform: Matrix4.identity()
                  ..translate(clampedOffset.dx, clampedOffset.dy) // ignore: deprecated_member_use
                  ..scale(clampedScale), // ignore: deprecated_member_use
                alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.showImagePreview && widget.imagePath != null) ...[
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          width: _computePreviewWidth(baseH),
                          height: baseH,
                          child: _ImagePreviewCard(
                            path: widget.imagePath!,
                            onClear: widget.onClearImage,
                            onReplace: widget.onReplaceImage,
                            onMetaLoaded: (w, h) {
                              if (_imgW != w || _imgH != h) {
                                setState(() {
                                  _imgW = w;
                                  _imgH = h;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      ConstrainedBox(
                        constraints: BoxConstraints.tightFor(
                          width: baseW,
                          height: baseH,
                        ),
                        child: Material(
                          color: cs.surface,
                          elevation: 12,
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            children: [
                              Column(
                                children: [
                                  Container(
                                    color: cs.surfaceContainerHighest,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            widget.title,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(fontWeight: FontWeight.w700),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: '重置大小/位置',
                                          onPressed: _reset,
                                          icon: const Icon(Icons.center_focus_strong_outlined),
                                        ),
                                        IconButton(
                                          tooltip: '关闭',
                                          onPressed: () => Navigator.of(context).pop(false),
                                          icon: const Icon(Icons.close),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: widget.child,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: widget.actions,
                                    ),
                                  ),
                                ],
                              ),
                              // Bottom-left resize handle.
                              Positioned(
                                left: 0,
                                bottom: 0,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onPanStart: (d) => _startResize(d, baseW, baseH),
                                  onPanUpdate: (d) => _updateResize(
                                    d,
                                    widget.minSize.width,
                                    widget.minSize.height,
                                    maxBaseW,
                                    maxBaseH,
                                    handleOnLeft: true,
                                  ),
                                  child: SizedBox(
                                    width: 30,
                                    height: 30,
                                    child: Icon(
                                      Icons.drag_handle,
                                      size: 18,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
              ),
            ),
            ),
          ),
        ],
      ),
    ),
  ),
),
);
  }
}

final class _ImagePreviewCard extends StatefulWidget {
  final String path;
  final VoidCallback? onClear;
  final ValueChanged<String>? onReplace;
  final void Function(int width, int height)? onMetaLoaded;

  const _ImagePreviewCard({
    required this.path,
    this.onClear,
    this.onReplace,
    this.onMetaLoaded,
  });

  @override
  State<_ImagePreviewCard> createState() => _ImagePreviewCardState();
}

final class _ImagePreviewCardState extends State<_ImagePreviewCard> {
  final TransformationController _tc = TransformationController();

  int? _w;
  int? _h;
  int? _bytes;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  @override
  void didUpdateWidget(covariant _ImagePreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _tc.value = Matrix4.identity();
      _w = null;
      _h = null;
      _bytes = null;
      _loadMeta();
    }
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    try {
      final file = File(widget.path);
      final b = await file.length();
      final img = await decodeImageFromList(await file.readAsBytes());
      if (!mounted) return;
      setState(() {
        _bytes = b;
        _w = img.width;
        _h = img.height;
      });
      widget.onMetaLoaded?.call(img.width, img.height);
    } catch (_) {
      // Ignore preview meta errors.
    }
  }

  String _formatBytes(int v) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var d = v.toDouble();
    var i = 0;
    while (d >= 1024 && i < units.length - 1) {
      d /= 1024;
      i++;
    }
    final s = d >= 10 || i == 0 ? d.toStringAsFixed(0) : d.toStringAsFixed(1);
    return '$s ${units[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.path);
    final name = file.uri.pathSegments.isEmpty ? widget.path : file.uri.pathSegments.last;
    final cs = Theme.of(context).colorScheme;

    final meta = <String>[];
    if (_w != null && _h != null) meta.add('${_w}×${_h}');
    if (_bytes != null) meta.add(_formatBytes(_bytes!));

    return Material(
      color: cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '图片预览\n$name',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                IconButton(
                  tooltip: '重置缩放',
                  onPressed: () => setState(() => _tc.value = Matrix4.identity()),
                  icon: const Icon(Icons.center_focus_strong_outlined),
                ),
                if (widget.onClear != null)
                  IconButton(
                    tooltip: '移除图片',
                    onPressed: widget.onClear,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
          ),
          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Text(
                meta.join(' · '),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          Expanded(
            child: DropTarget(
              enable: widget.onReplace != null,
              onDragDone: (detail) {
                if (widget.onReplace == null) return;
                if (detail.files.isEmpty) return;
                final f = detail.files.first;
                final p = f.path;
                if (p.isNotEmpty) widget.onReplace!(p);
              },
              child: Builder(
                builder: (context) {
                  return Container(
                    color: cs.surface,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: InteractiveViewer(
                            transformationController: _tc,
                            minScale: 0.2,
                            maxScale: 8.0,
                            child: Image.file(
                              file,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text('无法加载图片：$error'),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        if (widget.onReplace != null)
                          Positioned(
                            left: 8,
                            right: 8,
                            bottom: 8,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                child: Row(
                                  children: [
                                    Icon(Icons.upload_file, color: cs.onSurfaceVariant, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '从资源管理器拖拽图片到此处替换',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: cs.onSurfaceVariant),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
