import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:xdnmb_api/xdnmb_api.dart' as api;

import '../../app/composer_controller.dart';
import '../../app/cookie_controller.dart';
import '../../data/cookie_store.dart';
import 'advanced_dice.dart';

/// The core composer form: cookie selector, title, content editor,
/// image upload, watermark, emoticons.
///
/// Consumes [ComposerController] for all mutable state.
final class ComposerEditor extends StatelessWidget {
  final ComposerController controller;
  final VoidCallback? onSubmit;

  const ComposerEditor({
    super.key,
    required this.controller,
    this.onSubmit,
  });

  Future<void> _pickImage() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'],
    );
    final path = res?.files.single.path;
    if (path == null || path.trim().isEmpty) return;
    controller.setImagePath(path);
    controller.onImageChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cookie = context.watch<CookieController>();
    final slotItems = cookie.slots;

    final selectedSlot = slotItems.cast<CookieSlot?>().firstWhere(
          (s) => s?.id == controller.selectedCookieSlotId,
          orElse: () => null,
        );

    final postSlotLabel = selectedSlot?.name ??
        cookie.defaultPostCookieSlot?.name ??
        (slotItems.isEmpty ? '（未导入饼干）' : '（未选择）');

    final cs = Theme.of(context).colorScheme;
    final isReply = controller.isReply;

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cookie selector
            Row(
              children: [
                const Icon(Icons.cookie_outlined),
                const SizedBox(width: 8),
                const Text('发言饼干：'),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: controller.selectedCookieSlotId,
                    items: slotItems
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(s.name ?? '未命名饼干'),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: controller.posting
                        ? null
                        : (v) {
                            controller.setSelectedCookieSlotId(v);
                            controller.onCookieChanged();
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

            // Title (new thread only)
            if (!isReply) ...[
              TextField(
                controller: controller.titleCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '标题（可选）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Content editor
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 200, maxHeight: 480),
              child: TextField(
                controller: controller.contentCtrl,
                focusNode: controller.focusNode,
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

            // Image picker
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: controller.posting ? null : _pickImage,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(
                      controller.imagePath == null
                          ? '选择图片（最多1张）'
                          : '已选择：${File(controller.imagePath!).uri.pathSegments.last}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '移除图片',
                  onPressed: controller.posting || controller.imagePath == null
                      ? null
                      : () {
                          controller.setImagePath(null);
                          controller.onImageChanged();
                        },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Watermark + draft saved + emoticon
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                InkWell(
                  onTap: controller.posting
                      ? null
                      : () {
                          controller.setWatermark(!controller.watermark);
                          controller.onWatermarkChanged();
                        },
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: controller.watermark,
                          onChanged: controller.posting
                              ? null
                              : (v) {
                                  controller.setWatermark(v ?? false);
                                  controller.onWatermarkChanged();
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
                if (controller.showDraftSaved)
                  Text(
                    '已自动保存',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                OutlinedButton.icon(
                  onPressed: controller.posting
                      ? null
                      : () {
                          controller.insertText('[h] [/h]');
                          if (controller.focusNode.canRequestFocus) {
                            controller.focusNode.requestFocus();
                          }
                        },
                  icon: const Icon(Icons.shield_outlined, size: 18),
                  label: const Text('防剧透'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: controller.posting
                      ? null
                      : () async {
                          final result = await showAdvancedDiceDialog(context);
                          if (result != null) {
                            controller.insertText(result);
                            if (controller.focusNode.canRequestFocus) {
                              controller.focusNode.requestFocus();
                            }
                          }
                        },
                  icon: const Icon(Icons.casino_outlined, size: 18),
                  label: const Text('骰子'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                _EmoticonDropdown(
                  expanded: controller.emoticonExpanded,
                  onExpandedChanged: controller.posting
                      ? null
                      : (v) {
                          controller.setEmoticonExpanded(v);
                        },
                  onInsert: (t) {
                    controller.insertText(t);
                    if (controller.focusNode.canRequestFocus) {
                      controller.focusNode.requestFocus();
                    }
                  },
                  backgroundColor: cs.surface,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Emoticon widgets (extracted from composer_page.dart) ──

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
            const baseFontSize = 13.0;
            const cellH = 36.0;
            const minCellW = 92.0;
            final crossAxisCount = math.max(2, (maxW / minCellW).floor());
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
                  final colW =
                      (maxW - 6 * (crossAxisCount - 1)) / crossAxisCount;
                  final estCharW = 0.62;
                  final maxChars =
                      math.max(4.0, (colW - 18) / (baseFontSize * estCharW));
                  final scale =
                      (maxChars / e.name.length).clamp(0.72, 1.0);
                  final fontSize = baseFontSize * scale;
                  return EmoticonButton(
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

final class EmoticonButton extends StatefulWidget {
  final String name;
  final String text;
  final double fontSize;
  final void Function(String text) onInsert;

  const EmoticonButton({
    super.key,
    required this.name,
    required this.text,
    required this.fontSize,
    required this.onInsert,
  });

  @override
  State<EmoticonButton> createState() => EmoticonButtonState();
}

final class EmoticonButtonState extends State<EmoticonButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      // Duration.zero: copy happens as soon as GestureDetector confirms long
      // press (default ~500ms). Total ~0.5s.
      duration: Duration.zero,
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
