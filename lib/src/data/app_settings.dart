import 'dart:convert';

import 'package:flutter/material.dart';

import 'font_config.dart';

/// Immutable aggregate of all user settings.
///
/// Stored as JSON on disk and loaded on startup. Version field allows
/// forward-compatible migrations.
final class AppSettings {
  static const int currentVersion = 2;

  final int version;

  // ── Appearance ──
  final ThemeMode themeMode;

  // ── Content text (API data) ──
  final FontConfig contentFont;

  // ── UI text (labels, buttons, meta rows) ──
  final FontConfig uiFont;

  // ── Browse behaviour ──
  final bool autoLoadOnScroll;
  final bool showImageInThread;
  final bool showLineBreakIndicator;
  final double threadPreloadDistance;
  final int previewMaxLines;

  // ── Cache / debug ──
  final bool enableDebugLog;
  final int threadCacheTtlMinutes;

  // ── Storage paths ──
  final String? databaseDirectory;
  final String? downloadDirectory;

  // ── Shortcuts ──
  /// Map of shortcut action id → key combination label.
  /// e.g. {"back": "Escape", "send": "Control+Enter"}
  final Map<String, String> shortcuts;

  // ── Update ──
  final bool autoCheckUpdate;
  final DateTime? lastUpdateCheckAt;

  const AppSettings({
    this.version = currentVersion,
    this.themeMode = ThemeMode.system,
    this.contentFont = const FontConfig(),
    this.uiFont = const FontConfig(),
    this.autoLoadOnScroll = true,
    this.showImageInThread = true,
    this.showLineBreakIndicator = true,
    this.threadPreloadDistance = 240.0,
    this.previewMaxLines = 10,
    this.enableDebugLog = false,
    this.threadCacheTtlMinutes = 5,
    this.databaseDirectory,
    this.downloadDirectory,
    this.shortcuts = const {'back': 'Escape'},
    this.autoCheckUpdate = true,
    this.lastUpdateCheckAt,
  });

  AppSettings copyWith({
    int? version,
    ThemeMode? themeMode,
    FontConfig? contentFont,
    FontConfig? uiFont,
    bool? autoLoadOnScroll,
    bool? showImageInThread,
    bool? showLineBreakIndicator,
    double? threadPreloadDistance,
    int? previewMaxLines,
    bool? enableDebugLog,
    int? threadCacheTtlMinutes,
    String? databaseDirectory,
    String? downloadDirectory,
    Map<String, String>? shortcuts,
    bool? autoCheckUpdate,
    DateTime? lastUpdateCheckAt,
  }) =>
      AppSettings(
        version: version ?? this.version,
        themeMode: themeMode ?? this.themeMode,
        contentFont: contentFont ?? this.contentFont,
        uiFont: uiFont ?? this.uiFont,
        autoLoadOnScroll: autoLoadOnScroll ?? this.autoLoadOnScroll,
        showImageInThread: showImageInThread ?? this.showImageInThread,
        showLineBreakIndicator: showLineBreakIndicator ?? this.showLineBreakIndicator,
        threadPreloadDistance: threadPreloadDistance ?? this.threadPreloadDistance,
        previewMaxLines: previewMaxLines ?? this.previewMaxLines,
        enableDebugLog: enableDebugLog ?? this.enableDebugLog,
        threadCacheTtlMinutes: threadCacheTtlMinutes ?? this.threadCacheTtlMinutes,
        databaseDirectory: databaseDirectory ?? this.databaseDirectory,
        downloadDirectory: downloadDirectory ?? this.downloadDirectory,
        shortcuts: shortcuts ?? this.shortcuts,
        autoCheckUpdate: autoCheckUpdate ?? this.autoCheckUpdate,
        lastUpdateCheckAt: lastUpdateCheckAt ?? this.lastUpdateCheckAt,
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'themeMode': switch (themeMode) {
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
          _ => 'system',
        },
        'contentFont': contentFont.toJson(),
        'uiFont': uiFont.toJson(),
        'autoLoadOnScroll': autoLoadOnScroll,
        'showImageInThread': showImageInThread,
        'showLineBreakIndicator': showLineBreakIndicator,
        'threadPreloadDistance': threadPreloadDistance,
        'previewMaxLines': previewMaxLines,
        'enableDebugLog': enableDebugLog,
        'threadCacheTtlMinutes': threadCacheTtlMinutes,
        'databaseDirectory': databaseDirectory,
        'downloadDirectory': downloadDirectory,
        'shortcuts': shortcuts,
        'autoCheckUpdate': autoCheckUpdate,
        'lastUpdateCheckAt': lastUpdateCheckAt?.millisecondsSinceEpoch,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    FontConfig parseFont(dynamic v) {
      if (v is Map<String, dynamic>) return FontConfig.fromJson(v);
      return FontConfig();
    }

    return AppSettings(
      version: (json['version'] as num?)?.toInt() ?? currentVersion,
      themeMode: switch (json['themeMode']) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      contentFont: parseFont(json['contentFont']),
      uiFont: parseFont(json['uiFont']),
      autoLoadOnScroll: json['autoLoadOnScroll'] as bool? ?? true,
      showImageInThread: json['showImageInThread'] as bool? ?? true,
      showLineBreakIndicator: json['showLineBreakIndicator'] as bool? ?? true,
      threadPreloadDistance:
          (json['threadPreloadDistance'] as num?)?.toDouble() ?? 240.0,
      previewMaxLines: (json['previewMaxLines'] as num?)?.toInt() ?? 10,
      enableDebugLog: json['enableDebugLog'] as bool? ?? false,
      threadCacheTtlMinutes:
          (json['threadCacheTtlMinutes'] as num?)?.toInt() ?? 5,
      databaseDirectory: json['databaseDirectory'] as String?,
      downloadDirectory: json['downloadDirectory'] as String?,
      shortcuts: (json['shortcuts'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v.toString())) ??
          const {'back': 'Escape'},
      autoCheckUpdate: json['autoCheckUpdate'] as bool? ?? true,
      lastUpdateCheckAt: json['lastUpdateCheckAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (json['lastUpdateCheckAt'] as num).toInt()),
    );
  }

  String toJsonString() =>
      const JsonEncoder.withIndent('  ').convert(toJson());

  factory AppSettings.fromJsonString(String s) {
    try {
      final decoded = jsonDecode(s) as Map<String, dynamic>;
      return AppSettings.fromJson(decoded);
    } catch (_) {
      return const AppSettings();
    }
  }
}
