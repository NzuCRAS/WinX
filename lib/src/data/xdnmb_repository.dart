import 'dart:collection';
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:html/parser.dart' show parse;
import 'package:xdnmb_api/xdnmb_api.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

import 'perf_log.dart';

final class _TtlLruCacheEntry<T> {
  final T value;
  final DateTime createdAt;
  _TtlLruCacheEntry(this.value) : createdAt = DateTime.now();
}

/// Very small TTL+LRU cache backed by LinkedHashMap.
///
/// - Access updates LRU order.
/// - Expired entries are evicted lazily.
final class _TtlLruCache<T> {
  final int maxEntries;
  final Duration ttl;
  final LinkedHashMap<String, _TtlLruCacheEntry<T>> _map = LinkedHashMap();

  _TtlLruCache({required this.maxEntries, required this.ttl});

  T? get(String key) {
    final e = _map.remove(key);
    if (e == null) return null;
    if (_isExpired(e)) {
      return null;
    }
    _map[key] = e;
    return e.value;
  }

  void set(String key, T value) {
    _map.remove(key);
    _map[key] = _TtlLruCacheEntry<T>(value);
    _evictIfNeeded();
  }

  void clear() => _map.clear();

  void removeWhere(bool Function(String key, T value) test) {
    final keys = <String>[];
    _map.forEach((k, v) {
      if (test(k, v.value)) keys.add(k);
    });
    for (final k in keys) {
      _map.remove(k);
    }
  }

  bool _isExpired(_TtlLruCacheEntry<T> e) {
    return DateTime.now().difference(e.createdAt) > ttl;
  }

  void _evictIfNeeded() {
    if (_map.isEmpty) return;
    final now = DateTime.now();
    final expiredKeys = <String>[];
    _map.forEach((k, v) {
      if (now.difference(v.createdAt) > ttl) expiredKeys.add(k);
    });
    for (final k in expiredKeys) {
      _map.remove(k);
    }

    while (_map.length > maxEntries) {
      _map.remove(_map.keys.first);
    }
  }
}

/// Per-thread cache session. Tracks cached page range and last access time
/// for TTL-based cleanup after the user leaves the thread.
final class _ThreadCacheSession {
  final int mainPostId;
  final bool onlyPo;
  int cachedMinPage;
  int cachedMaxPage;
  DateTime lastAccessedAt;

  _ThreadCacheSession({
    required this.mainPostId,
    required this.onlyPo,
    required this.cachedMinPage,
    required this.cachedMaxPage,
  }) : lastAccessedAt = DateTime.now();

  void touch() => lastAccessedAt = DateTime.now();

  String get _cachePrefix =>
      onlyPo ? 'threadOnlyPo:$mainPostId:' : 'thread:$mainPostId:';
}

/// Wraps [XdnmbApi] and provides in-memory caching.
final class XdnmbRepository {
  final XdnmbApi api;

  /// Optional debug hook to surface auth diagnostics in UI (e.g. a dialog).
  ///
  /// Intentionally nullable and opt-in to avoid introducing UI dependencies
  /// into this data layer.
  void Function(String title, String message)? debugShow;

  XdnmbRepository(this.api) {
    _startCleanupTimer();
  }

  ForumList? _lastForumList;

  // Single-flight in-flight requests by key.
  // This prevents repeated refresh taps from spawning multiple identical
  // requests and causing CPU/memory spikes.
  // NOTE: value type is Object? to support Future<void> (which completes with null).
  final _inflight = <String, Future<Object?>>{};

  // Lightweight concurrency gate for repository-level network requests.
  // This is intentionally simple (no cancellation), and works together with
  // single-flight to reduce handshake bursts on Windows.
  // Lowered to 3 because Windows Schannel can struggle with concurrent TLS
  // handshakes on some networks (proxy/AV/firewall interference).
  static const int _maxConcurrentRequests = 3;
  int _activeRequests = 0;
  final Queue<Completer<void>> _requestWaiters = Queue();

  // ---- In-memory page cache with TTL/LRU ----
  static const Duration _defaultPageCacheTtl = Duration(minutes: 5);

  final _forumPageCache = _TtlLruCache<List<ForumThread>>(
    maxEntries: 80,
    ttl: _defaultPageCacheTtl,
  );
  final _timelinePageCache = _TtlLruCache<List<ForumThread>>(
    maxEntries: 80,
    ttl: _defaultPageCacheTtl,
  );
  final _threadPageCache = _TtlLruCache<Thread>(
    maxEntries: 60,
    ttl: _defaultPageCacheTtl,
  );
  final _onlyPoThreadPageCache = _TtlLruCache<Thread>(
    maxEntries: 60,
    ttl: _defaultPageCacheTtl,
  );

