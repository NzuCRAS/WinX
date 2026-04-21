import 'package:flutter/material.dart';

import 'image_edit_state.dart';

final class EditorToolbar extends StatelessWidget {
  final EditorTool activeTool;
  final bool hasEdits;
  final bool isExporting;
  final ValueChanged<EditorTool> onToolChanged;
  final VoidCallback onReset;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;
  final VoidCallback onFlipH;
  final VoidCallback onFlipV;
  final VoidCallback onApply;

  const EditorToolbar({
    super.key,
    required this.activeTool,
    required this.hasEdits,
    this.isExporting = false,
    required this.onToolChanged,
    required this.onReset,
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.onFlipH,
    required this.onFlipV,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.black.withValues(alpha: 0.4),
          ],
        ),
      ),
      child: SafeArea(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            _ToolButton(
              icon: Icons.restart_alt,
              tooltip: '重置',
              onPressed: hasEdits ? onReset : null,
            ),
            _ToolButton(
              icon: Icons.rotate_left,
              tooltip: '向左旋转',
              onPressed: onRotateLeft,
            ),
            _ToolButton(
              icon: Icons.rotate_right,
              tooltip: '向右旋转',
              onPressed: onRotateRight,
            ),
            _ToolButton(
              icon: Icons.flip,
              tooltip: '水平翻转',
              onPressed: onFlipH,
            ),
            _ToolButton(
              icon: Icons.flip_camera_android,
              tooltip: '垂直翻转',
              onPressed: onFlipV,
            ),
            const _Divider(),
            _ToolButton(
              icon: isExporting ? Icons.hourglass_top : Icons.check,
              tooltip: '应用并替换',
              color: cs.primary,
              onPressed: isExporting ? null : onApply,
            ),
          ],
        ),
      ),
    );
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              icon,
              color: onPressed == null ? Colors.white38 : (color ?? Colors.white),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

final class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        width: 1,
        height: 28,
        color: Colors.white.withValues(alpha: 0.2),
      ),
    );
  }
}
