import 'package:flutter/material.dart';

import '../data/local_prefs.dart';

/// Manages all user settings (font, theme, behavior).
///
/// Separated from AppState so UI pages can watch only settings changes
/// without rebuilding on cookie changes.
final class SettingsController extends ChangeNotifier {
  final LocalPrefs _prefs;

  double contentFontSize = LocalPrefs.defaultContentFontSize;
  double contentLineHeight = LocalPrefs.defaultContentLineHeight;
  ThemeMode themeMode = ThemeMode.system;
  int previewMaxLines = LocalPrefs.defaultPreviewMaxLines;
  String fontFamily = LocalPrefs.defaultFontFamily;
  bool autoLoadOnScroll = LocalPrefs.defaultAutoLoadOnScroll;
  bool showImageInThread = LocalPrefs.defaultShowImageInThread;
  double threadPreloadDistance = LocalPrefs.defaultThreadPreloadDistance;
  bool enableDebugLog = LocalPrefs.defaultEnableDebugLog;
  int threadCacheTtlMinutes = LocalPrefs.defaultThreadCacheTtlMinutes;
  String? databaseDirectory;
  String? downloadDirectory;
  bool autoCheckUpdate = true;
  DateTime? lastUpdateCheckAt;

  /// Called whenever [enableDebugLog] changes. AppState wires this to repo.
  void Function(bool)? onDebugLogChanged;

  /// Called whenever [threadCacheTtlMinutes] changes. AppState wires this to repo.
  void Function(int)? onThreadCacheTtlChanged;

  SettingsController({required LocalPrefs prefs}) : _prefs = prefs;

  Future<void> init() async {
    contentFontSize = await _prefs.getContentFontSize();
    contentLineHeight = await _prefs.getContentLineHeight();
    previewMaxLines = await _prefs.getPreviewMaxLines();
    fontFamily = await _prefs.getFontFamily();
    autoLoadOnScroll = await _prefs.getAutoLoadOnScroll();
    showImageInThread = await _prefs.getShowImageInThread();
    threadPreloadDistance = await _prefs.getThreadPreloadDistance();
    enableDebugLog = await _prefs.getEnableDebugLog();
    threadCacheTtlMinutes = await _prefs.getThreadCacheTtlMinutes();
    databaseDirectory = await _prefs.getDatabaseDirectory();
    downloadDirectory = await _prefs.getDownloadDirectory();
    autoCheckUpdate = await _prefs.getAutoCheckUpdate();
    lastUpdateCheckAt = await _prefs.getLastUpdateCheckAt();
    final tm = await _prefs.getThemeMode();
    themeMode = switch (tm) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setContentFontSize(double value) async {
    contentFontSize = value;
    await _prefs.setContentFontSize(value);
    notifyListeners();
  }

  Future<void> setContentLineHeight(double value) async {
    contentLineHeight = value;
    await _prefs.setContentLineHeight(value);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    final s = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    };
    await _prefs.setThemeMode(s);
    notifyListeners();
  }

  Future<void> setPreviewMaxLines(int value) async {
    previewMaxLines = value;
    await _prefs.setPreviewMaxLines(value);
    notifyListeners();
  }

  Future<void> setFontFamily(String value) async {
    fontFamily = value;
    await _prefs.setFontFamily(value);
    notifyListeners();
  }

  Future<void> setAutoLoadOnScroll(bool value) async {
    autoLoadOnScroll = value;
    await _prefs.setAutoLoadOnScroll(value);
    notifyListeners();
  }

  Future<void> setShowImageInThread(bool value) async {
    showImageInThread = value;
    await _prefs.setShowImageInThread(value);
    notifyListeners();
  }

  Future<void> setThreadPreloadDistance(double value) async {
    threadPreloadDistance = value;
    await _prefs.setThreadPreloadDistance(value);
    notifyListeners();
  }

  Future<void> setEnableDebugLog(bool value) async {
    enableDebugLog = value;
    onDebugLogChanged?.call(value);
    await _prefs.setEnableDebugLog(value);
    notifyListeners();
  }

  Future<void> setThreadCacheTtlMinutes(int value) async {
    threadCacheTtlMinutes = value;
    onThreadCacheTtlChanged?.call(value);
    await _prefs.setThreadCacheTtlMinutes(value);
    notifyListeners();
  }

  Future<void> setDatabaseDirectory(String? value) async {
    databaseDirectory = value;
    await _prefs.setDatabaseDirectory(value);
    notifyListeners();
  }

  Future<void> setDownloadDirectory(String? value) async {
    downloadDirectory = value;
    await _prefs.setDownloadDirectory(value);
    notifyListeners();
  }

  Future<void> setAutoCheckUpdate(bool value) async {
    autoCheckUpdate = value;
    await _prefs.setAutoCheckUpdate(value);
    notifyListeners();
  }

  Future<void> setLastUpdateCheckAt(DateTime value) async {
    lastUpdateCheckAt = value;
    await _prefs.setLastUpdateCheckAt(value);
    notifyListeners();
  }

  Future<void> reset() async {
    await setContentFontSize(LocalPrefs.defaultContentFontSize);
    await setContentLineHeight(LocalPrefs.defaultContentLineHeight);
    await setThemeMode(ThemeMode.system);
    await setPreviewMaxLines(LocalPrefs.defaultPreviewMaxLines);
    await setFontFamily(LocalPrefs.defaultFontFamily);
    await setAutoLoadOnScroll(LocalPrefs.defaultAutoLoadOnScroll);
    await setShowImageInThread(LocalPrefs.defaultShowImageInThread);
    await setThreadPreloadDistance(LocalPrefs.defaultThreadPreloadDistance);
    await setEnableDebugLog(LocalPrefs.defaultEnableDebugLog);
    await setThreadCacheTtlMinutes(LocalPrefs.defaultThreadCacheTtlMinutes);
    await setDatabaseDirectory(null);
    await setDownloadDirectory(null);
  }
}
