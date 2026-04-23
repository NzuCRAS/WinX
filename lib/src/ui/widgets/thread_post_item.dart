import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xdnmb_api/xdnmb_api.dart' as api;

import '../../app/settings_controller.dart';
import 'post_content.dart';
import 'thread_post_image.dart';

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

String _cookieUserHash(api.PostBase p) {
  final n = p.userHash.trim();
  return n.isEmpty ? '无名氏' : n;
}

/// Renders a single post inside a thread.
///
/// Optimizations:
/// - No animation wrapper when not flashing (avoids TweenAnimationBuilder
///   overhead for every item).
/// - All style computation happens inside the widget, keeping the parent's
///   itemBuilder lean.
final class ThreadPostItem extends StatelessWidget {
  final api.PostBase post;
  final int index;
  final String? poUserHash;
  final int? flashPostId;
  final int flashPhase;
  final VoidCallback? onReply;
  final bool isSearchMatch;

  /// IDs of all posts currently loaded in the thread. When the user taps a
  /// `>>No.xxx` reference that is in this list, [onRefInThread] is called
  /// instead of opening an external reference dialog.
  final List<int>? inThreadPostIds;
  final ValueChanged<int>? onRefInThread;

  const ThreadPostItem({
    super.key,
    required this.post,
    required this.index,
    this.poUserHash,
    this.flashPostId,
    required this.flashPhase,
    this.onReply,
    this.isSearchMatch = false,
    this.inThreadPostIds,
    this.onRefInThread,
  });

  @override
  Widget build(BuildContext context) {
    final shouldFlash = flashPostId != null && post.id == flashPostId;
    final content = _buildContent(context);
    final cs = Theme.of(context).colorScheme;

    Widget wrap(Widget child) {
      final bg = isSearchMatch
          ? cs.primaryContainer.withValues(alpha: 0.35)
          : null;
      return Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: child,
      );
    }

    if (!shouldFlash) {
      return wrap(content);
    }

    final targetT = (flashPhase.isEven) ? 1.0 : 0.0;
    final flashColor = cs.onSurface.withValues(alpha: 0.14);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: targetT),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeInOut,
      builder: (context, t, child) {
        return Container(
          color: Color.lerp(
            isSearchMatch ? cs.primaryContainer.withValues(alpha: 0.35) : null,
            flashColor,
            t,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: child,
        );
      },
      child: content,
    );
  }

  Widget _buildContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (index == 0 && post.isSage == true) ...[
          _buildSageLabel(context),
          const SizedBox(height: 4),
        ],
        _buildMetaRow(context),
        const SizedBox(height: 8),
        ThreadPostImage(post: post),
        PostContent(
          text: post.content,
          postId: post.id,
          inThreadPostIds: inThreadPostIds,
          onRefInThread: onRefInThread,
        ),
      ],
    );
  }

  Widget _buildSageLabel(BuildContext context) {
    final baseSize = Theme.of(context).textTheme.labelSmall?.fontSize ?? 12;
    final settings = context.read<SettingsController>();
    return Text(
      'SAGE ↓',
      style: TextStyle(
        color: Theme.of(context).colorScheme.error,
        fontWeight: settings.uiFontWeight,
        fontSize: (baseSize * 1.25).clamp(10, 999),
        fontFamily: settings.uiFontFamily,
        fontFamilyFallback: settings.uiFontFallback,
      ),
    );
  }

  Widget _buildMetaRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.read<SettingsController>();
    final metaStyle = TextStyle(
      fontSize: Theme.of(context).textTheme.labelMedium?.fontSize,
      height: Theme.of(context).textTheme.labelMedium?.height,
      fontWeight: settings.contentFontWeight,
      fontFamily: settings.contentFontFamily,
      fontFamilyFallback: settings.contentFontFallback,
    );
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  _cookieUserHash(post),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: metaStyle.copyWith(
                    color: post.isAdmin ? cs.error : cs.primary,
                    fontWeight: post.isAdmin ? FontWeight.w700 : null,
                  ),
                ),
              ),
              if (poUserHash != null && post.userHash == poUserHash) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'PO',
                    style: metaStyle.copyWith(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: Theme.of(context).textTheme.labelSmall?.fontSize,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Text(
              _formatToSeconds(post.postTime),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: metaStyle.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onReply,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  'No.${post.id}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: metaStyle.copyWith(
                    color: cs.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
