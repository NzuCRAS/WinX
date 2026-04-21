import 'package:flutter/material.dart';

import 'image_edit_state.dart';

/// Paints doodle strokes and text overlay previews on top of the image.
final class ImageEditorPainter extends CustomPainter {
  final ImageEditState state;
  final Size imageSize;

  ImageEditorPainter({required this.state, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    final imageRect = _calculateImageRect(size, imageSize);

    // Paint doodle strokes
    for (final stroke in state.doodleStrokes) {
      if (stroke.points.length < 2) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth * imageRect.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final path = Path();
      final first = _normalizedToScreen(stroke.points.first, imageRect);
      path.moveTo(first.dx, first.dy);
      for (int i = 1; i < stroke.points.length; i++) {
        final point = _normalizedToScreen(stroke.points[i], imageRect);
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }

    // Paint text items (preview only - editing text is handled by widgets)
    for (final textItem in state.textItems) {
      if (textItem.isEditing) continue;
      final pos = _normalizedToScreen(textItem.position, imageRect);
      final textSpan = TextSpan(
        text: textItem.text,
        style: TextStyle(
          color: textItem.color,
          fontSize: textItem.fontSize * imageRect.width,
          fontWeight: FontWeight.bold,
          shadows: const [
            Shadow(color: Colors.black54, blurRadius: 2, offset: Offset(1, 1)),
          ],
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, pos);
    }
  }

  Offset _normalizedToScreen(Offset normalized, Rect imageRect) {
    return Offset(
      imageRect.left + normalized.dx * imageRect.width,
      imageRect.top + normalized.dy * imageRect.height,
    );
  }

  Rect _calculateImageRect(Size widgetSize, Size imageSize) {
    final fit = applyBoxFit(BoxFit.contain, imageSize, widgetSize);
    final destinationSize = fit.destination;
    final offset = Alignment.center.inscribe(destinationSize, Offset.zero & widgetSize);
    return offset;
  }

  @override
  bool shouldRepaint(covariant ImageEditorPainter old) =>
      old.state != state || old.imageSize != imageSize;
}
