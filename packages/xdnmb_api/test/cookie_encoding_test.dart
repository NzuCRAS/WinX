import 'dart:convert';

import 'package:test/test.dart';
import 'package:xdnmb_api/src/client.dart' as c;

void main() {
  group('encodeCookieValue / debugging heuristics', () {
    test('percent-encoded text should not be stored as userHash (shape detector)', () {
    // Use enough %xx blocks so the heuristic can confidently treat it as
    // already-percent-encoded userhash text.
    const percentText =
      '%CD%02%74%4F%9B%49%B5%9C%0B%E0%9E%06%8C%9A%39%6A%0B%F4%1A%90%72%EE%D1%0A';
      final shape = c.testOnlyPercentShape(percentText);
      expect(shape.seemsPercentEncoded, isTrue);
    expect(shape.percentTriples, greaterThanOrEqualTo(8));
    });

    test('latin1 raw bytes encode to identical %XX stream', () {
      // bytes: CD 02 74 4F
      final raw = latin1.decode([0xCD, 0x02, 0x74, 0x4F], allowInvalid: true);
      expect(c.encodeCookieValue(raw), '%CD%02%74%4F');
    });

    test('utf8 double-encoding symptom: Ã\u008d for 0xCD', () {
      // If someone mistakenly stored "%CD" as UTF-8 decoded bytes:
      // 0xCD -> 'Í' (latin1) -> UTF-8 bytes C3 8D -> %C3%8D
  final wrong = latin1.decode([0xC3, 0x8D], allowInvalid: true);
  expect(c.encodeCookieValue(wrong), '%C3%8D');
    });
  });
}
