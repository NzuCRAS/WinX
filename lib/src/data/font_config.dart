import 'dart:convert';

import 'package:flutter/material.dart';

/// Represents a single font family with its variants (Regular, Bold, etc.)
/// extracted from the Windows registry.
final class FontFamily {
  final String familyName;
  final List<String> variants;

  const FontFamily({required this.familyName, required this.variants});

  @override
  String toString() => familyName;
}

/// Per-block font configuration (e.g. UI text vs API content).
///
/// Each block has its own:
/// - [availableFonts]: pool of saved font family names (system + user-uploaded)
/// - [fallbackOrder]: priority order drawn from [availableFonts]
/// - [fontSize], [fontWeight], [lineHeight]: text metrics
final class FontConfig {
  /// Saved font family names that can be used for this block.
  final List<String> availableFonts;
  /// Priority fallback order (subset of [availableFonts]).
  final List<String> fallbackOrder;
  /// Font size in logical pixels.
  final double fontSize;
  /// Font weight label. Supported values:
  ///   'normal', 'bold', 'w100'..'w900'.
  final String fontWeight;
  /// Line height multiplier.
  final double lineHeight;
  /// Paths to user-uploaded font files for this block.
  final List<String> userFontPaths;

  const FontConfig({
    this.availableFonts = const [],
    this.fallbackOrder = const [],
    this.fontSize = 14.0,
    this.fontWeight = 'normal',
    this.lineHeight = 1.5,
    this.userFontPaths = const [],
  });

  static const List<String> _defaultFontFallback = [
    'Cantarell',
    'LXGWWenKai',
    'Segoe UI',
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'Noto Sans CJK SC',
    'Noto Sans',
  ];

  static const Map<String, FontWeight> _weightMap = {
    'normal': FontWeight.normal,
    'bold': FontWeight.bold,
    'w100': FontWeight.w100,
    'w200': FontWeight.w200,
    'w300': FontWeight.w300,
    'w400': FontWeight.w400,
    'w500': FontWeight.w500,
    'w600': FontWeight.w600,
    'w700': FontWeight.w700,
    'w800': FontWeight.w800,
    'w900': FontWeight.w900,
  };

  FontWeight? get resolvedWeight => _weightMap[fontWeight];

  /// Produce the final `fontFamilyFallback` list for Flutter.
  ///
  /// User-selected fonts (from [fallbackOrder]) are placed first, followed by
  /// the default system fallback chain. Duplicates are removed.
  List<String> resolve() {
    final result = <String>[];
    for (final f in fallbackOrder) {
      final t = f.trim();
      if (t.isNotEmpty && !result.contains(t)) result.add(t);
    }
    for (final f in _defaultFontFallback) {
      if (!result.contains(f)) result.add(f);
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
        'availableFonts': availableFonts,
        'fallbackOrder': fallbackOrder,
        'fontSize': fontSize,
        'fontWeight': fontWeight,
        'lineHeight': lineHeight,
        'userFontPaths': userFontPaths,
      };

  factory FontConfig.fromJson(Map<String, dynamic> json) => FontConfig(
        availableFonts:
            (json['availableFonts'] as List<dynamic>?)?.cast<String>() ?? const [],
        fallbackOrder:
            (json['fallbackOrder'] as List<dynamic>?)?.cast<String>() ?? const [],
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
        fontWeight: json['fontWeight'] as String? ?? 'normal',
        lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.5,
        userFontPaths:
            (json['userFontPaths'] as List<dynamic>?)?.cast<String>() ?? const [],
      );

  String toJsonString() => jsonEncode(toJson());

  FontConfig copyWith({
    List<String>? availableFonts,
    List<String>? fallbackOrder,
    double? fontSize,
    String? fontWeight,
    double? lineHeight,
    List<String>? userFontPaths,
  }) =>
      FontConfig(
        availableFonts: availableFonts ?? this.availableFonts,
        fallbackOrder: fallbackOrder ?? this.fallbackOrder,
        fontSize: fontSize ?? this.fontSize,
        fontWeight: fontWeight ?? this.fontWeight,
        lineHeight: lineHeight ?? this.lineHeight,
        userFontPaths: userFontPaths ?? this.userFontPaths,
      );

  factory FontConfig.fromJsonString(String s) {
    try {
      final decoded = jsonDecode(s) as Map<String, dynamic>;
      return FontConfig.fromJson(decoded);
    } catch (_) {
      return FontConfig();
    }
  }
}
