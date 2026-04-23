import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/app_settings.dart';
import '../data/font_config.dart';
import '../data/local_prefs.dart';
import '../data/settings_file_store.dart';

/// Manages all user settings via a single JSON file on disk.
///
/// On first launch (or when the JSON file is missing) settings are
/// transparently migrated from the legacy SharedPreferences store.
final class SettingsController extends ChangeNotifier {
  final LocalPrefs _prefs;
  final SettingsFileStore _fileStore;

  AppSettings _settings = const AppSettings();

  AppSettings get settings => _settings;

  // Convenience getters for widgets that only need a subset.
  ThemeMode get themeMode => _settings.themeMode;
  FontConfig get contentFont => _settings.contentFont;
  FontConfig get uiFont => _settings.uiFont;
  /// Primary font family for content text (first in fallbackOrder, or null).
  String? get contentFontFamily => _settings.contentFont.fallbackOrder.firstOrNull;
  List<String> get contentFontFallback => _settings.contentFont.resolve();
  FontWeight? get contentFontWeight => _settings.contentFont.resolvedWeight;
  /// Primary font family for UI text (first in fallbackOrder, or null).
  String? get uiFontFamily => _settings.uiFont.fallbackOrder.firstOrNull;
  List<String> get uiFontFallback => _settings.uiFont.resolve();
  FontWeight? get uiFontWeight => _settings.uiFont.resolvedWeight;
  bool get autoLoadOnScroll => _settings.autoLoadOnScroll;
  bool get showImageInThread => _settings.showImageInThread;
  bool get showLineBreakIndicator => _settings.showLineBreakIndicator;
  double get threadPreloadDistance => _settings.threadPreloadDistance;
  int get previewMaxLines => _settings.previewMaxLines;
  bool get enableDebugLog => _settings.enableDebugLog;
  int get threadCacheTtlMinutes => _settings.threadCacheTtlMinutes;
  String? get databaseDirectory => _settings.databaseDirectory;
  String? get downloadDirectory => _settings.downloadDirectory;
  Map<String, String> get shortcuts => _settings.shortcuts;
  bool get autoCheckUpdate => _settings.autoCheckUpdate;
  DateTime? get lastUpdateCheckAt => _settings.lastUpdateCheckAt;

  // Legacy aliases so existing widgets don't break immediately.
  double get contentFontSize => _settings.contentFont.fontSize;
  double get contentLineHeight => _settings.contentFont.lineHeight;
  List<String> get fontFamilyFallback => _settings.contentFont.resolve();

  /// Called whenever [enableDebugLog] changes. AppState wires this to repo.
  void Function(bool)? onDebugLogChanged;

  /// Called whenever [threadCacheTtlMinutes] changes. AppState wires this to repo.
  void Function(int)? onThreadCacheTtlChanged;

  SettingsController({required LocalPrefs prefs})
      : _prefs = prefs,
        _fileStore = SettingsFileStore();

  Future<void> init() async {
    // 1. Try the new JSON file first.
    final fromFile = await _fileStore.read();
    if (fromFile != null) {
      _settings = fromFile;
      // Migrate font paths from old location if needed.
      await _migrateFontPathsIfNeeded();
      notifyListeners();
      return;
    }

    // 2. Migrate from legacy SharedPreferences.
    final legacy = await _migrateFromLegacy();
    _settings = legacy;
    await _fileStore.write(_settings);
    notifyListeners();
  }

  Future<AppSettings> _migrateFromLegacy() async {
    final themeMode = switch (await _prefs.getThemeMode()) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    // Font config may already exist as v2 JSON in prefs.
    final fontConfigJson = await _prefs.getFontConfigJson();
    FontConfig contentFont;
    FontConfig uiFont;
    if (fontConfigJson.isNotEmpty) {
      final fc = FontConfig.fromJsonString(fontConfigJson);
      contentFont = fc;
      uiFont = FontConfig(
        availableFonts: List.unmodifiable(fc.availableFonts),
        fallbackOrder: List.unmodifiable(fc.fallbackOrder),
        userFontPaths: List.unmodifiable(fc.userFontPaths),
      );
    } else {
      final oldFamily = await _prefs.getFontFamily();
      final order = oldFamily.isNotEmpty ? [oldFamily] : <String>[];
      contentFont = FontConfig(
        fallbackOrder: order,
        fontSize: await _prefs.getContentFontSize(),
        lineHeight: await _prefs.getContentLineHeight(),
      );
      uiFont = FontConfig(
        fallbackOrder: List.unmodifiable(order),
        fontSize: await _prefs.getContentFontSize(),
        lineHeight: await _prefs.getContentLineHeight(),
      );
    }

    return AppSettings(
      themeMode: themeMode,
      contentFont: contentFont,
      uiFont: uiFont,
      autoLoadOnScroll: await _prefs.getAutoLoadOnScroll(),
      showImageInThread: await _prefs.getShowImageInThread(),
      showLineBreakIndicator: await _prefs.getShowLineBreakIndicator(),
      threadPreloadDistance: await _prefs.getThreadPreloadDistance(),
      previewMaxLines: await _prefs.getPreviewMaxLines(),
      enableDebugLog: await _prefs.getEnableDebugLog(),
      threadCacheTtlMinutes: await _prefs.getThreadCacheTtlMinutes(),
      databaseDirectory: await _prefs.getDatabaseDirectory(),
      downloadDirectory: await _prefs.getDownloadDirectory(),
      autoCheckUpdate: await _prefs.getAutoCheckUpdate(),
      lastUpdateCheckAt: await _prefs.getLastUpdateCheckAt(),
    );
  }