  // ---- Per-thread cache sessions ----
  final Map<String, _ThreadCacheSession> _threadSessions = {};
  Duration _threadCacheTtl = _defaultPageCacheTtl;
  Timer? _cleanupTimer;

  Future<T> _singleFlight<T>(String key, Future<T> Function() request) {
    final existing = _inflight[key];
    if (existing != null) {
      return existing.then((v) => v as T);
    }

  final fut = request();
  // Store as Future<Object?> to share a single inflight map.
  // Important: Future<void> completes with `null`, so we must not cast to Object.
  final boxed = fut.then<Object?>((v) => v);
  _inflight[key] = boxed;
  return boxed.whenComplete(() {
      if (identical(_inflight[key], boxed)) {
        _inflight.remove(key);
      }
    }).then((v) => v as T);
  }

  Future<T> _withRequestGate<T>(Future<T> Function() request, {String? tag}) async {
    final gateSw = PerfLog.enabled ? (Stopwatch()..start()) : null;

    final tQueueStart = DateTime.now();
    if (_activeRequests >= _maxConcurrentRequests) {
      final c = Completer<void>();
      _requestWaiters.addLast(c);
      try {
        await c.future.timeout(const Duration(seconds: 30));
      } on TimeoutException {
        _requestWaiters.remove(c);
        throw TimeoutException(
            'Request queue timeout (tag=${tag ?? '-'})');
      }
    }

  final queuedMs = DateTime.now().difference(tQueueStart).inMilliseconds;

    _activeRequests++;
    final tStart = DateTime.now();
    try {
      try {
        final result = await request();
        final durMs = DateTime.now().difference(tStart).inMilliseconds;
        _dbg('gate ok tag=${tag ?? '-'} queuedMs=$queuedMs durMs=$durMs active=$_activeRequests');
        if (gateSw != null) {
          PerfLog.log(
            'net ${tag ?? '-'} queuedMs=$queuedMs durMs=$durMs totalMs=${gateSw.elapsedMilliseconds} active=$_activeRequests',
          );
        }
        return result;
      } on HandshakeException {
        // On Windows TLS handshake can fail intermittently (concurrent Schannel
        // limits, network jitter). Retry once as a safety net.
        _dbg('gate handshake-retry tag=${tag ?? '-'}');
        PerfLog.log('net.retry ${tag ?? '-'} handshake-retry');
        await Future.delayed(const Duration(milliseconds: 600));
        final result = await request();
        final durMs = DateTime.now().difference(tStart).inMilliseconds;
        _dbg('gate ok-after-retry tag=${tag ?? '-'} queuedMs=$queuedMs durMs=$durMs active=$_activeRequests');
        if (gateSw != null) {
          PerfLog.log(
            'net.ok-retry ${tag ?? '-'} queuedMs=$queuedMs durMs=$durMs totalMs=${gateSw.elapsedMilliseconds} active=$_activeRequests',
          );
        }
        return result;
      }
    } catch (e) {
      final durMs = DateTime.now().difference(tStart).inMilliseconds;
      _dbg('gate err tag=${tag ?? '-'} queuedMs=$queuedMs durMs=$durMs active=$_activeRequests err=$e');
      if (gateSw != null) {
        gateSw.stop();
        PerfLog.log(
          'net.err ${tag ?? '-'} queuedMs=$queuedMs durMs=$durMs totalMs=${gateSw.elapsedMilliseconds} active=$_activeRequests err=$e',
        );
      }
      rethrow;
    } finally {
      _activeRequests--;
      if (_requestWaiters.isNotEmpty && _activeRequests < _maxConcurrentRequests) {
        _requestWaiters.removeFirst().complete();
      }
    }
  }

  String? _authCookie;

  // Debug flag for diagnosing cookie-gated forums (e.g. 值班室) on Windows.
  // Keep it off by default to avoid noisy logs.
  static const bool _debugAuth = bool.fromEnvironment('XDNMB_DEBUG_AUTH', defaultValue: false);

  static const bool _debugAuthDialogEnabled =
      bool.fromEnvironment('XDNMB_DEBUG_AUTH_DIALOG', defaultValue: false);

  bool enableDebugLog = false;

  void _dbg(String message) {
    if (!_debugAuth && !enableDebugLog) return;
    developer.log(message, name: 'xdnmb.net');
  }

  String _cookieSummary(String? cookie) {
    if (cookie == null) return 'null';
    final c = cookie.trim();
    if (c.isEmpty) return 'empty';
    final prefix = c.replaceAll(RegExp(r'\s+'), ' ');
    final shown = prefix.length <= 24 ? prefix : prefix.substring(0, 24);
    return 'len=${c.length} hasUserhash=${c.contains('userhash=')} prefix="${shown.replaceAll('userhash=', 'userhash=***')}"';
  }

