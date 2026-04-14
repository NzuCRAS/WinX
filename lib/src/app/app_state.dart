import 'package:flutter/material.dart';
import 'package:xdnmb_api/xdnmb_api.dart';

import '../data/cookie_store.dart';
import '../data/local_prefs.dart';
import '../data/xdnmb_repository.dart';
import '../ui/app_navigator.dart';

final class AppState extends ChangeNotifier {
  final CookieStore cookieStore;
  final LocalPrefs prefs;
  late final XdnmbApi api;
  late final XdnmbRepository repo;

  bool initialized = false;
  List<CookieSlot> cookieSlots = const [];
  String? activeCookieSlotId;
  String? defaultPostCookieSlotId;
  String? defaultAuthCookieSlotId;
  String? cookieName;

  // Settings
  double contentFontSize = LocalPrefs.defaultContentFontSize;
  double contentLineHeight = LocalPrefs.defaultContentLineHeight;
  ThemeMode themeMode = ThemeMode.system;
  int previewMaxLines = LocalPrefs.defaultPreviewMaxLines;
  String fontFamily = LocalPrefs.defaultFontFamily;
  bool autoLoadOnScroll = LocalPrefs.defaultAutoLoadOnScroll;
  bool showImageInThread = LocalPrefs.defaultShowImageInThread;
  double threadPreloadDistance = LocalPrefs.defaultThreadPreloadDistance;

  AppState({CookieStore? cookieStore, LocalPrefs? prefs})
      : cookieStore = cookieStore ?? CookieStore(),
        prefs = prefs ?? LocalPrefs();

