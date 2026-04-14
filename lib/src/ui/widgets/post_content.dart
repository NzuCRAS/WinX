import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xdnmb_api/xdnmb_api.dart' as api;

import '../../app/app_state.dart';

/// Semi-rich text renderer:
/// - clickable `>>123456` references (preview via API)
/// - clickable URLs
final class PostContent extends StatelessWidget {
  final String text;
  final int postId;

  const PostContent({super.key, required this.text, required this.postId});

  static final _ref = RegExp(r'>>\s*(?:No\.)?\s*(\d{1,10})');
  static final _url = RegExp(r'(https?://[^\s]+)');
  static final _spoiler = RegExp(r'\[h\]([\s\S]*?)\[\/h\]', caseSensitive: false);

  static final _refDialogKey = GlobalKey<_ReferenceDialogState>();
  static bool _refDialogOpen = false;

  @override
  Widget build(BuildContext context) {
  final spans = <InlineSpan>[];
  final s = _normalizePostText(text);

  spans.addAll(_buildInlineSpans(context, s));

    final app = context.watch<AppState>();
    return SelectableText.rich(
      TextSpan(
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: app.contentFontSize,
              height: app.contentLineHeight,
              fontFamily: app.fontFamily.isEmpty ? null : app.fontFamily,
            ),
        children: spans,
      ),
    );
  }

  static List<InlineSpan> _buildInlineSpans(BuildContext context, String s) {
    // Step 1: parse spoiler blocks. Outer-most non-overlapping matches only.
    final parts = <InlineSpan>[];
    var cursor = 0;
    for (final match in _spoiler.allMatches(s)) {
      if (match.start > cursor) {
        parts.addAll(
            _buildInlineSpansNoSpoiler(context, s.substring(cursor, match.start)));
      }

      final inner = match.group(1) ?? '';
      parts.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _SpoilerBlock(text: inner, interactive: true),
        ),
      );
      cursor = match.end;
    }

    if (cursor < s.length) {
      parts.addAll(_buildInlineSpansNoSpoiler(context, s.substring(cursor)));
    }
    return parts;
  }

  static List<InlineSpan> _buildInlineSpansNoSpoiler(
      BuildContext context, String s) {
    // Split into lines so we can apply greentext style for lines starting with `>`.
    final spans = <InlineSpan>[];

    // Keep line breaks as individual spans so SelectableText preserves them.
    final lines = s.split('\n');
    for (int li = 0; li < lines.length; li++) {
      final line = lines[li];
  final green = _greentextColor(Theme.of(context));
      spans.addAll(_buildInlineSpansLeaf(context, line,
          baseStyle: line.startsWith('>')
      ? TextStyle(color: green)
              : null));
      if (li != lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }

    return spans;
  }

  static List<InlineSpan> _buildInlineSpansLeaf(
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
          recognizer: TapGestureRecognizer()
            ..onTap = id == null
                ? null
                : () async {
                    final st = _refDialogKey.currentState;
                    if (_refDialogOpen && st != null) {
                      st.push(id);
                      return;
                    }

                    _refDialogOpen = true;
                    try {
                      await showDialog(
                        context: context,
                        builder: (context) => _ReferenceDialog(
                          key: _refDialogKey,
                          initialPostId: id,
                        ),
                      );
                    } finally {
                      _refDialogOpen = false;
                    }
                  },
        ));
        i = refMatch.end;
        continue;
      }

      if (urlMatch != null) {
        final raw = urlMatch.group(1)!;
        spans.add(TextSpan(
          text: raw,
          style: (baseStyle ?? const TextStyle()).copyWith(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              final uri = Uri.tryParse(raw);
              if (uri != null) {
                launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
        ));
        i = urlMatch.end;
        continue;
      }

      final next = [
        _ref.firstMatch(s.substring(i)),
        _url.firstMatch(s.substring(i)),
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
    // Keep it readable on both themes.
    return b == Brightness.dark ? Colors.lightGreenAccent.shade200 : Colors.green.shade700;
  }
}

final class _SpoilerBlock extends StatefulWidget {
  final String text;
  final bool interactive;

  const _SpoilerBlock({required this.text, this.interactive = true});

  @override
  State<_SpoilerBlock> createState() => _SpoilerBlockState();
}

final class _SpoilerBlockState extends State<_SpoilerBlock> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
  final content = widget.text;

    final canToggle = widget.interactive;

    final bar = Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: _revealed ? cs.surfaceContainerHighest : Colors.black,
          borderRadius: BorderRadius.circular(4),
        ),
        child: _revealed
            ? SelectableText.rich(
                TextSpan(
                  style: TextStyle(color: cs.onSurface),
                  children: PostContent._buildInlineSpans(
                      context, _normalizePostText(content)),
                ),
              )
            // Covered state: show a pure black bar, no text.
            : const SizedBox(width: 72, height: 18),
      );

    if (!canToggle) return bar;
    return InkWell(
      onTap: () => setState(() => _revealed = !_revealed),
      child: bar,
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
  // Example: 任天堂<font color="DeepSkyBlue">N</font> -> 任天堂N
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
  r'''<\s*a\b[^>]*href\s*=\s*(["\'])(.*?)\1[^>]*>(.*?)<\s*\/a\s*>''',
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

final class _ReferenceDialog extends StatefulWidget {
  final int initialPostId;

  const _ReferenceDialog({super.key, required this.initialPostId});

  @override
  State<_ReferenceDialog> createState() => _ReferenceDialogState();
}

final class _ReferenceDialogState extends State<_ReferenceDialog> {
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

  // API 侧的 Reference 模型默认值就是“无名氏”，所以仅仅判断空串不够。
  // 当 name 为空或等于默认匿名名时，退化为显示 userHash（饼干标识）的一部分。
  if (rawName.isNotEmpty && rawName != '无名氏') return rawName;

  final uh = ref.userHash.trim();
  if (uh.isEmpty) return '无名氏';

  // 显示 userHash 的前 N 位作为“饼干标识”（不加任何前缀），避免你说的“第一位消失”。
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

  // Collapse excessive blank lines (common when HTML already contains `\n`
  // plus `<br>`/`</p>` conversions). For in-post content, two consecutive newlines
  // are usually unintended and look like an extra blank line.
  s = s.replaceAll(RegExp(r'\n{2,}'), '\n');
  return s;
}
