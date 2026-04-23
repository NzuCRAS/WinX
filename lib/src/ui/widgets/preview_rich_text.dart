import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/settings_controller.dart';
import 'list_preview.dart';

/// Lightweight rich renderer for list previews.
///
/// Goals:
/// - keep performance predictable (no network, no dialogs)
/// - apply simple formatting: greentext lines and spoiler bars
/// - spoiler bars are *not* interactive in lists
final class PreviewRichText extends StatelessWidget {
  final String text;
  final int maxLines;
  final TextStyle? style;

  const PreviewRichText({
    super.key,
    required this.text,
    required this.maxLines,
    this.style,
  });

  static const String _spoilerToken = '[spoiler]';

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final normalized = normalizeForListPreview(text);
    final showLineBreak = context.select(
      (SettingsController s) => s.showLineBreakIndicator,
    );
    final lineBreakColor = Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.45);

    final spans = <InlineSpan>[];
    final lines = normalized.split('\n');
    final green = _greentextColor(Theme.of(context));

    for (var li = 0; li < lines.length; li++) {
      final line = lines[li];

      // Split line by spoiler tokens.
      var cursor = 0;
      while (cursor < line.length) {
        final idx = line.indexOf(_spoilerToken, cursor);
        if (idx < 0) {
          final chunk = line.substring(cursor);
          spans.add(TextSpan(
            text: chunk,
            style: line.startsWith('>') ? baseStyle.copyWith(color: green) : null,
          ));
          break;
        }

        if (idx > cursor) {
          final chunk = line.substring(cursor, idx);
          spans.add(TextSpan(
            text: chunk,
            style: line.startsWith('>') ? baseStyle.copyWith(color: green) : null,
          ));
        }

        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _SpoilerBar(height: baseStyle.fontSize == null ? 16 : (baseStyle.fontSize! + 2)),
          ),
        );

        cursor = idx + _spoilerToken.length;
      }

      if (li != lines.length - 1) {
        if (showLineBreak) {
          spans.add(TextSpan(
            text: ' \u{21A9}',
            style: TextStyle(color: lineBreakColor, fontSize: (baseStyle.fontSize ?? 14) * 0.82),
          ));
        }
        spans.add(const TextSpan(text: '\n'));
      }
    }

    return Text.rich(
      TextSpan(style: baseStyle, children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  static Color _greentextColor(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? Colors.lightGreenAccent.shade200
        : Colors.green.shade700;
  }
}

final class _SpoilerBar extends StatelessWidget {
  final double height;

  const _SpoilerBar({required this.height});

  @override
  Widget build(BuildContext context) {
    // Pure black bar without any text.
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      width: 56,
      height: height,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
