import 'package:flutter/material.dart';

enum EditorTool { none, crop, text, doodle }

/// A single text overlay item.
final class TextOverlayItem {
  final String text;
  final Offset position; // Normalized 0..1 relative to image bounds
  final double fontSize; // Relative to image width (e.g., 0.05 = 5%)
  final Color color;
  final bool isEditing;

  const TextOverlayItem({
    required this.text,
    required this.position,
    this.fontSize = 0.05,
    this.color = Colors.white,
    this.isEditing = false,
  });

  TextOverlayItem copyWith({
    String? text,
    Offset? position,
    double? fontSize,
    Color? color,
    bool? isEditing,
  }) =>
      TextOverlayItem(
        text: text ?? this.text,
        position: position ?? this.position,
        fontSize: fontSize ?? this.fontSize,
        color: color ?? this.color,
        isEditing: isEditing ?? this.isEditing,
      );
}

/// A single doodle stroke.
final class DoodleStroke {
  final List<Offset> points; // Normalized 0..1
  final Color color;
  final double strokeWidth; // Relative to image width

  const DoodleStroke({
    required this.points,
    this.color = Colors.red,
    this.strokeWidth = 0.005,
  });
}

/// Immutable state of all image edits.
final class ImageEditState {
  final int rotation; // 0, 1, 2, 3 (quarter turns)
  final bool flippedH;
  final bool flippedV;
  final Rect? cropRect; // Normalized 0..1, null = no crop
  final List<TextOverlayItem> textItems;
  final List<DoodleStroke> doodleStrokes;
  final int? activeTextIndex;
  final bool isDoodling;

  const ImageEditState({
    this.rotation = 0,
    this.flippedH = false,
    this.flippedV = false,
    this.cropRect,
    this.textItems = const [],
    this.doodleStrokes = const [],
    this.activeTextIndex,
    this.isDoodling = false,
  });

  ImageEditState copyWith({
    int? rotation,
    bool? flippedH,
    bool? flippedV,
    Rect? cropRect,
    List<TextOverlayItem>? textItems,
    List<DoodleStroke>? doodleStrokes,
    int? activeTextIndex,
    bool? isDoodling,
    bool clearCropRect = false,
  }) =>
      ImageEditState(
        rotation: rotation ?? this.rotation,
        flippedH: flippedH ?? this.flippedH,
        flippedV: flippedV ?? this.flippedV,
        cropRect: clearCropRect ? null : (cropRect ?? this.cropRect),
        textItems: textItems ?? this.textItems,
        doodleStrokes: doodleStrokes ?? this.doodleStrokes,
        activeTextIndex: activeTextIndex ?? this.activeTextIndex,
        isDoodling: isDoodling ?? this.isDoodling,
      );

  bool get hasEdits =>
      rotation != 0 ||
      flippedH ||
      flippedV ||
      cropRect != null ||
      textItems.isNotEmpty ||
      doodleStrokes.isNotEmpty;
}
