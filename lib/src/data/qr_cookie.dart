import 'dart:convert';

import 'package:xdnmb_api/xdnmb_api.dart';

String _sanitizeUserHash(String input) {
  // IMPORTANT: userhash is arbitrary bytes. We keep it as a latin1 string.
  // Do NOT drop non-ASCII (0x80-0xFF). Only remove ASCII control chars.
  final runes = input.runes.where((c) {
    final isAsciiControl = (c >= 0x00 && c <= 0x1f) || c == 0x7f;
    return !isAsciiControl;
  });
  // IMPORTANT:
  // - Do NOT trim
  // - Do NOT collapse whitespace
  // Because those mutate bytes and can make cookie differ from the QR payload.
  return String.fromCharCodes(runes);
}

/// QR payload model.
///
/// Example:
/// {"cookie":"%CD%02tO%9BI%B5%9C%0B%E0%9E%06%8C%9A9j%0B%F4%1A%90r%EE%D1%0A","name":"NzuCRAS"}
final class QrCookiePayload {
  final String cookie;
  final String? name;

  const QrCookiePayload({required this.cookie, this.name});

  factory QrCookiePayload.fromJsonString(String raw) {
    final decoded = json.decode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('二维码内容不是 JSON 对象');
    }
    final cookie = decoded['cookie'];
    if (cookie is! String || cookie.isEmpty) {
      throw const FormatException('二维码缺少 cookie 字段');
    }
    final name = decoded['name'];
    return QrCookiePayload(cookie: cookie, name: name is String ? name : null);
  }

  /// Decode percent-encoded bytes to a userHash string.
  ///
  /// The forum issues QR cookies as percent-encoded raw bytes. We keep the
  /// original bytes but represent as a Dart string using ISO-8859-1 to preserve
  /// all byte values 0-255 without loss.
  String decodeUserHash() {
    final bytes = <int>[];
    final s = cookie;
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x25 /* % */) {
        if (i + 2 >= s.length) {
          // trailing '%': keep literal
          bytes.add(c);
          continue;
        }
        final hi = _hexValue(s.codeUnitAt(i + 1));
        final lo = _hexValue(s.codeUnitAt(i + 2));
        if (hi >= 0 && lo >= 0) {
          bytes.add((hi << 4) | lo);
          i += 2;
          continue;
        }
        // not a valid %xx: keep literal
        bytes.add(c);
        continue;
      }
      bytes.add(c);
    }
    return latin1.decode(bytes, allowInvalid: true);
  }

  /// Return the percent-encoded userhash text as-is.
  ///
  /// This matches the QR payload/cURL usage: `Cookie: userhash=%CD%02...`.
  /// Storing this form avoids Windows header/control-char pitfalls.
  String percentUserHash() => cookie;

  static int _hexValue(int c) {
    if (c >= 0x30 && c <= 0x39) return c - 0x30;
    if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
    if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
    return -1;
  }

  XdnmbCookie toXdnmbCookie() =>
      XdnmbCookie(_sanitizeUserHash(percentUserHash()), name: name);
}
