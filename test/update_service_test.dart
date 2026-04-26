import 'package:flutter_test/flutter_test.dart';

import 'package:xdnmb_client/src/data/update_service.dart';

void main() {
  group('UpdateService.isNewerVersion', () {
    test('equal versions are not newer', () {
      expect(UpdateService.isNewerVersion('v1.0.0', 'v1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('1.0.0', '1.0.0'), isFalse);
    });

    test('handles missing v prefix on either side', () {
      expect(UpdateService.isNewerVersion('1.0.0', 'v1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('v1.0.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('v1.0.1', '1.0.0'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.1', 'v1.0.0'), isTrue);
    });

    test('greater patch is newer', () {
      expect(UpdateService.isNewerVersion('v1.0.1', 'v1.0.0'), isTrue);
      expect(UpdateService.isNewerVersion('v1.0.0', 'v1.0.1'), isFalse);
    });

    test('greater minor is newer', () {
      expect(UpdateService.isNewerVersion('v1.2.0', 'v1.1.99'), isTrue);
      expect(UpdateService.isNewerVersion('v1.1.99', 'v1.2.0'), isFalse);
    });

    test('greater major is newer', () {
      expect(UpdateService.isNewerVersion('v2.0.0', 'v1.99.99'), isTrue);
      expect(UpdateService.isNewerVersion('v1.99.99', 'v2.0.0'), isFalse);
    });

    test('numeric (not lexicographic) comparison', () {
      // Lexicographically "10" < "2", but numerically 10 > 2.
      expect(UpdateService.isNewerVersion('v1.10.0', 'v1.2.0'), isTrue);
      expect(UpdateService.isNewerVersion('v1.2.0', 'v1.10.0'), isFalse);
    });

    test('regression: 1.3.0 vs 1.1.0 (the bug we just fixed)', () {
      // Reproduces the original issue where 1.3.0 client thought 1.1.0
      // was the running version. Both sides are real strings now.
      expect(UpdateService.isNewerVersion('v1.3.0', 'v1.3.0'), isFalse);
      expect(UpdateService.isNewerVersion('v1.4.0', 'v1.3.0'), isTrue);
    });

    test('shorter version components default to zero', () {
      // "1.0" treated as "1.0.0".
      expect(UpdateService.isNewerVersion('v1.0', 'v1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('v1.0.0', 'v1.0'), isFalse);
      expect(UpdateService.isNewerVersion('v1.0.1', 'v1.0'), isTrue);
      expect(UpdateService.isNewerVersion('v1.1', 'v1.0.99'), isTrue);
    });

    test('extra components are compared too', () {
      // "1.0.0.1" should be newer than "1.0.0" (the 4th component is greater).
      expect(UpdateService.isNewerVersion('v1.0.0.1', 'v1.0.0'), isTrue);
      expect(UpdateService.isNewerVersion('v1.0.0', 'v1.0.0.1'), isFalse);
    });

    test('pre-release suffixes are stripped before comparing', () {
      // "1.2.0-rc.1" reduces to "1.2.0".
      expect(UpdateService.isNewerVersion('v1.2.0-rc.1', 'v1.2.0'), isFalse);
      expect(UpdateService.isNewerVersion('v1.2.0', 'v1.2.0-rc.1'), isFalse);
      expect(UpdateService.isNewerVersion('v1.2.1-beta', 'v1.2.0'), isTrue);
      expect(UpdateService.isNewerVersion('v1.2.0', 'v1.2.1-beta'), isFalse);
    });

    test('non-numeric components fall back to zero', () {
      expect(UpdateService.isNewerVersion('vabc', 'v1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('v1.0.0', 'vabc'), isTrue);
    });

    test('empty string compares as zero', () {
      expect(UpdateService.isNewerVersion('', 'v1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('v1.0.0', ''), isTrue);
      expect(UpdateService.isNewerVersion('', ''), isFalse);
    });
  });

  group('UpdateService.isReleaseAsset', () {
    bool match(String name) => UpdateService.isReleaseAsset(name);

    test('matches normal release', () {
      expect(match('WinX-1.0.0-windows-x64.zip'), isTrue);
      expect(match('WinX-1.3.0-windows-x64.zip'), isTrue);
      expect(match('WinX-12.345.6789-windows-x64.zip'), isTrue);
    });

    test('matches pre-release suffix', () {
      expect(match('WinX-1.0.0-rc.1-windows-x64.zip'), isTrue);
      expect(match('WinX-1.0.0-beta-windows-x64.zip'), isTrue);
      expect(match('WinX-1.0.0-beta.2-windows-x64.zip'), isTrue);
      expect(match('WinX-1.0.0-alpha_3-windows-x64.zip'), isTrue);
    });

    test('rejects symbol/debug variants', () {
      // Regression: these used to slip through because "-symbols" looks
      // like a pre-release tag to the version regex. The blacklist catches
      // them now.
      expect(match('WinX-symbols-1.0.0-windows-x64.zip'), isFalse);
      expect(match('WinX-debug-1.0.0-windows-x64.zip'), isFalse);
      expect(match('WinX-1.0.0-symbols-windows-x64.zip'), isFalse);
      expect(match('WinX-1.0.0-debug-windows-x64.zip'), isFalse);
      expect(match('WinX-1.0.0-pdb-windows-x64.zip'), isFalse);
      expect(match('WinX-1.0.0-Symbols-windows-x64.zip'), isFalse);
    });

    test('rejects other architectures and platforms', () {
      expect(match('WinX-1.0.0-windows-x86.zip'), isFalse);
      expect(match('WinX-1.0.0-windows-arm64.zip'), isFalse);
      expect(match('WinX-1.0.0-mac-x64.zip'), isFalse);
      expect(match('WinX-1.0.0-linux-x64.tar.gz'), isFalse);
    });

    test('case sensitive on the WinX prefix', () {
      expect(match('winx-1.0.0-windows-x64.zip'), isFalse);
      expect(match('WINX-1.0.0-windows-x64.zip'), isFalse);
    });

    test('rejects non-zip extension', () {
      expect(match('WinX-1.0.0-windows-x64.exe'), isFalse);
      expect(match('WinX-1.0.0-windows-x64.tar.gz'), isFalse);
      expect(match('WinX-1.0.0-windows-x64'), isFalse);
    });

    test('rejects 2-segment or 4-segment version', () {
      expect(match('WinX-1.0-windows-x64.zip'), isFalse);
      expect(match('WinX-1.0.0.0-windows-x64.zip'), isFalse);
    });

    test('rejects extra prefix or suffix', () {
      expect(match('extra-WinX-1.0.0-windows-x64.zip'), isFalse);
      expect(match('WinX-1.0.0-windows-x64.zip.bak'), isFalse);
      expect(match(' WinX-1.0.0-windows-x64.zip'), isFalse);
    });
  });
}
