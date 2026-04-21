import 'package:flutter/material.dart';

import 'image_edit_state.dart';

/// Displays draggable text items on top of the image.
final class DraggableTextOverlay extends StatelessWidget {
  final Rect imageRect;
  final List<TextOverlayItem> textItems;
  final int? activeTextIndex;
  final ValueChanged<int> onTextTapped;
  final ValueChanged<Offset> onTextMoved;
  final VoidCallback onAddText;

  const DraggableTextOverlay({
    super.key,
    required this.imageRect,
    required this.textItems,
    this.activeTextIndex,
    required this.onTextTapped,
    required this.onTextMoved,
    required this.onAddText,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (int i = 0; i < textItems.length; i++)
          _buildTextItem(context, i, textItems[i]),
        // Add text button
        Positioned(
          bottom: 80,
          right: 16,
          child: FloatingActionButton.small(
            onPressed: onAddText,
            child: const Icon(Icons.text_fields),
          ),
        ),
      ],
    );
  }

  Widget _buildTextItem(BuildContext context, int index, TextOverlayItem item) {
    final screenPos = Offset(
      imageRect.left + item.position.dx * imageRect.width,
      imageRect.top + item.position.dy * imageRect.height,
    );

    if (item.isEditing) {
      return Positioned(
        left: screenPos.dx - 100,
        top: screenPos.dy - 20,
        width: 200,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '输入文字...',
              contentPadding: EdgeInsets.all(8),
              border: OutlineInputBorder(),
            ),
            style: TextStyle(
              color: item.color,
              fontSize: item.fontSize * imageRect.width,
            ),
            onSubmitted: (text) {
              onTextMoved(Offset.zero); // trigger update
            },
          ),
        ),
      );
    }

    return Positioned(
      left: screenPos.dx,
      top: screenPos.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          final newScreenPos = screenPos + details.delta;
          final normalized = Offset(
            (newScreenPos.dx - imageRect.left) / imageRect.width,
            (newScreenPos.dy - imageRect.top) / imageRect.height,
          );
          onTextMoved(normalized);
        },
        onTap: () => onTextTapped(index),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            border: activeTextIndex == index
                ? Border.all(color: Colors.blue, width: 2)
                : null,
          ),
          child: Text(
            item.text,
            style: TextStyle(
              color: item.color,
              fontSize: item.fontSize * imageRect.width,
              fontWeight: FontWeight.bold,
              shadows: const [
                Shadow(color: Colors.black54, blurRadius: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
