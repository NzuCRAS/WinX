import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/settings_controller.dart';
import 'list_preview.dart';
import 'preview_rich_text.dart';
import 'cdn_fallback_image.dart';

/// A list item that matches the normal forum thread list layout:
/// - optional thumbnail on the left
/// - optional title (only shown when not empty and not "无标题")
/// - content preview with ellipsis
/// - meta line: cookie · timestamp(to seconds)
final class ThreadListItem extends StatelessWidget {
  final String? thumbUrl;
  final String? title;
  final String content;
  final String cookie;
  final DateTime time;
  final bool isAdmin;
  final bool isSage;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;

  const ThreadListItem({
    super.key,
    required this.thumbUrl,
    required this.title,
    required this.content,
    required this.cookie,
    required this.time,
    this.isAdmin = false,
  this.isSage = false,
    this.onTap,
    this.onSecondaryTap,
  });

  bool get _hasTitle {
    final t = title?.trim() ?? '';
    return t.isNotEmpty && t != '无标题';
  }

  String _formatToSeconds(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsController>();

    final t = title?.trim();
    final preview = (() {
      final raw = content.trim();
      if (raw.isEmpty) return '（无内容）';
      return normalizeForListPreview(raw);
    })();

    var cookieText = cookie.trim().isEmpty ? '无名氏' : cookie.trim();
  // User requirement: cookie should always be blue across lists.
  // Keep admin red.
  final cookieColor = isAdmin ? cs.error : cs.primary;

    // Special marker used by PostHistoryPage:
    // - prefix with [reply] to apply red color to the two chars "回串".
    final replyMarker = '[reply]';
    final isReplyLabel = cookieText.startsWith(replyMarker);
    if (isReplyLabel) {
      cookieText = cookieText.substring(replyMarker.length);
    }
    final base = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontSize: (settings.contentFontSize - 2).clamp(10, 999),
          height: settings.contentLineHeight,
          fontFamily: settings.fontFamily.isEmpty ? null : settings.fontFamily,
        );

    final tile = ListTile(
      leading: (thumbUrl == null || thumbUrl!.trim().isEmpty)
          ? null
          : ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CdnFallbackCachedNetworkImage(
                imageUrl: thumbUrl!,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  width: 56,
                  height: 56,
                  color: cs.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  color: cs.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_hasTitle)
            Text(
              t!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontFamily: settings.fontFamily.isEmpty ? null : settings.fontFamily,
              ),
            ),
          PreviewRichText(
            text: preview,
            maxLines: settings.previewMaxLines,
            style: TextStyle(
              fontSize: settings.contentFontSize,
              height: settings.contentLineHeight,
              fontFamily: settings.fontFamily.isEmpty ? null : settings.fontFamily,
            ),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              style: base,
              children: [
                if (isSage) ...[
                  TextSpan(
                    text: 'SAGE ↓  ',
                    style: base?.copyWith(
                      color: cs.error,
                      fontWeight: FontWeight.w800,
                      fontSize:
                          ((base.fontSize ?? 12) * 1.25).clamp(10, 999),
                    ),
                  ),
                ],
                if (isReplyLabel && cookieText.startsWith('回串')) ...[
                  TextSpan(
                    text: '回串',
                    style: base?.copyWith(
                      color: cs.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text: cookieText.substring(2),
                    style: base?.copyWith(
                      color: cookieColor,
                      fontWeight: isAdmin ? FontWeight.w700 : null,
                    ),
                  ),
                ] else
                  TextSpan(
                    text: cookieText,
                    style: base?.copyWith(
                      color: cookieColor,
                      fontWeight: isAdmin ? FontWeight.w700 : null,
                    ),
                  ),
                const TextSpan(text: '  '),
                TextSpan(
                  text: _formatToSeconds(time),
                  style: base?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      // Only set onTap on ListTile if there's no secondary tap handler.
      // If onSecondaryTap exists, InkWell will handle both tap events below.
      onTap: onSecondaryTap == null ? onTap : null,
    );

    if (onSecondaryTap == null) return tile;
    return InkWell(
      onTap: onTap,
      onSecondaryTap: onSecondaryTap,
      child: tile,
    );
  }
}