  String _hexByte(int b) => b.toRadixString(16).toUpperCase().padLeft(2, '0');

  String _bytesHexPrefix(String s, {int maxBytes = 16}) {
    List<int> bytes;
    try {
  bytes = latin1.encode(s);
    } catch (_) {
      bytes = s.runes.map((r) => r & 0xff).toList(growable: false);
    }
    final n = bytes.length < maxBytes ? bytes.length : maxBytes;
    return bytes.take(n).map(_hexByte).join(' ');
  }

  String _strPrefix(String s, {int max = 48}) {
    if (s.length <= max) return s;
    return s.substring(0, max);
  }

  String _sanitizeHeaderValueLikeSdk(String input) {
    // Mirror xdnmb_api's sanitizeHeaderValue(): remove ASCII control chars and DEL.
    final runes = input.runes.where((c) {
      if ((c >= 0x00 && c <= 0x1f) || c == 0x7f) return false;
      return true;
    });
    return String.fromCharCodes(runes);
  }

  String _sha256PrefixHex(String input, {int prefixBytes = 8}) {
    List<int> bytes;
    try {
  bytes = utf8.encode(input);
    } catch (_) {
      bytes = input.runes.map((r) => r & 0xff).toList(growable: false);
    }
    final d = sha256.convert(Uint8List.fromList(bytes)).bytes;
    final n = prefixBytes.clamp(1, d.length);
    return d.take(n).map(_hexByte).join();
  }

  ({bool seemsPercentEncoded, int percentTriples, int length}) _percentShape(
      String s) {
    var triples = 0;
    for (var i = 0; i + 2 < s.length; i++) {
      if (s.codeUnitAt(i) != 0x25 /* % */) continue;
      final hi = s.codeUnitAt(i + 1);
      final lo = s.codeUnitAt(i + 2);
      final isHex = ((hi >= 0x30 && hi <= 0x39) ||
              (hi >= 0x41 && hi <= 0x46) ||
              (hi >= 0x61 && hi <= 0x66)) &&
              ((lo >= 0x30 && lo <= 0x39) ||
              (lo >= 0x41 && lo <= 0x46) ||
              (lo >= 0x61 && lo <= 0x66));
      if (isHex) triples++;
    }
    final seems = triples >= 8;
    return (seemsPercentEncoded: seems, percentTriples: triples, length: s.length);
  }

  void _maybeShowAuthDebugDialog({
    required int forumId,
    required int page,
  }) {
    if (!_debugAuth || !_debugAuthDialogEnabled) return;
    final show = debugShow;
    if (show == null) return;

  final apiCookie = api.xdnmbCookie?.cookie;
  final apiUserHash = api.xdnmbCookie?.userHash;
    final authCookie = _authCookie;

    String fmt(String label, String? cookie) {
      if (cookie == null) return '$label: null';
      final shape = _percentShape(cookie);
      return [
        '$label:',
        '  sha256Prefix=${_sha256PrefixHex(cookie)}',
        '  len=${shape.length}',
        '  percentTriples=${shape.percentTriples}',
        '  seemsPercentEncoded=${shape.seemsPercentEncoded}',
        '  summary=${_cookieSummary(cookie)}',
      ].join('\n');
    }

    String? userHashDiag() {
      final uh = apiUserHash;
      if (uh == null) return null;
      // What we *intend* to send (percent-encoded bytes).
      final encoded = XdnmbCookie(uh).cookie;
      // What HttpClient will receive after SDK sanitizeHeaderValue.
      // This is important on Windows where control bytes are rejected in headers.
  final sanitized = _sanitizeHeaderValueLikeSdk(encoded);
      return [
        'userHash diag (api.xdnmbCookie.userHash):',
        '  rawBytesHexPrefix=${_bytesHexPrefix(uh)}',
        '  rawLen=${uh.length}',
        '  encodedPrefix=${_strPrefix(encoded)}',
        '  encodedPercentTriples=${_percentShape(encoded).percentTriples}',
        '  sanitizedEncodedPrefix=${_strPrefix(sanitized)}',
        '  sanitizedPercentTriples=${_percentShape(sanitized).percentTriples}',
      ].join('\n');
    }

    show(
      'Auth 调试（forum=$forumId page=$page）',
      [
        if (userHashDiag() != null) userHashDiag()!,
        if (userHashDiag() != null) '',
        fmt('apiCookie', apiCookie),
        fmt('authCookie', authCookie),
        '',
        '说明：sha256Prefix 用于和 curl 的 userhash 对比，不是明文。',
        '如果 seemsPercentEncoded=true，通常表示你存进来的 userHash 已经是 %XX 文本，可能被再次编码。',
      ].join('\n'),
    );
  }

