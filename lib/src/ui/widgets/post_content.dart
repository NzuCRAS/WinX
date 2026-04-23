import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xdnmb_api/xdnmb_api.dart' as api;

import '../../app/app_state.dart';
import '../../app/settings_controller.dart';

// ── Reference dialog shared state ──

final _refDialogKey = GlobalKey<ReferenceDialogState>();
var _refDialogOpen = false;

/// Shows a reference dialog, reusing an existing one if already open.
Future<void> showReferenceDialog(BuildContext context, int postId) async {
  final st = _refDialogKey.currentState;
  if (_refDialogOpen && st != null) {
    st.push(postId);
    return;
  }

  _refDialogOpen = true;
  try {
    await showDialog(
      context: context,
      builder: (context) => ReferenceDialog(
        key: _refDialogKey,
        initialPostId: postId,
      ),
    );
  } finally {
    _refDialogOpen = false;
  }
}

/// Semi-rich text renderer:
/// - clickable `>>123456` references (preview via API)
/// - clickable URLs
/// - greentext lines (starting with `>`)
/// - spoiler blocks `[h]...[/h]` (tap to reveal)
///
/// All gesture recognizers are created fresh on every build and disposed either
/// before the next build or in [dispose], preventing memory leaks.
final class PostContent extends StatefulWidget {
  final String text;
  final int postId;

  /// If provided, `>>No.xxx` references whose postId is in this list will
  /// trigger [onRefInThread] instead of opening the external reference dialog.
  final List<int>? inThreadPostIds;

  /// Called when the user taps a `>>No.xxx` reference that exists in the
  /// current thread (i.e. [inThreadPostIds] contains the referenced id).
  final ValueChanged<int>? onRefInThread;

  const PostContent({
    super.key,
    required this.text,
    required this.postId,
    this.inThreadPostIds,
    this.onRefInThread,
  });

  @override
  State<PostContent> createState() => _PostContentState();
}

final class _PostContentState extends State<PostContent> {
  static final _ref = RegExp(r'>>\s*(?:No\.)?\s*(\d{1,10})');
  // Exclude common trailing punctuation and whitespace from the match.
  static final _url = RegExp(r'(https?://[^\s"<>(){}\[\]]+)');
  static final _spoiler =
      RegExp(r'\[h\]([\s\S]*?)\[\/h\]', caseSensitive: false);
  // Advanced dice prefix: bold the digit before [n,m].
  static final _dicePrefix = RegExp(r'(\d+)\[(\d+),(\d+)\]');

  /// Recognizers created during the last build. Disposed before the next build
  /// and in [dispose].
  final List<GestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _tapRecognizer(VoidCallback onTap) {
    final r = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(r);
    return r;
  }

