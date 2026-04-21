import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/io_client.dart';
import 'package:xdnmb_api/xdnmb_api.dart';

import '../data/cookie_store.dart';
import '../data/cdn_selector.dart';
import '../data/local_prefs.dart';
import '../data/xdnmb_repository.dart';
import '../ui/app_navigator.dart';
import '../data/perf_log.dart';
import 'composer_controller.dart';
import 'cookie_controller.dart';
import 'settings_controller.dart';

/// App-wide state coordinator.
///
/// Delegates cookie and settings concerns to dedicated controllers so that
/// UI pages can subscribe to only what they need.
final class AppState extends ChangeNotifier {
  final CookieStore cookieStore;
  final LocalPrefs prefs;
  late final XdnmbApi api;
  late final XdnmbRepository repo;
  late final CdnSelector cdnSelector;
  late final CookieController cookie;
  late final SettingsController settings;
  late final ComposerController composer;

  // Keep a single HttpClient for the whole app lifecycle so connections can be
  // reused (keep-alive) across requests.
  HttpClient? _httpClient;

  bool initialized = false;

  AppState({CookieStore? cookieStore, LocalPrefs? prefs})
      : cookieStore = cookieStore ?? CookieStore(),
        prefs = prefs ?? LocalPrefs();

  Future<void> init() async {
    final sw = Stopwatch()..start();
    PerfLog.log('app.init start');

    _httpClient = HttpClient();
    _httpClient!.connectionTimeout = const Duration(seconds: 15);
    _httpClient!.idleTimeout = const Duration(seconds: 90);

    // Load cookies first so we know which userhash to use for API init.
    final slots = await cookieStore.readSlots();
    final activeId = await cookieStore.readActiveSlotId();
    final defaultPost = await cookieStore.readDefaultPostSlot();
    final defaultAuth = await cookieStore.readDefaultAuthSlot();

    final CookieSlot? browsingSlot = defaultAuth ?? await cookieStore.readActiveSlot();

    XdnmbUrlsSharedHttpClient.set(IOClient(_httpClient!));
    api = XdnmbApi(userHash: browsingSlot?.userHash, client: _httpClient);
    if (browsingSlot != null) {
      api.xdnmbCookie = XdnmbCookie(browsingSlot.userHash, name: browsingSlot.name);
    }
    repo = XdnmbRepository(api);

    // Wire up controllers.
    cookie = CookieController(
      store: cookieStore,
      api: api,
      repo: repo,
    );
    // Seed controller with already-loaded values (avoids second DB read).
    cookie
      ..slots = slots
      ..activeSlotId = activeId
      ..defaultPostSlotId = defaultPost?.id
      ..defaultAuthSlotId = defaultAuth?.id
      ..cookieName = browsingSlot?.name;

    settings = SettingsController(prefs: prefs);
    settings.onDebugLogChanged = (v) => repo.enableDebugLog = v;
    settings.onThreadCacheTtlChanged = (v) =>
        repo.setThreadCacheTtl(Duration(minutes: v));
    await settings.init();

    composer = ComposerController();
    repo.enableDebugLog = settings.enableDebugLog;
    repo.setThreadCacheTtl(Duration(minutes: settings.threadCacheTtlMinutes));

    PerfLog.log('app.init cookies+settings durMs=${sw.elapsedMilliseconds}');

    // ---- URL cache (cold-start speed-up) ----
    try {
      final cache = await prefs.getUrlCache();
      if (cache.baseUrl != null ||
          cache.cdnUrl != null ||
          cache.backupApiUrl != null ||
          (cache.cdnCandidates != null && cache.cdnCandidates!.isNotEmpty)) {
        XdnmbUrls.overrideAll(
          baseUrl: cache.baseUrl,
          cdnUrl: cache.cdnUrl,
          backupApiUrl: cache.backupApiUrl,
          cdnCandidates: cache.cdnCandidates,
        );
        PerfLog.log(
          'app.urlCache.apply ok updatedAt=${cache.updatedAt?.toIso8601String() ?? 'null'}',
        );
      } else {
        PerfLog.log('app.urlCache.apply skip');
      }
    } catch (e) {
      PerfLog.log('app.urlCache.apply err=$e');
    }

    cdnSelector = CdnSelector(
      candidatesProvider: () => XdnmbUrls().cdnCandidates,
    );
    repo.debugShow = (title, message) {
      final ctx = AppNavigator.navigatorKey.currentContext;
      if (ctx == null) return;
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
    repo.setAuthCookie(defaultAuth?.userHash == null
        ? null
        : XdnmbCookie(defaultAuth!.userHash, name: defaultAuth.name).cookie);

    // Mark app as ready for UI immediately.
    initialized = true;
    notifyListeners();

    sw.stop();
    PerfLog.log('app.init ready durMs=${sw.elapsedMilliseconds}');

    // Best-effort URL update; don't block app start on failure.
    // ignore: discarded_futures
    PerfLog.time('app.warmUpNetwork', _warmUpNetwork);

    // CDN 测速：不阻塞启动。
    // ignore: discarded_futures
    PerfLog.time('app.cdnSelector.start', () async {
      await cdnSelector.start();
    });
  }

  Future<void> _warmUpNetwork() async {
    try {
      await repo.updateUrls();
      try {
        final urls = XdnmbUrls();
        await prefs.setUrlCache(
          baseUrl: urls.baseUrl,
          cdnUrl: urls.cdnUrl,
          backupApiUrl: urls.backupApiUrl,
          cdnCandidates: urls.cdnCandidates,
          updatedAt: DateTime.now(),
        );
        PerfLog.log('app.urlCache.save ok');
      } catch (e) {
        PerfLog.log('app.urlCache.save err=$e');
      }
    } catch (_) {
      // ignore
    }
  }

  @override
  void dispose() {
    composer.dispose();
    try {
      repo.dispose();
    } catch (_) {}
    try {
      api.close();
    } catch (_) {
      // ignore any late init errors
    }

    final c = _httpClient;
    _httpClient = null;
    c?.close(force: true);
    XdnmbApi.closeSharedHttpClient();
    super.dispose();
  }
}