  /// Migrate font file paths from old `Documents/fonts/` to new
  /// `Documents/xdnmb_client/fonts/` if needed.
  Future<void> _migrateFontPathsIfNeeded() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final oldFontDir = p.join(docsDir.path, 'fonts');
    final newFontDir = p.join(docsDir.path, 'xdnmb_client', 'fonts');

    var needsSave = false;
    FontConfig migrateFont(FontConfig font) {
      final newPaths = List<String>.from(font.userFontPaths);
      for (var i = 0; i < newPaths.length; i++) {
        if (newPaths[i].startsWith(oldFontDir) &&
            !newPaths[i].startsWith(newFontDir)) {
          newPaths[i] = newPaths[i].replaceFirst(oldFontDir, newFontDir);
          needsSave = true;
        }
      }
      return font.copyWith(userFontPaths: newPaths);
    }

    final newContentFont = migrateFont(_settings.contentFont);
    final newUiFont = migrateFont(_settings.uiFont);

    if (needsSave) {
      _settings = _settings.copyWith(
        contentFont: newContentFont,
        uiFont: newUiFont,
      );
      await _save();
    }
  }

  Future<void> _save() async {
    await _fileStore.write(_settings);
    notifyListeners();
  }

  // ── Generic update ──

  Future<void> update(AppSettings Function(AppSettings) fn) async {
    _settings = fn(_settings);
    await _save();
  }

  // ── Appearance ──

  Future<void> setThemeMode(ThemeMode mode) async {
    _settings = _settings.copyWith(themeMode: mode);
    await _save();
  }

  Future<void> setPreviewMaxLines(int value) async {
    _settings = _settings.copyWith(previewMaxLines: value);
    await _save();
  }

  // ── Content font ──

  Future<void> setContentFont(FontConfig value) async {
    _settings = _settings.copyWith(contentFont: value);
    await _save();
  }

  Future<void> setContentFontSize(double value) async {
    _settings = _settings.copyWith(
      contentFont: _settings.contentFont.copyWith(fontSize: value),
    );
    await _save();
  }

  Future<void> setContentLineHeight(double value) async {
    _settings = _settings.copyWith(
      contentFont: _settings.contentFont.copyWith(lineHeight: value),
    );
    await _save();
  }

  Future<void> setContentFontWeight(String value) async {
    _settings = _settings.copyWith(
      contentFont: _settings.contentFont.copyWith(fontWeight: value),
    );
    await _save();
  }

  Future<void> setContentFallbackOrder(List<String> order) async {
    _settings = _settings.copyWith(
      contentFont: _settings.contentFont.copyWith(fallbackOrder: order),
    );
    await _save();
  }

  Future<void> addContentFallbackFont(String family) async {
    if (family.trim().isEmpty) return;
    final list = [..._settings.contentFont.fallbackOrder];
    if (list.contains(family)) return;
    list.add(family);
    _settings = _settings.copyWith(
      contentFont: _settings.contentFont.copyWith(fallbackOrder: list),
    );
    await _save();
  }

  Future<void> removeContentFallbackFont(int index) async {
    final list = List<String>.from(_settings.contentFont.fallbackOrder)
      ..removeAt(index);
    _settings = _settings.copyWith(
      contentFont: _settings.contentFont.copyWith(fallbackOrder: list),
    );
    await _save();
  }

  Future<void> reorderContentFallbackFonts(int oldIndex, int newIndex) async {
    final list = List<String>.from(_settings.contentFont.fallbackOrder);
    if (oldIndex < 0 || oldIndex >= list.length) return;
    final item = list.removeAt(oldIndex);
    final insertIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (insertIndex < 0 || insertIndex > list.length) {
      list.insert(oldIndex, item);
      return;
    }
    list.insert(insertIndex, item);
    _settings = _settings.copyWith(
      contentFont: _settings.contentFont.copyWith(fallbackOrder: list),
    );
    await _save();
  }

  // ── UI font ──

  Future<void> setUiFont(FontConfig value) async {
    _settings = _settings.copyWith(uiFont: value);
    await _save();
  }

  Future<void> setUiFontSize(double value) async {
    _settings = _settings.copyWith(
      uiFont: _settings.uiFont.copyWith(fontSize: value),
    );
    await _save();
  }

  Future<void> setUiFontWeight(String value) async {
    _settings = _settings.copyWith(
      uiFont: _settings.uiFont.copyWith(fontWeight: value),
    );
    await _save();
  }

  Future<void> setUiFallbackOrder(List<String> order) async {
    _settings = _settings.copyWith(
      uiFont: _settings.uiFont.copyWith(fallbackOrder: order),
    );
    await _save();
  }

  Future<void> addUiFallbackFont(String family) async {
    if (family.trim().isEmpty) return;
    final list = [..._settings.uiFont.fallbackOrder];
    if (list.contains(family)) return;
    list.add(family);
    _settings = _settings.copyWith(
      uiFont: _settings.uiFont.copyWith(fallbackOrder: list),
    );
    await _save();
  }

  Future<void> removeUiFallbackFont(int index) async {
    final list = List<String>.from(_settings.uiFont.fallbackOrder)
      ..removeAt(index);
    _settings = _settings.copyWith(
      uiFont: _settings.uiFont.copyWith(fallbackOrder: list),
    );
    await _save();
  }

  Future<void> reorderUiFallbackFonts(int oldIndex, int newIndex) async {
    final list = List<String>.from(_settings.uiFont.fallbackOrder);
    if (oldIndex < 0 || oldIndex >= list.length) return;
    final item = list.removeAt(oldIndex);
    final insertIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (insertIndex < 0 || insertIndex > list.length) {
      list.insert(oldIndex, item);
      return;
    }
    list.insert(insertIndex, item);
    _settings = _settings.copyWith(
      uiFont: _settings.uiFont.copyWith(fallbackOrder: list),
    );
    await _save();
  }

  // ── Font pool (shared between content and UI) ──

  Future<void> addAvailableFont(String family) async {
    if (family.trim().isEmpty) return;
    final c = _addToPool(_settings.contentFont, family);
    final u = _addToPool(_settings.uiFont, family);
    _settings = _settings.copyWith(contentFont: c, uiFont: u);
    await _save();
  }

  Future<void> removeAvailableFont(String family) async {
    final c = _removeFromPool(_settings.contentFont, family);
    final u = _removeFromPool(_settings.uiFont, family);
    _settings = _settings.copyWith(contentFont: c, uiFont: u);
    await _save();
  }

  static FontConfig _addToPool(FontConfig cfg, String family) {
    if (cfg.availableFonts.contains(family)) return cfg;
    return cfg.copyWith(
      availableFonts: [...cfg.availableFonts, family],
    );
  }

  static FontConfig _removeFromPool(FontConfig cfg, String family) {
    return cfg.copyWith(
      availableFonts: cfg.availableFonts.where((f) => f != family).toList(),
      fallbackOrder: cfg.fallbackOrder.where((f) => f != family).toList(),
    );
  }

  // ── Browse behaviour ──

  Future<void> setAutoLoadOnScroll(bool value) async {
    _settings = _settings.copyWith(autoLoadOnScroll: value);
    await _save();
  }

  Future<void> setShowImageInThread(bool value) async {
    _settings = _settings.copyWith(showImageInThread: value);
    await _save();
  }

  Future<void> setShowLineBreakIndicator(bool value) async {
    _settings = _settings.copyWith(showLineBreakIndicator: value);
    await _save();
  }

  Future<void> setThreadPreloadDistance(double value) async {
    _settings = _settings.copyWith(threadPreloadDistance: value);
    await _save();
  }

  // ── Debug / cache ──

  Future<void> setEnableDebugLog(bool value) async {
    _settings = _settings.copyWith(enableDebugLog: value);
    onDebugLogChanged?.call(value);
    await _save();
  }

  Future<void> setThreadCacheTtlMinutes(int value) async {
    _settings = _settings.copyWith(threadCacheTtlMinutes: value);
    onThreadCacheTtlChanged?.call(value);
    await _save();
  }

  // ── Storage ──

  Future<void> setDatabaseDirectory(String? value) async {
    _settings = _settings.copyWith(databaseDirectory: value);
    await _save();
  }

  Future<void> setDownloadDirectory(String? value) async {
    _settings = _settings.copyWith(downloadDirectory: value);
    await _save();
  }

  // ── Shortcuts ──

  Future<void> setShortcut(String action, String keyCombo) async {
    final map = Map<String, String>.from(_settings.shortcuts);
    map[action] = keyCombo;
    _settings = _settings.copyWith(shortcuts: map);
    await _save();
  }

  // ── Update ──

  Future<void> setAutoCheckUpdate(bool value) async {
    _settings = _settings.copyWith(autoCheckUpdate: value);
    await _save();
  }

  Future<void> setLastUpdateCheckAt(DateTime value) async {
    _settings = _settings.copyWith(lastUpdateCheckAt: value);
    await _save();
  }

  // ── Reset ──

  Future<void> reset() async {
    _settings = const AppSettings();
    await _save();
  }
}