  @override
  Widget build(BuildContext context) {
    // Clean up recognizers from previous build before creating new ones.
    _disposeRecognizers();

    final spans = <InlineSpan>[];
    final s = _normalizePostText(widget.text);

    // Use Selectors to only rebuild when the specific fields change,
    // rather than watching the entire SettingsController.
    final fontSize = context.select(
      (SettingsController s) => s.contentFontSize,
    );
    final lineHeight = context.select(
      (SettingsController s) => s.contentLineHeight,
    );
    final fontFamily = context.select(
      (SettingsController s) => s.contentFontFamily,
    );
    final fontFamilyFallback = context.select(
      (SettingsController s) => s.contentFontFallback,
    );
    final fontWeight = context.select(
      (SettingsController s) => s.contentFontWeight,
    );
    final showLineBreak = context.select(
      (SettingsController s) => s.showLineBreakIndicator,
    );

    spans.addAll(_buildInlineSpans(context, s, showLineBreak: showLineBreak));

    return SelectableText.rich(
      TextSpan(
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: fontSize,
              height: lineHeight,
              fontWeight: fontWeight,
              fontFamily: fontFamily,
              fontFamilyFallback: fontFamilyFallback,
            ),
        children: spans,
      ),
    );
  }

  List<InlineSpan> _buildInlineSpans(BuildContext context, String s, {required bool showLineBreak}) {
    final parts = <InlineSpan>[];
    var cursor = 0;
    for (final match in _spoiler.allMatches(s)) {
      if (match.start > cursor) {
        parts.addAll(_buildInlineSpansNoSpoiler(
            context, s.substring(cursor, match.start), showLineBreak: showLineBreak));
      }

      final inner = match.group(1) ?? '';
      parts.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _SpoilerBlock(text: inner),
        ),
      );
      cursor = match.end;
    }

    if (cursor < s.length) {
      parts.addAll(_buildInlineSpansNoSpoiler(context, s.substring(cursor), showLineBreak: showLineBreak));
    }
    return parts;
  }

  List<InlineSpan> _buildInlineSpansNoSpoiler(
      BuildContext context, String s, {required bool showLineBreak}) {
    final spans = <InlineSpan>[];
    final lines = s.split('\n');
    final green = _greentextColor(Theme.of(context));
    final lineBreakColor = Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.45);

    for (int li = 0; li < lines.length; li++) {
      final line = lines[li];
      spans.addAll(_buildInlineSpansLeaf(
        context,
        line,
        baseStyle: line.startsWith('>') ? TextStyle(color: green) : null,
      ));
      if (li != lines.length - 1) {
        if (showLineBreak) {
          spans.add(TextSpan(
            text: ' \u{21A9}',
            style: TextStyle(color: lineBreakColor, fontSize: (Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14) * 0.82),
          ));
        }
        spans.add(const TextSpan(text: '\n'));
      }
    }

    return spans;
  }

  List<InlineSpan> _buildInlineSpansLeaf(
    BuildContext context,
    String s, {
    TextStyle? baseStyle,
  }) {
    final spans = <InlineSpan>[];
    int i = 0;
    while (i < s.length) {
      final refMatch = _ref.matchAsPrefix(s, i);
      final urlMatch = _url.matchAsPrefix(s, i);

      if (refMatch != null) {
        final id = int.tryParse(refMatch.group(1) ?? '');
        final raw = refMatch.group(0)!;
        spans.add(TextSpan(
          text: raw,
          style: (baseStyle ?? const TextStyle()).copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
          recognizer: _tapRecognizer(() async {
            if (id == null) return;

            // If the referenced post is in the current thread, jump directly.
            final ids = widget.inThreadPostIds;
            final onInThread = widget.onRefInThread;
            if (ids != null && onInThread != null && ids.contains(id)) {
              onInThread(id);
              return;
            }

            await showReferenceDialog(context, id);
          }),
        ));
        i = refMatch.end;
        continue;
      }

      if (urlMatch != null) {
        final fullMatch = urlMatch.group(1)!;
        // Trim trailing punctuation (ASCII + common CJK) so the link doesn't
        // include commas, periods, quotes, etc.
        final raw = fullMatch.replaceAll(
          RegExp(r'''[.,;:!?)\]}'"\s。，、；：！？）】》」』]+$'''),
          '',
        );
        final trailing = fullMatch.substring(raw.length);

        spans.add(TextSpan(
          text: raw,
          style: (baseStyle ?? const TextStyle()).copyWith(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
          recognizer: _tapRecognizer(() {
            final uri = Uri.tryParse(raw);
            if (uri != null) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }),
        ));

        if (trailing.isNotEmpty) {
          spans.add(TextSpan(text: trailing, style: baseStyle));
        }
        i = urlMatch.end;
        continue;
      }

      final diceMatch = _dicePrefix.matchAsPrefix(s, i);
      if (diceMatch != null) {
        final prefix = diceMatch.group(1)!;
        final n = diceMatch.group(2)!;
        final m = diceMatch.group(3)!;
        spans.add(TextSpan(
          text: prefix,
          style: (baseStyle ?? const TextStyle()).copyWith(
            fontWeight: FontWeight.bold,
          ),
        ));
        spans.add(TextSpan(text: '[$n,$m]', style: baseStyle));
        i = diceMatch.end;
        continue;
      }

      final next = [
        _ref.firstMatch(s.substring(i)),
        _url.firstMatch(s.substring(i)),
        _dicePrefix.firstMatch(s.substring(i)),
      ].whereType<RegExpMatch>().map((m) => m.start).fold<int?>(
          null, (min, v) => (min == null || v < min) ? v : min);

      final end = next == null ? s.length : i + next;
      spans.add(TextSpan(text: s.substring(i, end), style: baseStyle));
      i = end;
    }
    return spans;
  }

  static Color _greentextColor(ThemeData theme) {
    final b = theme.brightness;
    return b == Brightness.dark
        ? Colors.lightGreenAccent.shade200
        : Colors.green.shade700;
  }
}

/// Spoiler block: shows a black bar when collapsed; reveals rich content
/// (with ref/URL/greentext support) when tapped. Revealed content is rendered
/// as a nested [PostContent] so it participates in text selection.
final class _SpoilerBlock extends StatefulWidget {
  final String text;

  const _SpoilerBlock({required this.text});

  @override
  State<_SpoilerBlock> createState() => _SpoilerBlockState();
}

final class _SpoilerBlockState extends State<_SpoilerBlock> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!_revealed) {
      return InkWell(
        onTap: () => setState(() => _revealed = true),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const SizedBox(width: 72, height: 18),
        ),
      );
    }

    return InkWell(
      onTap: () => setState(() => _revealed = false),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: PostContent(
          text: _normalizePostText(widget.text),
          postId: 0,
        ),
      ),
    );
  }
}

