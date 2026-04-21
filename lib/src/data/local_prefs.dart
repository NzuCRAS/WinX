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
  static const _kEnableDebugLog = 'xdnmb.enableDebugLog';
  static const _kDatabaseDirectory = 'xdnmb.databaseDirectory';
  static const _kDownloadDirectory = 'xdnmb.downloadDirectory';
  static const _kThreadCacheTtlMinutes = 'xdnmb.threadCacheTtlMinutes';

  // ---- Auto update ----
  static const _kAutoCheckUpdate = 'xdnmb.autoCheckUpdate';
  static const _kLastUpdateCheckAt = 'xdnmb.lastUpdateCheckAt';

  // ---- Network URL cache (best-effort) ----
  static const _kUrlCacheBase = 'xdnmb.urlCache.baseUrl';
  static const _kUrlCacheCdn = 'xdnmb.urlCache.cdnUrl';
  static const _kUrlCacheBackupApi = 'xdnmb.urlCache.backupApiUrl';
  static const _kUrlCacheCdnCandidates = 'xdnmb.urlCache.cdnCandidates';
  static const _kUrlCacheUpdatedAtMs = 'xdnmb.urlCache.updatedAtMs';

  static const double defaultContentFontSize = 14.0;
  static const double defaultContentLineHeight = 1.5;
  static const String defaultThemeMode = 'system';
  static const int defaultPreviewMaxLines = 10;
  static const String defaultFontFamily = '';
  static const bool defaultAutoLoadOnScroll = true;
  static const bool defaultShowImageInThread = true;
  static const double defaultThreadPreloadDistance = 240.0;
  static const bool defaultEnableDebugLog = false;
  static const int defaultThreadCacheTtlMinutes = 5;

  SharedPreferences? _sp;
  Future<SharedPreferences> get _prefs async {
    return _sp ??= await SharedPreferences.getInstance();
  }

  Future<bool> getSkipAnnouncement() async {
    final sp = await _prefs;
    return sp.getBool(_kSkipAnnouncement) ?? false;
  }

  Future<void> setSkipAnnouncement(bool value) async {
    final sp = await _prefs;
    await sp.setBool(_kSkipAnnouncement, value);
  }

  Future<double> getContentFontSize() async {
    final sp = await _prefs;
    return sp.getDouble(_kContentFontSize) ?? defaultContentFontSize;
  }

  Future<void> setContentFontSize(double value) async {
    final sp = await _prefs;
    await sp.setDouble(_kContentFontSize, value);
  }

  Future<double> getContentLineHeight() async {
    final sp = await _prefs;
    return sp.getDouble(_kContentLineHeight) ?? defaultContentLineHeight;
  }

  Future<void> setContentLineHeight(double value) async {
    final sp = await _prefs;
    await sp.setDouble(_kContentLineHeight, value);
  }

  Future<String> getThemeMode() async {
    final sp = await _prefs;
    return sp.getString(_kThemeMode) ?? defaultThemeMode;
  }

  Future<void> setThemeMode(String value) async {
    final sp = await _prefs;
    await sp.setString(_kThemeMode, value);
  }

  Future<int> getPreviewMaxLines() async {
    final sp = await _prefs;
    return sp.getInt(_kPreviewMaxLines) ?? defaultPreviewMaxLines;
  }

  Future<void> setPreviewMaxLines(int value) async {
    final sp = await _prefs;
    await sp.setInt(_kPreviewMaxLines, value);
  }

  Future<String> getFontFamily() async {
    final sp = await _prefs;
    return sp.getString(_kFontFamily) ?? defaultFontFamily;
  }

  Future<void> setFontFamily(String value) async {
    final sp = await _prefs;
    await sp.setString(_kFontFamily, value);
  }

  Future<bool> getAutoLoadOnScroll() async {
    final sp = await _prefs;
    return sp.getBool(_kAutoLoadOnScroll) ?? defaultAutoLoadOnScroll;
  }

  Future<void> setAutoLoadOnScroll(bool value) async {
    final sp = await _prefs;
    await sp.setBool(_kAutoLoadOnScroll, value);
  }

  Future<bool> getShowImageInThread() async {
    final sp = await _prefs;
    return sp.getBool(_kShowImageInThread) ?? defaultShowImageInThread;
  }

  Future<void> setShowImageInThread(bool value) async {
    final sp = await _prefs;
    await sp.setBool(_kShowImageInThread, value);
  }

  Future<double> getThreadPreloadDistance() async {
    final sp = await _prefs;
    return sp.getDouble(_kThreadPreloadDistance) ?? defaultThreadPreloadDistance;
  }

  Future<void> setThreadPreloadDistance(double value) async {
    final sp = await _prefs;
    await sp.setDouble(_kThreadPreloadDistance, value);
  }

  Future<bool> getEnableDebugLog() async {
    final sp = await _prefs;
    return sp.getBool(_kEnableDebugLog) ?? defaultEnableDebugLog;
  }

  Future<void> setEnableDebugLog(bool value) async {
    final sp = await _prefs;
    await sp.setBool(_kEnableDebugLog, value);
  }

  /// Per-thread scroll offset storing.
  ///
  /// [key] should be a fully qualified preference key.
  /// This is intentionally low-level so callers can version/migrate keys.
  Future<double?> getThreadScrollOffset(String key) async {
    final sp = await _prefs;
    return sp.getDouble(key);
  }

  Future<void> setThreadScrollOffset(String key, double value) async {
    final sp = await _prefs;
    await sp.setDouble(key, value);
  }


  /// Per-thread reading progress anchor: saves a stable postId.
  Future<int?> getThreadProgressAnchorPostId(String key) async {
    final sp = await _prefs;
    return sp.getInt(key);
  }

  Future<void> setThreadProgressAnchorPostId(String key, int value) async {
    final sp = await _prefs;
    await sp.setInt(key, value);
  }

  /// Per-thread reading progress alignment in viewport, range [0, 1].
  Future<double?> getThreadProgressAlignment(String key) async {
    final sp = await _prefs;
    return sp.getDouble(key);
  }

  Future<void> setThreadProgressAlignment(String key, double value) async {
    final sp = await _prefs;
    await sp.setDouble(key, value);
  }

  /// Per-thread reading progress index hint (best-effort).
  ///
  /// Used when the saved anchor post is deleted or cannot be found after
  /// loading available pages. This helps us fall back to a nearby position.
  Future<int?> getThreadProgressTopIndexHint(String key) async {
    final sp = await _prefs;
    return sp.getInt(key);
  }

  Future<void> setThreadProgressTopIndexHint(String key, int value) async {
    final sp = await _prefs;
    await sp.setInt(key, value);
  }

  // ---- Cursor v2 (unified) ----

  /// Stores an encoded cursor blob (JSON string) for quick restore.
  Future<String?> getThreadCursor(String key) async {
    final sp = await _prefs;
    return sp.getString(key);
  }

  Future<void> setThreadCursor(String key, String value) async {
    final sp = await _prefs;
    await sp.setString(key, value);
  }

  Future<void> deleteThreadCursor(String key) async {
    final sp = await _prefs;
    await sp.remove(key);
  }

  // ---- URL cache ----

  Future<({Uri? baseUrl, Uri? cdnUrl, Uri? backupApiUrl, List<Uri>? cdnCandidates, DateTime? updatedAt})>
      getUrlCache() async {
    final sp = await _prefs;
    Uri? parseUri(String? v) => v == null ? null : Uri.tryParse(v);

    final baseUrl = parseUri(sp.getString(_kUrlCacheBase));
    final cdnUrl = parseUri(sp.getString(_kUrlCacheCdn));
    final backupApiUrl = parseUri(sp.getString(_kUrlCacheBackupApi));

    final rawCandidates = sp.getStringList(_kUrlCacheCdnCandidates);
    final cdnCandidates = rawCandidates
        ?.map((e) => Uri.tryParse(e))
        .whereType<Uri>()
        .toList(growable: false);

    final updatedAtMs = sp.getInt(_kUrlCacheUpdatedAtMs);
    final updatedAt = updatedAtMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(updatedAtMs, isUtc: false);

    return (
      baseUrl: baseUrl,
      cdnUrl: cdnUrl,
      backupApiUrl: backupApiUrl,
      cdnCandidates: cdnCandidates,
      updatedAt: updatedAt,
    );
  }

  Future<void> setUrlCache({
    required Uri baseUrl,
    required Uri cdnUrl,
    required Uri backupApiUrl,
    List<Uri>? cdnCandidates,
    DateTime? updatedAt,
  }) async {
    final sp = await _prefs;
    await sp.setString(_kUrlCacheBase, baseUrl.toString());
    await sp.setString(_kUrlCacheCdn, cdnUrl.toString());
    await sp.setString(_kUrlCacheBackupApi, backupApiUrl.toString());
    if (cdnCandidates != null) {
      await sp.setStringList(
        _kUrlCacheCdnCandidates,
        cdnCandidates.map((e) => e.toString()).toList(growable: false),
      );
    }
    await sp.setInt(
      _kUrlCacheUpdatedAtMs,
      (updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
    );
  }

  // ---- Storage paths ----

  Future<String?> getDatabaseDirectory() async {
    final sp = await _prefs;
    return sp.getString(_kDatabaseDirectory);
  }

  Future<void> setDatabaseDirectory(String? value) async {
    final sp = await _prefs;
    if (value == null) {
      await sp.remove(_kDatabaseDirectory);
    } else {
      await sp.setString(_kDatabaseDirectory, value);
    }
  }

  Future<String?> getDownloadDirectory() async {
    final sp = await _prefs;
    return sp.getString(_kDownloadDirectory);
  }

  Future<void> setDownloadDirectory(String? value) async {
    final sp = await _prefs;
    if (value == null) {
      await sp.remove(_kDownloadDirectory);
    } else {
      await sp.setString(_kDownloadDirectory, value);
    }
  }

  Future<int> getThreadCacheTtlMinutes() async {
    final sp = await _prefs;
    return sp.getInt(_kThreadCacheTtlMinutes) ?? defaultThreadCacheTtlMinutes;
  }

  Future<void> setThreadCacheTtlMinutes(int value) async {
    final sp = await _prefs;
    await sp.setInt(_kThreadCacheTtlMinutes, value);
  }

  // ---- Auto update ----

  Future<bool> getAutoCheckUpdate() async {
    final sp = await _prefs;
    return sp.getBool(_kAutoCheckUpdate) ?? true;
  }

  Future<void> setAutoCheckUpdate(bool value) async {
    final sp = await _prefs;
    await sp.setBool(_kAutoCheckUpdate, value);
  }

  Future<DateTime?> getLastUpdateCheckAt() async {
    final sp = await _prefs;
    final ms = sp.getInt(_kLastUpdateCheckAt);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setLastUpdateCheckAt(DateTime value) async {
    final sp = await _prefs;
    await sp.setInt(_kLastUpdateCheckAt, value.millisecondsSinceEpoch);
  }
}
