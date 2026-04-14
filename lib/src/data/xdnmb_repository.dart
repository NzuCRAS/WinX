import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

import 'package:xdnmb_api/xdnmb_api.dart';

import 'history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps [XdnmbApi] and provides in-memory caching.
final class XdnmbRepository {
  final XdnmbApi api;

  final HistoryStore _historyStore;

  /// Optional debug hook to surface auth diagnostics in UI (e.g. a dialog).
  ///
  /// Intentionally nullable and opt-in to avoid introducing UI dependencies
  /// into this data layer.
  void Function(String title, String message)? debugShow;

  XdnmbRepository(this.api, {HistoryStore? historyStore})
  : _historyStore = historyStore ?? HistoryStore();

  ForumList? _lastForumList;

  final _forumPageCache = HashMap<String, List<ForumThread>>();
  final _timelinePageCache = HashMap<String, List<ForumThread>>();
  final _threadPageCache = HashMap<String, Thread>();
  final _onlyPoThreadPageCache = HashMap<String, Thread>();

  String? _authCookie;

  // Debug flag for diagnosing cookie-gated forums (e.g. 值班室) on Windows.
  // Keep it off by default to avoid noisy logs.
  static const bool _debugAuth = bool.fromEnvironment('XDNMB_DEBUG_AUTH', defaultValue: false);

  static const bool _debugAuthDialogEnabled =
      bool.fromEnvironment('XDNMB_DEBUG_AUTH_DIALOG', defaultValue: false);

  void _dbg(String message) {
    if (!_debugAuth) return;
    developer.log(message, name: 'xdnmb.auth');
  }