  /// Provide an auth cookie (userhash cookie header value) for cookie-gated forums.
  ///
  /// This is used as a fallback when the current [api.xdnmbCookie] is not the
  /// intended auth slot.
  void setAuthCookie(String? cookie) {
    _authCookie = cookie;
  _dbg('setAuthCookie: ${_cookieSummary(cookie)}');
  }

  String _kForum(int forumId, int page) => 'forum:$forumId:$page:${XdnmbUrls().useBackupApi}';
  String _kTimeline(int timelineId, int page) =>
      'timeline:${timelineId.abs()}:$page:${XdnmbUrls().useBackupApi}';
  String _kThread(int mainPostId, int page) =>
      'thread:$mainPostId:$page:${XdnmbUrls().useBackupApi}';

  String _kOnlyPoThread(int mainPostId, int page) =>
      'threadOnlyPo:$mainPostId:$page:${XdnmbUrls().useBackupApi}';

  /// Best-effort prefetch & cache adjacent pages.
  ///
  /// This is intentionally fire-and-forget and should never throw to callers.
  /// Used to hide server TTFB when user is about to navigate to neighbor pages.
  ///
  /// Keeps a per-thread session of cached pages; within a session the cached
  /// range only grows. Expired sessions are cleaned up by [_cleanupTimer].
  Future<void> prefetchThreadAdjacentPages({
    required int mainPostId,
    required int currentPage,
    required bool onlyPo,
  }) async {
    startThreadSession(mainPostId, onlyPo);
    final key = '${onlyPo ? 'onlyPo:' : ''}$mainPostId';
    final session = _threadSessions[key];
    if (session == null) return;
    session.touch();

    // Target cache window: currentPage-2 .. currentPage+2, plus one look-ahead.
    final targetMin = (currentPage - 2).clamp(1, currentPage);
    final targetMax = currentPage + 2;
    final lookaheadPage = currentPage + 3;

    // Expand session range (only grows while inside the thread).
    if (session.cachedMinPage > targetMin) session.cachedMinPage = targetMin;
    if (session.cachedMaxPage < targetMax) session.cachedMaxPage = targetMax;
    if (session.cachedMaxPage < lookaheadPage) {
      session.cachedMaxPage = lookaheadPage;
    }

    final pagesToFetch = <int>{};
    final cache = onlyPo ? _onlyPoThreadPageCache : _threadPageCache;

    for (var p = session.cachedMinPage; p <= session.cachedMaxPage; p++) {
      if (p == currentPage) continue;
      final cacheKey = onlyPo ? _kOnlyPoThread(mainPostId, p) : _kThread(mainPostId, p);
      if (cache.get(cacheKey) == null) {
        pagesToFetch.add(p);
      }
    }
    if (pagesToFetch.isEmpty) return;

    for (final p in pagesToFetch) {
      final cacheKey = onlyPo ? _kOnlyPoThread(mainPostId, p) : _kThread(mainPostId, p);
      // ignore: discarded_futures
      _singleFlight<void>('prefetch:${onlyPo ? 'threadOnlyPoPage' : 'threadPage'}:$cacheKey', () async {
        try {
          final data = await _withRequestGate(
            () => onlyPo
                ? api.getOnlyPoThread(mainPostId, page: p)
                : api.getThread(mainPostId, page: p),
            tag: onlyPo ? 'prefetchOnlyPoThreadPage:$cacheKey' : 'prefetchThreadPage:$cacheKey',
          );
          cache.set(cacheKey, data);
        } catch (_) {
          // ignore
        }
        return;
      });
    }
  }

  void _trimThreadPages({
    required int mainPostId,
    required bool onlyPo,
    required int keepMinPage,
    required int keepMaxPage,
  }) {
    final prefix = onlyPo ? 'threadOnlyPo:$mainPostId:' : 'thread:$mainPostId:';
    final cache = onlyPo ? _onlyPoThreadPageCache : _threadPageCache;
    cache.removeWhere((k, _) {
      if (!k.startsWith(prefix)) return false;
      final parts = k.split(':');
      if (parts.length < 3) return false;
      final page = int.tryParse(parts[2]);
      if (page == null) return false;
      return page < keepMinPage || page > keepMaxPage;
    });
  }

