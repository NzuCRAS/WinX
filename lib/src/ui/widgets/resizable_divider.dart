import 'package:flutter/material.dart';

/// A vertical divider that can be dragged horizontally to resize an adjacent
/// panel. Shows a resize cursor on hover.
final class ResizableDivider extends StatefulWidget {
  final double width;
  final double minWidth;
  final double maxWidth;
  final ValueChanged<double> onWidthChanged;

  const ResizableDivider({
    super.key,
    required this.width,
    required this.minWidth,
    required this.maxWidth,
    required this.onWidthChanged,
  });

  @override
  State<ResizableDivider> createState() => _ResizableDividerState();
}

final class _ResizableDividerState extends State<ResizableDivider> {
  bool _hovering = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = _hovering || _dragging;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onHorizontalDragCancel: () => setState(() => _dragging = false),
        onHorizontalDragUpdate: (details) {
          final newWidth = widget.width - details.delta.dx;
          widget.onWidthChanged(
            newWidth.clamp(widget.minWidth, widget.maxWidth),
          );
        },
        child: SizedBox(
          width: 8,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: active ? 3 : 1,
              color: active
                  ? cs.primary.withValues(alpha: 0.6)
                  : cs.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}
