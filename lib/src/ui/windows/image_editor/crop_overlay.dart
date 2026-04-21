import 'package:flutter/material.dart';

enum _DragHandle {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  topEdge,
  bottomEdge,
  leftEdge,
  rightEdge,
  body,
}

/// A widget that displays a crop selection overlay on top of an image.
///
/// The [imageRect] is the actual on-screen rectangle where the image is displayed.
/// [normalizedCropRect] is the crop region in normalized 0..1 coordinates.
final class CropOverlay extends StatefulWidget {
  final Rect imageRect;
  final Rect? normalizedCropRect;
  final ValueChanged<Rect> onCropChanged;
  final VoidCallback onCropEnd;

  const CropOverlay({
    super.key,
    required this.imageRect,
    this.normalizedCropRect,
    required this.onCropChanged,
    required this.onCropEnd,
  });

  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

final class _CropOverlayState extends State<CropOverlay> {
  late Rect _currentCrop;
  _DragHandle? _activeHandle;
  Offset? _dragStart;
  Rect? _cropAtDragStart;

  static const double _handleSize = 20;
  static const double _minCropSize = 0.05;

  @override
  void initState() {
    super.initState();
    _currentCrop = widget.normalizedCropRect ??
        const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8);
  }

  @override
  void didUpdateWidget(covariant CropOverlay old) {
    super.didUpdateWidget(old);
    if (old.normalizedCropRect != widget.normalizedCropRect &&
        widget.normalizedCropRect != null) {
      _currentCrop = widget.normalizedCropRect!;
    }
  }

  Rect _normalizedToScreen(Rect normalized) {
    return Rect.fromLTWH(
      widget.imageRect.left + normalized.left * widget.imageRect.width,
      widget.imageRect.top + normalized.top * widget.imageRect.height,
      normalized.width * widget.imageRect.width,
      normalized.height * widget.imageRect.height,
    );
  }

  Rect _screenToNormalized(Rect screen) {
    return Rect.fromLTWH(
      (screen.left - widget.imageRect.left) / widget.imageRect.width,
      (screen.top - widget.imageRect.top) / widget.imageRect.height,
      screen.width / widget.imageRect.width,
      screen.height / widget.imageRect.height,
    );
  }

  _DragHandle? _hitTestHandle(Offset localPos) {
    final cropScreen = _normalizedToScreen(_currentCrop);
    const hs = _handleSize;
    const h2 = hs / 2;

    // Corner handles
    final corners = <(_DragHandle, Offset)>[
      (_DragHandle.topLeft, cropScreen.topLeft),
      (_DragHandle.topRight, cropScreen.topRight),
      (_DragHandle.bottomLeft, cropScreen.bottomLeft),
      (_DragHandle.bottomRight, cropScreen.bottomRight),
    ];
    for (final (type, pos) in corners) {
      if ((localPos - pos).distance < h2 + 4) return type;
    }

    // Edge handles
    if ((localPos.dy - cropScreen.top).abs() < 8 &&
        localPos.dx > cropScreen.left + hs &&
        localPos.dx < cropScreen.right - hs) {
      return _DragHandle.topEdge;
    }
    if ((localPos.dy - cropScreen.bottom).abs() < 8 &&
        localPos.dx > cropScreen.left + hs &&
        localPos.dx < cropScreen.right - hs) {
      return _DragHandle.bottomEdge;
    }
    if ((localPos.dx - cropScreen.left).abs() < 8 &&
        localPos.dy > cropScreen.top + hs &&
        localPos.dy < cropScreen.bottom - hs) {
      return _DragHandle.leftEdge;
    }
    if ((localPos.dx - cropScreen.right).abs() < 8 &&
        localPos.dy > cropScreen.top + hs &&
        localPos.dy < cropScreen.bottom - hs) {
      return _DragHandle.rightEdge;
    }

    // Body
    if (cropScreen.contains(localPos)) return _DragHandle.body;

    return null;
  }