  Future<void> prefetchForumAdjacentPages({
    required int forumId,
    required int currentPage,
    int backward = 0,
    int forward = 1,
    int keepMinPage = 1,
    int keepMaxPage = 999999,
  }) async {
    _trimForumPages(forumId: forumId, keepMinPage: keepMinPage, keepMaxPage: keepMaxPage);
    final pages = <int>{};
    for (var p = currentPage - backward; p <= currentPage + forward; p++) {
      if (p < 1) continue;
      if (p < keepMinPage || p > keepMaxPage) continue;
      if (p == currentPage) continue;
      pages.add(p);
    }
    for (final p in pages) {
      final key = _kForum(forumId, p);
      if (_forumPageCache.get(key) != null) continue;
      // ignore: discarded_futures
      _singleFlight<List<ForumThread>>('prefetch:forumPage:$key', () async {
        try {
          final data = await _withRequestGate(
            () => api.getForum(forumId, page: p),
            tag: 'prefetchForumPage:$key',
          );
          _forumPageCache.set(key, data);
          return data;
        } catch (_) {
          return const <ForumThread>[];
        }
      });
    }
  }

  void _trimForumPages({
    required int forumId,
    required int keepMinPage,
    required int keepMaxPage,
  }) {
    final prefix = 'forum:$forumId:';
    _forumPageCache.removeWhere((k, _) {
      if (!k.startsWith(prefix)) return false;
      final parts = k.split(':');
      if (parts.length < 3) return false;
      final page = int.tryParse(parts[2]);
      if (page == null) return false;
      return page < keepMinPage || page > keepMaxPage;
    });
  }

  Future<void> prefetchTimelineAdjacentPages({
    required int timelineId,
    required int currentPage,
    int backward = 0,
    int forward = 1,
    int keepMinPage = 1,
    int keepMaxPage = 999999,
  }) async {
    _trimTimelinePages(
      timelineId: timelineId,
      keepMinPage: keepMinPage,
      keepMaxPage: keepMaxPage,
    );
    final pages = <int>{};
    for (var p = currentPage - backward; p <= currentPage + forward; p++) {
      if (p < 1) continue;
      if (p < keepMinPage || p > keepMaxPage) continue;
      if (p == currentPage) continue;
      pages.add(p);
    }
    for (final p in pages) {
      final key = _kTimeline(timelineId, p);
      if (_timelinePageCache.get(key) != null) continue;
      // ignore: discarded_futures
      _singleFlight<List<ForumThread>>('prefetch:timelinePage:$key', () async {
        try {
          final data = await _withRequestGate(
            () => api.getTimeline(timelineId.abs(), page: p),
            tag: 'prefetchTimelinePage:$key',
          );
          _timelinePageCache.set(key, data);
          return data;
        } catch (_) {
          return const <ForumThread>[];
        }
      });
    }
  }

  void _trimTimelinePages({
    required int timelineId,
    required int keepMinPage,
    required int keepMaxPage,
  }) {
    final prefix = 'timeline:${timelineId.abs()}:';
    _timelinePageCache.removeWhere((k, _) {
      if (!k.startsWith(prefix)) return false;
      final parts = k.split(':');
      if (parts.length < 3) return false;
      final page = int.tryParse(parts[2]);
      if (page == null) return false;
      return page < keepMinPage || page > keepMaxPage;
    });
  }

  Future<void> updateUrls() => api.updateUrls();

  void useBackupApi(bool value) => api.useBackupApi(value);

  Future<ForumList> getForumList() async {
    const key = 'getForumList';
    return _singleFlight<ForumList>(key, () async {
      final list = await _withRequestGate(
        () => api.getForumList(),
        tag: 'getForumList',
      );
      _lastForumList = list;
      return list;
    });
  }

  Future<Notice> getNotice() {
    const key = 'getNotice';
    return _singleFlight<Notice>(key, () {
      return _withRequestGate(() => api.getNotice(), tag: 'getNotice');
    });
  }

  Future<HtmlForum> getHtmlForumInfo(int forumId) {
    final key = 'getHtmlForumInfo:$forumId';
    return _singleFlight<HtmlForum>(key, () {
      return _withRequestGate(
        () => api.getHtmlForumInfo(forumId),
        tag: 'getHtmlForumInfo:$forumId',
      );
    });
  }

  Future<List<Timeline>> getTimelineList() {
    const key = 'getTimelineList';
    return _singleFlight<List<Timeline>>(key, () {
      return _withRequestGate(
        () => api.getTimelineList(),
        tag: 'getTimelineList',
      );
    });
  }

  Future<List<ForumThread>> getTimelinePage(int timelineId, int page,
      {bool forceRefresh = false}) async {
  final key = _kTimeline(timelineId, page);
    if (!forceRefresh) {
  final cached = _timelinePageCache.get(key);
      if (cached != null) return cached;
    }

    return _singleFlight<List<ForumThread>>('timelinePage:$key', () async {
      final data = await _withRequestGate(
        () => api.getTimeline(timelineId.abs(), page: page),
        tag: 'getTimelinePage:$key',
      );
  _timelinePageCache.set(key, data);
      return data;
    });
  }