  String _cookieSummary(String? cookie) {
    if (cookie == null) return 'null';
    final c = cookie.trim();
    if (c.isEmpty) return 'empty';
    // Avoid logging raw cookies; only show length and a small sanitized prefix.
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
      bytes = latin1.encode(input);
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

  Future<void> updateUrls() => api.updateUrls();

  void useBackupApi(bool value) => api.useBackupApi(value);

  Future<ForumList> getForumList() async {
    final list = await api.getForumList();
    _lastForumList = list;
    return list;
  }

  Future<Notice> getNotice() => api.getNotice();

  Future<HtmlForum> getHtmlForumInfo(int forumId) => api.getHtmlForumInfo(forumId);

  Future<List<Timeline>> getTimelineList() => api.getTimelineList();

  Future<List<ForumThread>> getTimelinePage(int timelineId, int page,
      {bool forceRefresh = false}) async {
  final key = _kTimeline(timelineId, page);
    if (!forceRefresh) {
      final cached = _timelinePageCache[key];
      if (cached != null) return cached;
    }

  final data = await api.getTimeline(timelineId.abs(), page: page);
    _timelinePageCache[key] = data;
    return data;
  }

  Future<List<ForumThread>> getForumPage(int forumId, int page,
      {bool forceRefresh = false}) async {
    final key = _kForum(forumId, page);
    if (!forceRefresh) {
      final cached = _forumPageCache[key];
      if (cached != null) return cached;
    }

  _dbg('getForumPage start forumId=$forumId page=$page backup=${XdnmbUrls().useBackupApi} apiCookie=${_cookieSummary(api.xdnmbCookie?.cookie)} authCookie=${_cookieSummary(_authCookie)}');
  _maybeShowAuthDebugDialog(forumId: forumId, page: page);
    try {
      final data = await api.getForum(forumId, page: page);
      _forumPageCache[key] = data;
      return data;
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
        final data = await api.getForum(forumId, page: page);
        _forumPageCache[retryKey] = data;
        return data;
      }

      // If still denied, try once with the explicitly configured auth cookie.
      final authCookie = _authCookie;
      if (isCookieDenied && authCookie != null && authCookie.trim().isNotEmpty) {
  _dbg('cookie denied; retrying with explicit authCookie forumId=$forumId');
        final retryKey = _kForum(forumId, page);
        try {
          final data = await api.getForum(forumId, page: page, cookie: authCookie);
          _forumPageCache[retryKey] = data;
          return data;
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
            _forumPageCache[retryKey] = htmlThreads;
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
              _forumPageCache[retryKey] = htmlThreads;
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
      final cached = _threadPageCache[key];
      if (cached != null) return cached;
    }

    final data = await api.getThread(mainPostId, page: page);

    // Best-effort: whenever we successfully fetch thread content, record it.
    // This ensures history works regardless of where the user enters a thread.
    // We only write on page=1 to avoid spamming history when auto-loading pages.
    if (page == 1) {
      // ignore: discarded_futures
      _historyStore.recordVisit(
        threadId: mainPostId,
    title: (data.mainPost.title.trim().isEmpty
      ? null
      : data.mainPost.title.trim()),
    userHash: data.mainPost.userHash.trim().isEmpty
      ? null
      : data.mainPost.userHash.trim(),
    isAdmin: data.mainPost.isAdmin,
    postTime: data.mainPost.postTime,
    replyCount: data.mainPost.replyCount,
    thumbImageUrl: data.mainPost.thumbImageUrl,
    content: data.mainPost.content,
      );

      // Extra debug breadcrumb: verify this code path is hit and whether writes stick.
      // ignore: discarded_futures
      () async {
        final sp = await SharedPreferences.getInstance();
        final t0 = DateTime.now().toIso8601String();
        await sp.setString(
          'xdnmb.history.debug.lastRecord',
          'repo.getThreadPage ok at $t0 threadId=$mainPostId (before readAll)',
        );

        final allNow = await _historyStore.readAll();
        final rawHistory = sp.getString('xdnmb.history.threads');
        final rawLen = rawHistory?.length ?? -1;
        final dbg = [
          'repo.getThreadPage ok at ${DateTime.now().toIso8601String()}',
          'threadId=$mainPostId',
          'readAll.count=${allNow.length}',
          'sp.getString(history).len=$rawLen',
        ].join(' ');

        // Best-effort; if this returns false, SharedPreferences backend is failing.
        final ok = await sp.setString('xdnmb.history.debug.lastRecord', dbg);
        if (!ok) {
          // One more try with explicit marker.
          // ignore: discarded_futures
          sp.setString('xdnmb.history.debug.lastRecord', '$dbg setString(lastRecord)=false');
        }
      }();
    }
    _threadPageCache[key] = data;
    return data;
  }

  Future<Thread> getOnlyPoThreadPage(int mainPostId, int page,
      {bool forceRefresh = false}) async {
    final key = _kOnlyPoThread(mainPostId, page);
    if (!forceRefresh) {
      final cached = _onlyPoThreadPageCache[key];
      if (cached != null) return cached;
    }

    final data = await api.getOnlyPoThread(mainPostId, page: page);

    if (page == 1) {
      // ignore: discarded_futures
      _historyStore.recordVisit(
        threadId: mainPostId,
    title: (data.mainPost.title.trim().isEmpty
      ? null
      : data.mainPost.title.trim()),
    userHash: data.mainPost.userHash.trim().isEmpty
      ? null
      : data.mainPost.userHash.trim(),
    isAdmin: data.mainPost.isAdmin,
    postTime: data.mainPost.postTime,
    replyCount: data.mainPost.replyCount,
    thumbImageUrl: data.mainPost.thumbImageUrl,
    content: data.mainPost.content,
      );

      // Extra debug breadcrumb for PO endpoint.
      // ignore: discarded_futures
      () async {
        final sp = await SharedPreferences.getInstance();
        final t0 = DateTime.now().toIso8601String();
        await sp.setString(
          'xdnmb.history.debug.lastRecord',
          'repo.getOnlyPoThreadPage ok at $t0 threadId=$mainPostId (before readAll)',
        );

        final allNow = await _historyStore.readAll();
        final rawHistory = sp.getString('xdnmb.history.threads');
        final rawLen = rawHistory?.length ?? -1;
        final dbg = [
          'repo.getOnlyPoThreadPage ok at ${DateTime.now().toIso8601String()}',
          'threadId=$mainPostId',
          'readAll.count=${allNow.length}',
          'sp.getString(history).len=$rawLen',
        ].join(' ');
        final ok = await sp.setString('xdnmb.history.debug.lastRecord', dbg);
        if (!ok) {
          // ignore: discarded_futures
          sp.setString('xdnmb.history.debug.lastRecord', '$dbg setString(lastRecord)=false');
        }
      }();
    }
    _onlyPoThreadPageCache[key] = data;
    return data;
  }

  Future<Reference> getReference(int postId) => api.getReference(postId);

  Future<List<Feed>> getFeed(String feedId, {int page = 1}) =>
    api.getFeed(feedId, page: page);

  Future<void> addFeed(String feedId, int mainPostId) =>
    api.addFeed(feedId, mainPostId);

  Future<void> deleteFeed(String feedId, int mainPostId) =>
    api.deleteFeed(feedId, mainPostId);

  Future<Uri> getRandomCoverUrl() => api.getRandomCoverUrl();
}