  Rect _adjustCrop(_DragHandle handle, Rect start, double dx, double dy) {
    var left = start.left;
    var top = start.top;
    var right = start.right;
    var bottom = start.bottom;
    final normDx = dx / widget.imageRect.width;
    final normDy = dy / widget.imageRect.height;

    switch (handle) {
      case _DragHandle.topLeft:
        left = (left + normDx).clamp(0.0, right - _minCropSize);
        top = (top + normDy).clamp(0.0, bottom - _minCropSize);
      case _DragHandle.topRight:
        right = (right + normDx).clamp(left + _minCropSize, 1.0);
        top = (top + normDy).clamp(0.0, bottom - _minCropSize);
      case _DragHandle.bottomLeft:
        left = (left + normDx).clamp(0.0, right - _minCropSize);
        bottom = (bottom + normDy).clamp(top + _minCropSize, 1.0);
      case _DragHandle.bottomRight:
        right = (right + normDx).clamp(left + _minCropSize, 1.0);
        bottom = (bottom + normDy).clamp(top + _minCropSize, 1.0);
      case _DragHandle.topEdge:
        top = (top + normDy).clamp(0.0, bottom - _minCropSize);
      case _DragHandle.bottomEdge:
        bottom = (bottom + normDy).clamp(top + _minCropSize, 1.0);
      case _DragHandle.leftEdge:
        left = (left + normDx).clamp(0.0, right - _minCropSize);
      case _DragHandle.rightEdge:
        right = (right + normDx).clamp(left + _minCropSize, 1.0);
      case _DragHandle.body:
        var newLeft = left + normDx;
        var newTop = top + normDy;
        final w = right - left;
        final h = bottom - top;
        if (newLeft < 0) newLeft = 0;
        if (newTop < 0) newTop = 0;
        if (newLeft + w > 1) newLeft = 1 - w;
        if (newTop + h > 1) newTop = 1 - h;
        left = newLeft;
        top = newTop;
        right = newLeft + w;
        bottom = newTop + h;
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  MouseCursor _cursorForHandle(_DragHandle? handle) {
    return switch (handle) {
      _DragHandle.topLeft || _DragHandle.bottomRight =>
        SystemMouseCursors.resizeUpLeftDownRight,
      _DragHandle.topRight || _DragHandle.bottomLeft =>
        SystemMouseCursors.resizeUpRightDownLeft,
      _DragHandle.topEdge || _DragHandle.bottomEdge =>
        SystemMouseCursors.resizeUpDown,
      _DragHandle.leftEdge || _DragHandle.rightEdge =>
        SystemMouseCursors.resizeLeftRight,
      _DragHandle.body => SystemMouseCursors.move,
      _ => SystemMouseCursors.basic,
    };
  }

  void _onPanStart(DragStartDetails details) {
    final localPos = details.localPosition;
    _activeHandle = _hitTestHandle(localPos);
    _dragStart = localPos;
    _cropAtDragStart = _currentCrop;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_activeHandle == null || _dragStart == null || _cropAtDragStart == null) return;
    final delta = details.localPosition - _dragStart!;
    setState(() {
      _currentCrop = _adjustCrop(_activeHandle!, _cropAtDragStart!, delta.dx, delta.dy);
    });
  }

  void _onPanEnd() {
    widget.onCropChanged(_currentCrop);
    _activeHandle = null;
    _dragStart = null;
    _cropAtDragStart = null;
    widget.onCropEnd();
  }

  @override
  Widget build(BuildContext context) {
    final cropScreen = _normalizedToScreen(_currentCrop);

    return Positioned.fromRect(
      rect: widget.imageRect,
      child: MouseRegion(
        cursor: _cursorForHandle(_activeHandle),
        child: GestureDetector(
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: (_) => _onPanEnd(),
          child: Stack(
            children: [
              // Darkened overlay with cutout
              CustomPaint(
                size: Size(widget.imageRect.width, widget.imageRect.height),
                painter: _CropOverlayPainter(cropRect: cropScreen),
              ),
              // Crop rectangle border
              Positioned.fromRect(
                rect: cropScreen,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
              // Corner handles
              ..._buildCornerHandles(cropScreen),
              // Rule of thirds grid
              Positioned.fromRect(
                rect: cropScreen,
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _RuleOfThirdsPainter(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCornerHandles(Rect cropScreen) {
    const hs = _handleSize;
    const h2 = hs / 2;
    final handles = <(_DragHandle, Offset)>[
      (_DragHandle.topLeft, cropScreen.topLeft),
      (_DragHandle.topRight, cropScreen.topRight),
      (_DragHandle.bottomLeft, cropScreen.bottomLeft),
      (_DragHandle.bottomRight, cropScreen.bottomRight),
    ];
    return handles.map((e) {
      return Positioned(
        left: e.$2.dx - h2,
        top: e.$2.dy - h2,
        width: hs,
        height: hs,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.blue, width: 2),
          ),
        ),
      );
    }).toList();
  }
}

final class _CropOverlayPainter extends CustomPainter {
  final Rect cropRect;

  _CropOverlayPainter({required this.cropRect});

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    // Draw full-screen overlay
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final path = Path()..addRect(fullRect);
    // Cut out the crop rect
    path.addRect(cropRect);
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, overlayPaint);
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter old) =>
      old.cropRect != cropRect;
}

final class _RuleOfThirdsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 1;

    final w = size.width;
    final h = size.height;

    // Vertical lines
    canvas.drawLine(Offset(w / 3, 0), Offset(w / 3, h), paint);
    canvas.drawLine(Offset(2 * w / 3, 0), Offset(2 * w / 3, h), paint);

    // Horizontal lines
    canvas.drawLine(Offset(0, h / 3), Offset(w, h / 3), paint);
    canvas.drawLine(Offset(0, 2 * h / 3), Offset(w, 2 * h / 3), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