  Future<void> init() async {
    cookieSlots = await cookieStore.readSlots();
    activeCookieSlotId = await cookieStore.readActiveSlotId();
    final defaultPost = await cookieStore.readDefaultPostSlot();
    final defaultAuth = await cookieStore.readDefaultAuthSlot();
    defaultPostCookieSlotId = defaultPost?.id;
    defaultAuthCookieSlotId = defaultAuth?.id;

    // For general browsing, prefer auth cookie if present.
    final CookieSlot? browsingSlot = defaultAuth ?? await cookieStore.readActiveSlot();
    cookieName = browsingSlot?.name;

    api = XdnmbApi(userHash: browsingSlot?.userHash);
    // Ensure cookie is actually sent as Cookie header via SDK.
    if (browsingSlot != null) {
      api.xdnmbCookie = XdnmbCookie(browsingSlot.userHash, name: browsingSlot.name);
    }
  repo = XdnmbRepository(api);
    // Optional: show auth debug info in a dialog to avoid relying on console logs.
    repo.debugShow = (title, message) {
      final ctx = AppNavigator.navigatorKey.currentContext;
      if (ctx == null) return;
      // Fire-and-forget; dialog dismissal is user-driven.
      // ignore: discarded_futures
      showDialog<void>(
        context: ctx,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: SelectableText(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    };
  // Provide explicit auth cookie fallback.
  repo.setAuthCookie(defaultAuth?.userHash == null
    ? null
    : XdnmbCookie(defaultAuth!.userHash, name: defaultAuth.name).cookie);

    // Load user settings.
    contentFontSize = await prefs.getContentFontSize();
    contentLineHeight = await prefs.getContentLineHeight();
    previewMaxLines = await prefs.getPreviewMaxLines();
    fontFamily = await prefs.getFontFamily();
    autoLoadOnScroll = await prefs.getAutoLoadOnScroll();
    showImageInThread = await prefs.getShowImageInThread();
    threadPreloadDistance = await prefs.getThreadPreloadDistance();
    final tm = await prefs.getThemeMode();
    themeMode = switch (tm) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    // Mark app as ready for UI immediately.
    initialized = true;
    notifyListeners();

    // Best-effort URL update; don't block app start on failure.
    // If this fails (e.g. TLS handshake), the user should still see the app UI
    // and can retry by refreshing.
    // ignore: discarded_futures
    _warmUpNetwork();
  }

  Future<void> _warmUpNetwork() async {
    try {
      await repo.updateUrls();
    } catch (_) {
      // ignore
    }
  }

  bool get hasCookie => api.xdnmbCookie != null;

  /// Cookie header value used for posting/replying.
  ///
  /// We always prefer the user's configured "default post" cookie slot.
  /// Returns the full cookie header value (e.g. `userhash=%CD%02...`).
  String? get defaultPostCookieHeader {
    final slot = defaultPostCookieSlot;
    if (slot == null) return null;
    return XdnmbCookie(slot.userHash, name: slot.name).cookie;
  }

  CookieSlot? _findSlot(String? id) {
    if (id == null) return null;
    for (final s in cookieSlots) {
      if (s.id == id) return s;
    }
    return null;
  }

  CookieSlot? get defaultPostCookieSlot => _findSlot(defaultPostCookieSlotId);
  CookieSlot? get defaultAuthCookieSlot => _findSlot(defaultAuthCookieSlotId);

  CookieSlot? get activeCookieSlot {
    if (cookieSlots.isEmpty) return null;
    final id = activeCookieSlotId;
    if (id == null) return cookieSlots.first;
    return cookieSlots.firstWhere((s) => s.id == id,
        orElse: () => cookieSlots.first);
  }

  Future<void> importCookie({required XdnmbCookie cookie}) async {
    api.xdnmbCookie = cookie;
    await cookieStore.upsertSlot(userHash: cookie.userHash, name: cookie.name);

    // Make the imported cookie actually take effect for both browsing and auth.
    // upsertSlot() already activates the slot; we reuse the active slot id.
    final slotId = await cookieStore.readActiveSlotId();
    if (slotId != null) {
      await cookieStore.setDefaultAuthSlot(slotId);
      await cookieStore.setDefaultPostSlot(slotId);
    }

  cookieSlots = await cookieStore.readSlots();
  activeCookieSlotId = await cookieStore.readActiveSlotId();
  final defaultPost = await cookieStore.readDefaultPostSlot();
  final defaultAuth = await cookieStore.readDefaultAuthSlot();
  defaultPostCookieSlotId = defaultPost?.id;
  defaultAuthCookieSlotId = defaultAuth?.id;
    cookieName = cookie.name;
    notifyListeners();
  }

  Future<void> switchCookieSlot(String slotId) async {
    await cookieStore.setActiveSlot(slotId);
    activeCookieSlotId = slotId;
    final slot = (await cookieStore.readActiveSlot());
    api.xdnmbCookie = slot == null ? null : XdnmbCookie(slot.userHash, name: slot.name);
    cookieName = slot?.name;
    notifyListeners();
  }

  Future<void> updateCookieSlotMeta(
    String slotId, {
    String? name,
    String? note,
  }) async {
    await cookieStore.updateSlot(slotId, name: name, note: note);
    cookieSlots = await cookieStore.readSlots();
    // Refresh derived ids.
    final defaultPost = await cookieStore.readDefaultPostSlot();
    final defaultAuth = await cookieStore.readDefaultAuthSlot();
    defaultPostCookieSlotId = defaultPost?.id;
    defaultAuthCookieSlotId = defaultAuth?.id;
  repo.setAuthCookie(defaultAuth?.userHash == null
    ? null
    : XdnmbCookie(defaultAuth!.userHash, name: defaultAuth.name).cookie);
    notifyListeners();
  }

  Future<void> setDefaultPostCookieSlot(String slotId) async {
    await cookieStore.setDefaultPostSlot(slotId);
    cookieSlots = await cookieStore.readSlots();
    final defaultPost = await cookieStore.readDefaultPostSlot();
    defaultPostCookieSlotId = defaultPost?.id;
    notifyListeners();
  }

  Future<void> setDefaultAuthCookieSlot(String slotId) async {
    await cookieStore.setDefaultAuthSlot(slotId);
    cookieSlots = await cookieStore.readSlots();
    final defaultAuth = await cookieStore.readDefaultAuthSlot();
    defaultAuthCookieSlotId = defaultAuth?.id;

    // Apply auth cookie to API immediately (browsing may require it).
    final slot = _findSlot(slotId);
    api.xdnmbCookie = slot == null ? null : XdnmbCookie(slot.userHash, name: slot.name);
    cookieName = slot?.name;

  repo.setAuthCookie(slot == null ? null : XdnmbCookie(slot.userHash, name: slot.name).cookie);

  // Switching auth cookie should invalidate caches in case previous loads
  // were denied and cached upstream states.
  repo.clearCaches();
    notifyListeners();
  }

  Future<void> deleteCookieSlot(String slotId) async {
    await cookieStore.deleteSlot(slotId);
    cookieSlots = await cookieStore.readSlots();
    activeCookieSlotId = await cookieStore.readActiveSlotId();
  final defaultPost = await cookieStore.readDefaultPostSlot();
  final defaultAuth = await cookieStore.readDefaultAuthSlot();
  defaultPostCookieSlotId = defaultPost?.id;
  defaultAuthCookieSlotId = defaultAuth?.id;
  repo.setAuthCookie(defaultAuth?.userHash == null
    ? null
    : XdnmbCookie(defaultAuth!.userHash, name: defaultAuth.name).cookie);
    final slot = await cookieStore.readActiveSlot();
    api.xdnmbCookie = slot == null ? null : XdnmbCookie(slot.userHash, name: slot.name);
    cookieName = slot?.name;
    notifyListeners();
  }

  Future<void> clearAllCookies() async {
    api.xdnmbCookie = null;
    await cookieStore.clearAll();
    cookieSlots = const [];
    activeCookieSlotId = null;
  defaultPostCookieSlotId = null;
  defaultAuthCookieSlotId = null;
  repo.clearCaches();
  repo.setAuthCookie(null);
    cookieName = null;
    notifyListeners();
  }

  // ── Settings ──

  Future<void> setContentFontSize(double value) async {
    contentFontSize = value;
    await prefs.setContentFontSize(value);
    notifyListeners();
  }

  Future<void> setContentLineHeight(double value) async {
    contentLineHeight = value;
    await prefs.setContentLineHeight(value);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    final s = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    };
    await prefs.setThemeMode(s);
    notifyListeners();
  }

  Future<void> setPreviewMaxLines(int value) async {
    previewMaxLines = value;
    await prefs.setPreviewMaxLines(value);
    notifyListeners();
  }

  Future<void> setFontFamily(String value) async {
    fontFamily = value;
    await prefs.setFontFamily(value);
    notifyListeners();
  }

  Future<void> setAutoLoadOnScroll(bool value) async {
    autoLoadOnScroll = value;
    await prefs.setAutoLoadOnScroll(value);
    notifyListeners();
  }

  Future<void> setShowImageInThread(bool value) async {
    showImageInThread = value;
    await prefs.setShowImageInThread(value);
    notifyListeners();
  }

  Future<void> setThreadPreloadDistance(double value) async {
    threadPreloadDistance = value;
    await prefs.setThreadPreloadDistance(value);
    notifyListeners();
  }

  Future<void> resetSettings() async {
    await setContentFontSize(LocalPrefs.defaultContentFontSize);
    await setContentLineHeight(LocalPrefs.defaultContentLineHeight);
    await setThemeMode(ThemeMode.system);
    await setPreviewMaxLines(LocalPrefs.defaultPreviewMaxLines);
    await setFontFamily(LocalPrefs.defaultFontFamily);
    await setAutoLoadOnScroll(LocalPrefs.defaultAutoLoadOnScroll);
    await setShowImageInThread(LocalPrefs.defaultShowImageInThread);
    await setThreadPreloadDistance(LocalPrefs.defaultThreadPreloadDistance);
  }
}
