import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'image_edit_state.dart';

/// Export the edited image to a new file.
Future<String> exportEditedImage({
  required String sourcePath,
  required ImageEditState state,
}) async {
  final bytes = await File(sourcePath).readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw Exception('无法解码图片');
  img.Image image = decoded;

  // 1. Apply rotation first
  if (state.rotation != 0) {
    image = switch (state.rotation) {
      1 => img.copyRotate(image, angle: 90),
      2 => img.copyRotate(image, angle: 180),
      3 => img.copyRotate(image, angle: 270),
      _ => image,
    };
  }

  // 2. Apply flips
  if (state.flippedH) {
    image = img.copyFlip(image, direction: img.FlipDirection.horizontal);
  }
  if (state.flippedV) {
    image = img.copyFlip(image, direction: img.FlipDirection.vertical);
  }

  // 3. Apply crop (in pixel coordinates)
  if (state.cropRect != null) {
    final rect = state.cropRect!;
    final x = (rect.left * image.width).round();
    final y = (rect.top * image.height).round();
    final w = (rect.width * image.width).round();
    final h = (rect.height * image.height).round();
    final cropped = img.copyCrop(image, x: x, y: y, width: w, height: h);
    image = cropped;
  }

  // 4. Burn doodle strokes
  for (final stroke in state.doodleStrokes) {
    if (stroke.points.length < 2) continue;
    final color = img.ColorRgba8(
      (stroke.color.r * 255).round(),
      (stroke.color.g * 255).round(),
      (stroke.color.b * 255).round(),
      (stroke.color.a * 255).round(),
    );
    final pixelStrokeWidth =
        (stroke.strokeWidth * image.width).round().clamp(1, 50);

    for (int i = 0; i < stroke.points.length - 1; i++) {
      final p1 = stroke.points[i];
      final p2 = stroke.points[i + 1];
      img.drawLine(
        image,
        x1: (p1.dx * image.width).round(),
        y1: (p1.dy * image.height).round(),
        x2: (p2.dx * image.width).round(),
        y2: (p2.dy * image.height).round(),
        color: color,
        thickness: pixelStrokeWidth,
      );
    }
  }

  // 5. Burn text overlays using Flutter's text rendering for quality
  for (final textItem in state.textItems) {
    if (textItem.text.isEmpty) continue;
    final pixelX = (textItem.position.dx * image.width).round();
    final pixelY = (textItem.position.dy * image.height).round();
    final pixelFontSize = (textItem.fontSize * image.width).round().clamp(8, 200);

    final result = await _burnText(
      image: image,
      text: textItem.text,
      x: pixelX,
      y: pixelY,
      fontSize: pixelFontSize.toDouble(),
      color: textItem.color,
    );
    image = result;
  }

  // 6. Encode and save to system temp directory
  final ext = sourcePath.contains('.')
      ? sourcePath.substring(sourcePath.lastIndexOf('.'))
      : '.png';
  final tempDir = Directory.systemTemp.path;
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final targetPath = '$tempDir${Platform.pathSeparator}xdnmb_edit_$timestamp$ext';

  final Uint8List encoded;
  if (ext.toLowerCase().contains('png')) {
    encoded = img.encodePng(image);
  } else if (ext.toLowerCase().contains('jpg') || ext.toLowerCase().contains('jpeg')) {
    encoded = img.encodeJpg(image, quality: 95);
  } else {
    encoded = img.encodePng(image);
  }
  await File(targetPath).writeAsBytes(encoded);

  return targetPath;
}

/// Render text using Flutter's text engine and composite it onto the image.
Future<img.Image> _burnText({
  required img.Image image,
  required String text,
  required int x,
  required int y,
  required double fontSize,
  required Color color,
}) async {
  // Estimate text size
  const maxWidth = 800;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final textStyle = ui.TextStyle(
    color: color,
    fontSize: fontSize,
    fontFamily: 'Microsoft YaHei',
  );
  final paragraphBuilder =
      ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.left))
        ..pushStyle(textStyle)
        ..addText(text);
  final paragraph = paragraphBuilder.build()
    ..layout(ui.ParagraphConstraints(width: maxWidth.toDouble()));
  final textW = paragraph.maxIntrinsicWidth.ceil();
  final textH = paragraph.height.ceil();

  if (textW <= 0 || textH <= 0) return image;

  // Draw text
  canvas.drawParagraph(paragraph, Offset.zero);
  final picture = recorder.endRecording();
  final uiImage = await picture.toImage(textW, textH);
  final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (byteData == null) return image;

  // Composite onto the image
  final textBytes = byteData.buffer.asUint8List();
  final textImg = img.Image.fromBytes(
    width: textW,
    height: textH,
    bytes: textBytes.buffer,
    order: img.ChannelOrder.rgba,
  );

  img.compositeImage(image, textImg, dstX: x, dstY: y);
  return image;
}
