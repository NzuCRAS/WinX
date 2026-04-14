import 'package:shared_preferences/shared_preferences.dart';

/// Very small wrapper for simple local preferences.
final class LocalPrefs {
  static const _kSkipAnnouncement = 'xdnmb.skipAnnouncement';
  static const _kContentFontSize = 'xdnmb.contentFontSize';
  static const _kContentLineHeight = 'xdnmb.contentLineHeight';
  static const _kThemeMode = 'xdnmb.themeMode';
  static const _kPreviewMaxLines = 'xdnmb.previewMaxLines';
  static const _kFontFamily = 'xdnmb.fontFamily';
  static const _kAutoLoadOnScroll = 'xdnmb.autoLoadOnScroll';
  static const _kShowImageInThread = 'xdnmb.showImageInThread';
  static const _kThreadPreloadDistance = 'xdnmb.threadPreloadDistance';

  static const double defaultContentFontSize = 14.0;
  static const double defaultContentLineHeight = 1.5;
  static const String defaultThemeMode = 'system';
  static const int defaultPreviewMaxLines = 10;
  static const String defaultFontFamily = '';
  static const bool defaultAutoLoadOnScroll = true;
  static const bool defaultShowImageInThread = true;
  static const double defaultThreadPreloadDistance = 240.0;

  Future<bool> getSkipAnnouncement() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kSkipAnnouncement) ?? false;
  }

  Future<void> setSkipAnnouncement(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kSkipAnnouncement, value);
  }

  Future<double> getContentFontSize() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getDouble(_kContentFontSize) ?? defaultContentFontSize;
  }

  Future<void> setContentFontSize(double value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(_kContentFontSize, value);
  }

  Future<double> getContentLineHeight() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getDouble(_kContentLineHeight) ?? defaultContentLineHeight;
  }

  Future<void> setContentLineHeight(double value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(_kContentLineHeight, value);
  }

  Future<String> getThemeMode() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_kThemeMode) ?? defaultThemeMode;
  }

  Future<void> setThemeMode(String value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kThemeMode, value);
  }

  Future<int> getPreviewMaxLines() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt(_kPreviewMaxLines) ?? defaultPreviewMaxLines;
  }

  Future<void> setPreviewMaxLines(int value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kPreviewMaxLines, value);
  }

  Future<String> getFontFamily() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_kFontFamily) ?? defaultFontFamily;
  }

  Future<void> setFontFamily(String value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kFontFamily, value);
  }

  Future<bool> getAutoLoadOnScroll() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kAutoLoadOnScroll) ?? defaultAutoLoadOnScroll;
  }

  Future<void> setAutoLoadOnScroll(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kAutoLoadOnScroll, value);
  }

  Future<bool> getShowImageInThread() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kShowImageInThread) ?? defaultShowImageInThread;
  }

  Future<void> setShowImageInThread(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kShowImageInThread, value);
  }

  Future<double> getThreadPreloadDistance() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getDouble(_kThreadPreloadDistance) ?? defaultThreadPreloadDistance;
  }

  Future<void> setThreadPreloadDistance(double value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(_kThreadPreloadDistance, value);
  }

  /// Per-thread scroll offset storing.
  ///
  /// [key] should be a fully qualified preference key.
  /// This is intentionally low-level so callers can version/migrate keys.
  Future<double?> getThreadScrollOffset(String key) async {
    final sp = await SharedPreferences.getInstance();
    return sp.getDouble(key);
  }

  Future<void> setThreadScrollOffset(String key, double value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(key, value);
  }


  /// Per-thread reading progress anchor: saves a stable postId.
  Future<int?> getThreadProgressAnchorPostId(String key) async {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt(key);
  }

  Future<void> setThreadProgressAnchorPostId(String key, int value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(key, value);
  }

  /// Per-thread reading progress alignment in viewport, range [0, 1].
  Future<double?> getThreadProgressAlignment(String key) async {
    final sp = await SharedPreferences.getInstance();
    return sp.getDouble(key);
  }

  Future<void> setThreadProgressAlignment(String key, double value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(key, value);
  }

  /// Per-thread reading progress index hint (best-effort).
  ///
  /// Used when the saved anchor post is deleted or cannot be found after
  /// loading available pages. This helps us fall back to a nearby position.
  Future<int?> getThreadProgressTopIndexHint(String key) async {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt(key);
  }

  Future<void> setThreadProgressTopIndexHint(String key, int value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(key, value);
  }
}
