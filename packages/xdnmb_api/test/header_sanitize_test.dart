import 'package:test/test.dart';
import 'package:xdnmb_api/src/client.dart';

void main() {
  group('sanitizeHeaderValue', () {
    test('removes CRLF and other ASCII control characters', () {
      final raw = 'userhash=abc\r\n123\u0000\u0007\tZ';
      final sanitized = sanitizeHeaderValue(raw);

      expect(sanitized.contains('\r'), isFalse);
      expect(sanitized.contains('\n'), isFalse);
      expect(sanitized.contains('\u0000'), isFalse);
      expect(sanitized.contains('\u0007'), isFalse);
  // NOTE: We no longer normalize whitespace to avoid mutating userhash bytes.
  // CR/LF are removed, so there is no guaranteed separator between
  // adjacent tokens split only by CR/LF.
  expect(sanitized, equals('userhash=abc123Z'));
    });

    test('trims and collapses whitespace', () {
  expect(sanitizeHeaderValue('  a   b  '), equals('  a   b  '));
    });
  });
}
