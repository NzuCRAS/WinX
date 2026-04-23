import 'dart:io';

import 'font_config.dart';

/// Scans the Windows registry for installed system fonts.
///
/// On Windows, font information is stored under:
///   HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts
///
/// Registry values look like:
///   "Microsoft YaHei (TrueType)"="msyh.ttc"
///   "Microsoft YaHei Bold (TrueType)"="msyhbd.ttc"
///
/// We parse the display name to extract the family name and variant.
final class SystemFontScanner {
  List<FontFamily>? _cached;

  /// Scan the Windows registry for installed fonts.
  ///
  /// Results are cached in memory; subsequent calls return the cached list
  /// unless [forceRefresh] is true.
  Future<List<FontFamily>> scan({bool forceRefresh = false}) async {
    if (!forceRefresh && _cached != null) return _cached!;

    if (!Platform.isWindows) {
      _cached = const [];
      return _cached!;
    }

    final result = await Process.run(
      'reg',
      [
        'query',
        r'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
        '/s',
      ],
      runInShell: false,
    );

    if (result.exitCode != 0) {
      _cached = const [];
      return _cached!;
    }

    final lines = (result.stdout as String).split('\n');
    final rawEntries = <_RawFontEntry>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // Registry lines with font data look like:
      //   "Font Name (TrueType)"    REG_SZ    "filename.ttf"
      final entry = _parseRegLine(trimmed);
      if (entry != null) rawEntries.add(entry);
    }

    _cached = _groupByFamily(rawEntries);
    return _cached!;
  }

  /// Clear the in-memory cache.
  void clearCache() => _cached = null;
}

/// A raw font entry parsed from a registry line.
final class _RawFontEntry {
  final String displayName;
  final String fileName;

  _RawFontEntry({required this.displayName, required this.fileName});
}

_RawFontEntry? _parseRegLine(String line) {
  // Lines from `reg query /s` in the Fonts key look like:
  //    "Font Name (TrueType)"    REG_SZ    filename.ttf
  // We look for REG_SZ as a marker and split around it.
  final regSzIndex = line.indexOf('REG_SZ');
  if (regSzIndex < 0) return null;

  final leftPart = line.substring(0, regSzIndex).trim();
  final rightPart = line.substring(regSzIndex + 6).trim();

  if (leftPart.isEmpty || rightPart.isEmpty) return null;

  // Remove surrounding quotes from the display name if present.
  var displayName = leftPart;
  if (displayName.startsWith('"') && displayName.endsWith('"')) {
    displayName = displayName.substring(1, displayName.length - 1);
  }

  // Remove the " (TrueType)" or " (OpenType)" suffix.
  displayName = displayName
      .replaceAll(RegExp(r'\s*\(TrueType\)\s*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*\(OpenType\)\s*$', caseSensitive: false), '');

  if (displayName.isEmpty) return null;

  // Remove surrounding quotes from filename if present.
  var fileName = rightPart;
  if (fileName.startsWith('"') && fileName.endsWith('"')) {
    fileName = fileName.substring(1, fileName.length - 1);
  }

  return _RawFontEntry(displayName: displayName, fileName: fileName);
}

/// Group raw registry entries by font family name.
///
/// Variant detection heuristics:
/// - "Family Name Bold" → family="Family Name", variant="Bold"
/// - "Family Name Italic" → family="Family Name", variant="Italic"
/// - "Family Name Bold Italic" → family="Family Name", variant="Bold Italic"
/// - "Family Name" → family="Family Name", variant="Regular"
List<FontFamily> _groupByFamily(List<_RawFontEntry> entries) {
  final map = <String, Set<String>>{};

  for (final e in entries) {
    final (family, variant) = _splitFamilyVariant(e.displayName);
    map.putIfAbsent(family, () => <String>{}).add(variant);
  }

  final families = map.entries.toList()
    ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

  return [
    for (final e in families)
      FontFamily(
        familyName: e.key,
        variants: e.value.toList()..sort(),
      ),
  ];
}

/// Split a registry display name into (familyName, variant).
///
/// Known variant keywords: Bold, Italic, Light, Medium, Semibold,
/// Black, Thin, Heavy, Extra, Condensed, Extended, Oblique.
(String, String) _splitFamilyVariant(String displayName) {
  final variantKeywords = [
    'Bold Italic',
    'Italic Bold',
    'Bold Oblique',
    'Oblique Bold',
    'Bold',
    'Italic',
    'Oblique',
    'Light',
    'Medium',
    'Semibold',
    'SemiBold',
    'Black',
    'Thin',
    'Heavy',
    'Extra',
    'Condensed',
    'Extended',
  ];

  final lower = displayName.toLowerCase();
  for (final kw in variantKeywords) {
    final kwLower = kw.toLowerCase();
    if (lower.endsWith(' $kwLower')) {
      final family = displayName.substring(0, displayName.length - kw.length - 1).trim();
      return (family.isEmpty ? displayName : family, kw);
    }
  }

  return (displayName, 'Regular');
}
