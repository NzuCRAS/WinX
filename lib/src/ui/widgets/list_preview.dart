/// Utilities for rendering list previews consistently across pages.
///
/// Keep this in a shared place so Subscription/History/PostHistory can use the
/// exact same normalization logic.
library;

String normalizeForListPreview(String input) {
  var s = input;
  s = s.replaceAll(RegExp(r'<\s*br\s*\/?>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<\s*\/p\s*>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<\s*p\s*>', caseSensitive: false), '');
  s = s.replaceAll(
    RegExp(r'<\s*\/\s*font\s*>', caseSensitive: false), '');
  s = s.replaceAll(
    RegExp(r'<\s*font\b[^>]*>', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  s = s
    .replaceAll('&gt;', '>')
    .replaceAll('&lt;', '<')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'");
  s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  s = s.replaceAll(RegExp(r'\n{2,}'), '\n');

  // Spoiler: in list previews, keep a placeholder but never show the content.
  // We replace the entire block with a fixed token that can be rendered as a black bar.
  s = s.replaceAll(
    RegExp(r'\[h\][\s\S]*?\[\/h\]', caseSensitive: false),
    '[spoiler]',
  );

  return s.trim();
}