  Future<List<ForumThread>> getForumPage(int forumId, int page,
      {bool forceRefresh = false}) async {
    final key = _kForum(forumId, page);
    if (!forceRefresh) {
  final cached = _forumPageCache.get(key);
      if (cached != null) return cached;
    }

  _dbg('getForumPage start forumId=$forumId page=$page backup=${XdnmbUrls().useBackupApi} apiCookie=${_cookieSummary(api.xdnmbCookie?.cookie)} authCookie=${_cookieSummary(_authCookie)}');
  _maybeShowAuthDebugDialog(forumId: forumId, page: page);
    try {
      return _singleFlight<List<ForumThread>>('forumPage:$key', () async {
        final data = await _withRequestGate(
          () => api.getForum(forumId, page: page),
          tag: 'getForumPage:$key',
        );
        _forumPageCache.set(key, data);
        return data;
      });
    } on HandshakeException catch (e) {
      // Windows 上有时会对特定域名/链路握手失败（代理/AV/TLS）。
      // 这里做一次“切备用 API”的兜底，不要让首页直接不可用。
      _dbg('getForumPage handshake forumId=$forumId page=$page backup=${XdnmbUrls().useBackupApi} err=$e');
      if (!XdnmbUrls().useBackupApi) {
        try {
          api.useBackupApi(true);
          final retryKey = _kForum(forumId, page);
          final data = await _singleFlight<List<ForumThread>>(
            'forumPage:$retryKey:handshakeBackup',
            () async {
              final d = await _withRequestGate(
                () => api.getForum(forumId, page: page),
                tag: 'getForumPage:handshakeBackup:$retryKey',
              );
              _forumPageCache.set(retryKey, d);
              return d;
            },
          );
          return data;
        } on HandshakeException catch (e2) {
          _dbg('getForumPage handshake still failing on backup forumId=$forumId err=$e2');
          // fallthrough to html fallback below
        } finally {
          // Avoid sticky state changes; other calls can decide again.
          api.useBackupApi(false);
        }
      }

      // Final fallback: try HTML forum list if we can infer a slug.
      final authCookie = _authCookie ?? api.xdnmbCookie?.cookie;
      final slug = _inferForumSlug(forumId);
      if (authCookie != null && slug != null && slug.trim().isNotEmpty) {
        try {
          final htmlThreads = await _getForumThreadsFromSlug(
            slug: slug,
            forumId: forumId,
            page: page,
            cookie: authCookie,
          );
          _forumPageCache.set(key, htmlThreads);
          return htmlThreads;
        } catch (e3) {
          _dbg('getForumPage html fallback failed forumId=$forumId slug="$slug" err=$e3');
        }
      }
      rethrow;
    } on XdnmbApiException catch (e) {
      // Some cookie-gated forums may fail on backup API even with a valid cookie.
      // If we see a typical denial message, retry on primary.
      final msg = e.toString();
      final isCookieDenied = msg.contains('必须登入') || msg.contains('领取饼干');
      _dbg('getForumPage error forumId=$forumId backup=${XdnmbUrls().useBackupApi} isCookieDenied=$isCookieDenied msg=$msg');
      if (isCookieDenied && XdnmbUrls().useBackupApi) {
        api.useBackupApi(false);
        _dbg('cookie denied on backup api; retrying on primary forumId=$forumId');
        final retryKey = _kForum(forumId, page);
        return _singleFlight<List<ForumThread>>('forumPage:$retryKey', () async {
          final data = await _withRequestGate(
            () => api.getForum(forumId, page: page),
            tag: 'getForumPage:retryPrimary:$retryKey',
          );
          _forumPageCache.set(retryKey, data);
          return data;
        });
      }

      // If still denied, try once with the explicitly configured auth cookie.
      final authCookie = _authCookie;
      if (isCookieDenied && authCookie != null && authCookie.trim().isNotEmpty) {
  _dbg('cookie denied; retrying with explicit authCookie forumId=$forumId');
        final retryKey = _kForum(forumId, page);
        try {
          return _singleFlight<List<ForumThread>>('forumPage:$retryKey:auth', () async {
            final data = await _withRequestGate(
              () => api.getForum(forumId, page: page, cookie: authCookie),
              tag: 'getForumPage:authCookie:$retryKey',
            );
            _forumPageCache.set(retryKey, data);
            return data;
          });
        } on XdnmbApiException catch (e2) {
          final msg2 = e2.toString();
          final denied2 = msg2.contains('必须登入') || msg2.contains('领取饼干');
          _dbg('explicit authCookie retry failed forumId=$forumId denied=$denied2 msg=$msg2');
          // Special-case: some forums (e.g. 值班室) may be accessible on web (/f/slug)
          // but denied on JSON API. Try HTML Forum/showf as a final fallback.
          if (denied2 && forumId == 18) {
            final htmlThreads = await _getForumThreadsFromSlug(
              slug: '值班室',
              forumId: forumId,
              page: page,
              cookie: authCookie,
            );
            _forumPageCache.set(retryKey, htmlThreads);
            return htmlThreads;
          }

          // Generic fallback: try /f/<forumName> pages when JSON API is gated.
          if (denied2) {
            final slug = _inferForumSlug(forumId);
            if (slug != null && slug.trim().isNotEmpty) {
              final htmlThreads = await _getForumThreadsFromSlug(
                slug: slug,
                forumId: forumId,
                page: page,
                cookie: authCookie,
              );
              _forumPageCache.set(retryKey, htmlThreads);
              return htmlThreads;
            }
          }
          rethrow;
        }
      }
      // If we're already on primary and still denied, just bubble up.
      rethrow;
    }
  }