/// Normalize server-provided HTML-ish content used in dialogs (e.g. notice,
/// forum rules) into plain text.
///
/// The API sometimes returns fragments containing tags like `<br>`, `<p>`,
/// `&bull;`, and `<a href="...">...`.
///
/// We keep it intentionally lightweight (no full HTML parser dependency):
/// - convert line breaks (`<br>`, `</p>`) into `\n`
/// - convert bullet entities into `•`
/// - convert anchors to `text（url）`
/// - strip remaining tags, decode a few common entities
/// - normalize whitespace/newlines
String normalizeDialogHtml(String input) {
  var s = input;

  // Font color/style wrappers: keep content, drop the tags.
  s = s.replaceAllMapped(
    RegExp(r'<\s*font\b[^>]*>(.*?)<\s*\/font\s*>',
        caseSensitive: false, dotAll: true),
    (m) => m.group(1) ?? '',
  );

  // Break lines.
  s = s.replaceAll(RegExp(r'<\s*br\s*\/?>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<\s*\/p\s*>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<\s*p\b[^>]*>', caseSensitive: false), '');

  // Bullet.
  s = s.replaceAll('&bull;', '•');
  s = s.replaceAll('&#8226;', '•');

  // Anchor: <a href="url">text</a> => text（url）
  s = s.replaceAllMapped(
    RegExp(
      r'''<\s*a\b[^>]*href\s*=\s*(["\u0027])(.*?)\1[^>]*>(.*?)<\s*\/a\s*>''',
      caseSensitive: false,
      dotAll: true,
    ),
    (m) {
      final url = (m.group(2) ?? '').trim();
      final text = _stripTags((m.group(3) ?? '').trim());
      if (url.isEmpty) return text;
      if (text.isEmpty) return url;
      if (text == url) return url;
      return '$text（$url）';
    },
  );

  // Drop images entirely (e.g. notice header images).
  s = s.replaceAll(RegExp(r'<\s*img\b[^>]*>', caseSensitive: false), '');

  // Strip remaining tags.
  s = _stripTags(s);

  // Entities.
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&gt;', '>')
      .replaceAll('&lt;', '<')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");

  return _normalizePostText(s);
}

String _stripTags(String s) => s.replaceAll(RegExp(r'<[^>]+>'), '');

final class ReferenceDialog extends StatefulWidget {
  final int initialPostId;

  const ReferenceDialog({super.key, required this.initialPostId});

  @override
  State<ReferenceDialog> createState() => ReferenceDialogState();
}

final class ReferenceDialogState extends State<ReferenceDialog> {
  final List<int> _stack = [];
  api.Reference? _ref;
  Object? _error;
  bool _loading = true;

  int get _currentId => _stack.isEmpty ? widget.initialPostId : _stack.last;

  @override
  void initState() {
    super.initState();
    _stack.add(widget.initialPostId);
    _load(widget.initialPostId);
  }

  void push(int id) {
    _stack.add(id);
    _load(id);
  }

  Future<void> _load(int id) async {
    setState(() {
      _loading = true;
      _error = null;
      _ref = null;
    });

    try {
      final repo = context.read<AppState>().repo;
      final ref = await repo.getReference(id);
      if (!mounted) return;
      setState(() {
        _ref = ref;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _pop() async {
    if (_stack.length <= 1) return;
    _stack.removeLast();
    await _load(_stack.last);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('引用 No.$_currentId'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? Text('加载失败：$_error')
                : _ref == null
                    ? const Text('（空）')
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _formatReferenceAuthor(_ref!),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Expanded(
                                child: Center(
                                  child: Text(
                                    _formatToSeconds(_ref!.postTime),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Text('No.${_ref!.id}'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Flexible(
                            child: SingleChildScrollView(
                              child: PostContent(
                                text: _ref!.content,
                                postId: _ref!.id,
                              ),
                            ),
                          ),
                        ],
                      ),
      ),
      actions: [
        TextButton(
          onPressed: _stack.length > 1 ? _pop : null,
          child: const Text('返回上一层'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

String _formatReferenceAuthor(api.Reference ref) {
  final rawName = ref.name.trim();
  if (rawName.isNotEmpty && rawName != '无名氏') return rawName;

  final uh = ref.userHash.trim();
  if (uh.isEmpty) return '无名氏';

  const n = 8;
  final shown = uh.length <= n ? uh : uh.substring(0, n);
  return shown.toUpperCase();
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

String _normalizePostText(String input) {
  var s = input;

  // Basic HTML -> plain text
  s = s.replaceAll(RegExp(r'<\s*br\s*\/?>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<\s*\/p\s*>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<\s*p\s*>', caseSensitive: false), '');

  // Strip <font ...> but keep inner text
  s = s.replaceAll(
    RegExp(r'<\s*\/\s*font\s*>', caseSensitive: false), '');
  s = s.replaceAll(
    RegExp(r'<\s*font\b[^>]*>', caseSensitive: false), '');

  // Strip remaining tags conservatively
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');

  // Common HTML entities
  s = s
      .replaceAll('&gt;', '>')
      .replaceAll('&lt;', '<')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");

  // Normalize newlines
  s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  // Collapse consecutive blank lines into a single newline to avoid
  // excessive vertical spacing in rendered posts.
  s = s.replaceAll(RegExp(r'\n{2,}'), '\n');

  return s;
}