  String? _inferForumSlug(int forumId) {
    final list = _lastForumList;
    if (list == null) return null;
    final f = list.forumList.cast<Forum?>().firstWhere(
          (x) => x?.id == forumId,
          orElse: () => null,
        );
    if (f == null) return null;
    // showName might contain light HTML; strip it for slug usage.
    final name = f.showName.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    return name.isEmpty ? null : name;
  }

  Future<List<ForumThread>> _getForumThreadsFromSlug({
    required String slug,
    required int forumId,
    required int page,
    required String cookie,
  }) async {
    _dbg('HTML slug fallback start forumId=$forumId page=$page slug="$slug"');

    // Web endpoint confirmed by user: https://www.nmbxd1.com/f/<slug>
    // Some pages may ignore page; try with '?page=' conservatively.
    final encoded = Uri.encodeComponent(slug);
    final uri = Uri.parse('https://www.nmbxd1.com/f/$encoded')
        .replace(queryParameters: page > 1 ? {'page': '$page'} : null);

    // We don't reuse xdnmb_api's internal http Client here because it's not
    // exposed. For this fallback we only need to send the userhash cookie.
    final client = http.Client();
    try {
  final res = await client.get(uri, headers: {HttpHeaders.cookieHeader: cookie});
      if (res.statusCode != HttpStatus.ok) {
        throw XdnmbApiException('HTML 版块请求失败：HTTP ${res.statusCode}');
      }

      final document = parse(utf8.decode(res.bodyBytes));

      // Try to extract threads from common markup: .h-threads-item-main.
      // Don't rely on body text because it may include unrelated UI text.
      final items = document.querySelectorAll('div.h-threads-item-main');
      if (items.isEmpty) {
        // Look for a dedicated error container and surface it if present.
        final text = (document.body?.text ?? '').trim();
        final isDenied = text.contains('必须登入') || text.contains('领取饼干');
        if (isDenied) {
          throw XdnmbApiException('HTML 版块也被拒绝：必须登入领取饼干后才可以访问');
        }
        throw XdnmbApiException('HTML 解析失败：没找到 threads 列表（值班室）');
      }

      final now = DateTime.now().toUtc();
      final threads = <ForumThread>[];
      for (final el in items) {
        // Thread id is usually in: a.h-threads-info-id, text like "No.123".
        final idText = el.querySelector('a.h-threads-info-id')?.text ?? '';
        final id = int.tryParse(idText.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (id <= 0) continue;

        final uid = el.querySelector('span.h-threads-info-uid')?.text.trim() ?? '';
        final title = el.querySelector('span.h-threads-info-title')?.text.trim() ?? '';
        final content = el.querySelector('div.h-threads-content')?.text.trim() ?? '';

        threads.add(
          ForumThread(
            Post(
              id: id,
              forumId: forumId,
              replyCount: 0,
              image: '',
              imageExtension: '',
              postTime: now,
              userHash: uid,
              name: '无名氏',
              title: title.isEmpty ? '无标题' : title,
              content: content,
            ),
            const <Post>[],
            0,
          ),
        );
      }
  _dbg('HTML slug fallback parsed threads=${threads.length} forumId=$forumId page=$page');
      return threads;
    } finally {
      client.close();
    }
  }

  // ---- Thread cache session management ----

  void setThreadCacheTtl(Duration ttl) => _threadCacheTtl = ttl;

  void startThreadSession(int mainPostId, bool onlyPo) {
    final key = '${onlyPo ? 'onlyPo:' : ''}$mainPostId';
    final session = _threadSessions[key];
    if (session != null) {
      session.touch();
      return;
    }
    _threadSessions[key] = _ThreadCacheSession(
      mainPostId: mainPostId,
      onlyPo: onlyPo,
      cachedMinPage: 999999,
      cachedMaxPage: 0,
    );
  }

  void endThreadSession(int mainPostId, bool onlyPo) {
    final key = '${onlyPo ? 'onlyPo:' : ''}$mainPostId';
    final session = _threadSessions[key];
    if (session != null) {
      session.touch();
    }
  }

  void _cleanupExpiredThreadSessions() {
    final now = DateTime.now();
    final expiredKeys = <String>[];
    _threadSessions.forEach((key, session) {
      if (now.difference(session.lastAccessedAt) > _threadCacheTtl) {
        expiredKeys.add(key);
      }
    });
    for (final key in expiredKeys) {
      final session = _threadSessions.remove(key);
      if (session == null) continue;
      final cache = session.onlyPo ? _onlyPoThreadPageCache : _threadPageCache;
      cache.removeWhere((k, _) => k.startsWith(session._cachePrefix));
    }
  }

  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _cleanupExpiredThreadSessions(),
    );
  }

  void dispose() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }

  void clearCaches() {
    _forumPageCache.clear();
    _timelinePageCache.clear();
    _threadPageCache.clear();
    _onlyPoThreadPageCache.clear();
  }

  Future<Thread> getThreadPage(int mainPostId, int page,
      {bool forceRefresh = false}) async {
    final key = _kThread(mainPostId, page);
    if (!forceRefresh) {
  final cached = _threadPageCache.get(key);
      if (cached != null) return cached;
    }

    final data = await _singleFlight<Thread>('threadPage:$key', () {
      return _withRequestGate(
        () => api.getThread(mainPostId, page: page),
        tag: 'getThreadPage:$key',
      );
    });

  _threadPageCache.set(key, data);

    // Update session if one exists.
    final sessionKey = 'thread:$mainPostId';
    final session = _threadSessions[sessionKey];
    if (session != null) {
      session.touch();
      if (session.cachedMinPage > page) session.cachedMinPage = page;
      if (session.cachedMaxPage < page) session.cachedMaxPage = page;
    }

    return data;
  }

  Future<Thread> getOnlyPoThreadPage(int mainPostId, int page,
      {bool forceRefresh = false}) async {
    final key = _kOnlyPoThread(mainPostId, page);
    if (!forceRefresh) {
  final cached = _onlyPoThreadPageCache.get(key);
      if (cached != null) return cached;
    }

    final data = await _singleFlight<Thread>('threadOnlyPoPage:$key', () {
      return _withRequestGate(
        () => api.getOnlyPoThread(mainPostId, page: page),
        tag: 'getOnlyPoThreadPage:$key',
      );
    });

    _onlyPoThreadPageCache.set(key, data);

    // Update session if one exists.
    final sessionKey = 'onlyPo:$mainPostId';
    final session = _threadSessions[sessionKey];
    if (session != null) {
      session.touch();
      if (session.cachedMinPage > page) session.cachedMinPage = page;
      if (session.cachedMaxPage < page) session.cachedMaxPage = page;
    }

    return data;
  }

  Future<Reference> getReference(int postId) {
    final key = 'reference:$postId:${XdnmbUrls().useBackupApi}';
    return _singleFlight<Reference>(key, () {
      return _withRequestGate(
        () => api.getReference(postId),
        tag: 'getReference:$postId',
      );
    });
  }

  Future<List<Feed>> getFeed(String feedId, {int page = 1}) {
    final key = 'feed:$feedId:$page:${XdnmbUrls().useBackupApi}';
    return _singleFlight<List<Feed>>(key, () {
      return _withRequestGate(
        () => api.getFeed(feedId, page: page),
        tag: 'getFeed:$feedId:$page',
      );
    });
  }

  Future<void> addFeed(String feedId, int mainPostId) {
    return _withRequestGate(
      () => api.addFeed(feedId, mainPostId),
      tag: 'addFeed:$feedId:$mainPostId',
    );
  }

  Future<void> deleteFeed(String feedId, int mainPostId) {
    return _withRequestGate(
      () => api.deleteFeed(feedId, mainPostId),
      tag: 'deleteFeed:$feedId:$mainPostId',
    );
  }

  Future<Uri> getRandomCoverUrl() {
    const key = 'randomCoverUrl';
    return _singleFlight<Uri>(key, () {
      return _withRequestGate(
        () => api.getRandomCoverUrl(),
        tag: 'getRandomCoverUrl',
      );
    });
  }
}
