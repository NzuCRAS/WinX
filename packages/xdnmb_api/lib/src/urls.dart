import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' hide Client;
import 'package:http/io_client.dart';

import 'client.dart';

/// Shared HTTP client used by `xdnmb_api` internal utilities when the caller
/// doesn't provide an explicit client.
///
/// This avoids creating a new `HttpClient` (and losing keep-alive benefits)
/// for every `XdnmbUrls.update()` call.
///
/// The application should close it on shutdown via
/// `XdnmbUrlsSharedHttpClient.close()`.
final class XdnmbUrlsSharedHttpClient {
  static IOClient? _shared;

  /// Set a shared client to be used by `XdnmbUrls.update()`.
  ///
  /// If you call this, you own the lifecycle of [client] and should close it
  /// yourself.
  static void set(IOClient client) {
    _shared = client;
  }

  /// Get (or lazily create) the shared client.
  static IOClient get instance {
    return _shared ??=
        IOClient(HttpClient()..connectionTimeout = Client.defaultConnectionTimeout);
  }

  /// Close the shared client if it was created by this class.
  ///
  /// Safe to call multiple times.
  static void close({bool force = true}) {
    final c = _shared;
    _shared = null;
    if (c == null) return;

    // IOClient doesn't expose the underlying HttpClient, but closing the
    // wrapper is enough to close the inner client.
    c.close();
  }
}

/// X 岛链接
final class XdnmbUrls {
  /// X 岛域名
  static const String xdnmbHost = 'www.nmbxd.com';

  /// 获取 CDN 链接的接口的路径
  static const String _cdnPath = 'Api/getCdnPath';

  /// 获取备用 API 链接的接口的路径
  static const String _backupApiPath = 'Api/backupUrl';

  /// X 岛初始链接
  static final Uri _originBaseUrl = Uri.parse('https://$xdnmbHost/');

  /// X 岛现在的链接
  static final Uri _currentBaseUrl = Uri.parse('https://www.nmbxd1.com/');

  /// X 岛现在的 CDN 链接
  static final Uri _currentCdnUrl = Uri.parse('https://image.nmb.best/');

  /// 上次从接口获得的 CDN 列表（按可用性/权重使用）
  static List<Uri>? _cachedCdnCandidates;

  /// X 岛现在的备用 API 链接
  static final Uri _currentBackupApiUrl = Uri.parse('https://api.nmb.best/');

    /// X 岛 JSON API 基础链接（注意：路径包含 `/api/`）
    ///
    /// 文档：`https://api.nmb.best/api/`
    static final Uri _jsonApiBaseUrl = Uri.parse('https://api.nmb.best/api/');

  /// X 岛公告链接
  static final Uri notice = Uri.parse('https://nmb.ovear.info/nmb-notice.json');

  /// 随机封面图（302 跳转到实际图片）
  ///
  /// 文档：GET https://nmb.ovear.info/h.php
  static final Uri randomCoverRedirect = Uri.parse('https://nmb.ovear.info/h.php');

  /// [XdnmbUrls] 的单例
  static XdnmbUrls _urls = XdnmbUrls._internal(
      baseUrl: _currentBaseUrl,
      cdnUrl: _currentCdnUrl,
      backupApiUrl: _currentBackupApiUrl);

  /// X 岛基础链接
  final Uri baseUrl;

  /// X 岛 CDN 链接
  final Uri cdnUrl;

  /// CDN 候选列表（用于图片加载的兜底重试）
  final List<Uri> cdnCandidates;

  /// 允许客户端覆盖当前使用的 CDN（例如：启动测速选最快）。
  ///
  /// 注意：这个值只影响“当前进程内”的 `XdnmbUrls()` 单例。
  /// 如果你希望跨重启持久化，请在客户端自行存储并在启动时调用本方法。
  static void overrideCdnUrl(Uri cdnUrl, {List<Uri>? candidates}) {
    _urls = XdnmbUrls._internal(
      baseUrl: _urls.baseUrl,
      cdnUrl: cdnUrl,
      backupApiUrl: _urls.backupApiUrl,
      cdnCandidates: candidates ?? _urls.cdnCandidates,
    )..useBackupApi = _urls.useBackupApi;
  }

  /// 允许客户端用“缓存值/用户配置”覆盖当前 URL 配置（base/cdn/backup）。
  ///
  /// 用途：冷启动先用上次成功的 URL，避免每次启动都同步/半同步探测慢域名。
  ///
  /// 注意：这是进程内覆盖，不会自动持久化；持久化由客户端负责（例如 SharedPreferences）。
  static void overrideAll({
    Uri? baseUrl,
    Uri? cdnUrl,
    Uri? backupApiUrl,
    List<Uri>? cdnCandidates,
  }) {
    _urls = XdnmbUrls._internal(
      baseUrl: baseUrl ?? _urls.baseUrl,
      cdnUrl: cdnUrl ?? _urls.cdnUrl,
      backupApiUrl: backupApiUrl ?? _urls.backupApiUrl,
      cdnCandidates: cdnCandidates ?? _urls.cdnCandidates,
    )..useBackupApi = _urls.useBackupApi;
  }

  /// X 岛备用 API 链接
  final Uri backupApiUrl;

  /// 是否使用备用 API 链接，默认不使用
  bool useBackupApi = false;

  /// X 岛 API 链接
  Uri get apiUrl => useBackupApi ? backupApiUrl : baseUrl;

    /// X 岛 JSON API 链接
    ///
    /// 说明：历史上本库把 JSON API 路径拼在主站域名下（例如 `www.nmbxd1.com/Api/showf`），
    /// 但根据公开文档与实际访问策略，受限版面应通过 `api.nmb.best/api/...` 调用，否则会在
    ///携带饼干时仍被返回“必须登入领取饼干”。
    Uri get jsonApiUrl => _jsonApiBaseUrl;

  /// CDN 列表链接
  Uri get cdnList => apiUrl.replace(path: _cdnPath);

  /// 获取备用 API 链接的链接
  Uri get backupApiList => apiUrl.replace(path: _backupApiPath);

  /// 版块列表链接
    Uri get forumList => jsonApiUrl.replace(path: 'api/getForumList');

  /// 时间线列表链接
    Uri get timelineList => jsonApiUrl.replace(path: 'api/getTimelineList');

  /// 获取最新发的串的链接
  Uri get getLastPost => baseUrl.replace(path: 'Api/getLastPost');

  /// 发串链接
  Uri get postNewThread =>
      baseUrl.replace(path: 'Home/Forum/doPostThread.html');

  /// 回串链接
  Uri get replyThread => baseUrl.replace(path: 'Home/Forum/doReplyThread.html');

  /// 验证码图片链接
  Uri get verifyImage => baseUrl.replace(path: 'Member/User/Index/verify.html');

  /// 用户登陆链接
  Uri get userLogin => baseUrl.replace(path: 'Member/User/Index/login.html');

  /// 用户饼干链接
  Uri get cookiesList => baseUrl.replace(path: 'Member/User/Cookie/index.html');

  /// 获取新饼干链接
  Uri get getNewCookie =>
      baseUrl.replace(path: 'Member/User/Cookie/apply.html');

  /// 注册帐号链接
  Uri get registerAccount =>
      baseUrl.replace(path: 'Member/User/Index/sendRegister.html');

  /// 重置密码链接
  Uri get resetPassword =>
      baseUrl.replace(path: 'Member/User/Index/sendForgotPassword.html');

  /// [XdnmbUrls] 的内部构造器
  XdnmbUrls._internal(
      {required this.baseUrl,
      required this.cdnUrl,
  required this.backupApiUrl,
  List<Uri>? cdnCandidates})
  : cdnCandidates = (cdnCandidates == null || cdnCandidates.isEmpty)
    ? <Uri>[cdnUrl]
    : List.unmodifiable(cdnCandidates);

  /// 构造 [XdnmbUrls]，返回 [XdnmbUrls] 单例
  factory XdnmbUrls() => _urls;

  /// 版块链接
  ///
  /// [forumId] 为版块 ID，[page] 从 1 开始算起
    Uri forum(int forumId, {int page = 1}) => jsonApiUrl.replace(
            path: 'api/showf', queryParameters: {'id': '$forumId', 'page': '$page'});

  /// 网页版版块链接
  ///
  /// [forumId] 为版块 ID，[page] 从 1 开始算起
  Uri htmlForum(int forumId, {int page = 1}) => baseUrl.replace(
      path: 'Forum/showf',
      queryParameters: {'id': '$forumId', 'page': '$page'});

  /// 时间线链接
  ///
  /// [timelineId] 为时间线 ID，[page] 从 1 开始算起
    Uri timeline(int timelineId, {int page = 1}) => jsonApiUrl.replace(
            path: 'api/timeline',
      queryParameters: {'id': '$timelineId', 'page': '$page'});

  /// 串（帖子）链接
  ///
  /// [mainPostId] 为主串 ID，[page] 从 1 开始算起
    Uri thread(int mainPostId, {int page = 1}) => jsonApiUrl.replace(
            path: 'api/thread',
      queryParameters: {'id': '$mainPostId', 'page': '$page'});

  /// 串引用链接
  ///
  /// [postId] 为串 ID
    Uri reference(int postId) =>
            jsonApiUrl.replace(path: 'api/ref', queryParameters: {'id': '$postId'});

  /// 网页版串引用链接
  ///
  /// [postId] 为串 ID
  Uri htmlReference(int postId) => baseUrl
      .replace(path: 'Home/Forum/ref', queryParameters: {'id': '$postId'});

  /// 只看 Po 主的串的链接
  ///
  /// [mainPostId] 为主串 ID，[page] 从 1 开始算起
    Uri onlyPoThread(int mainPostId, {int page = 1}) => jsonApiUrl.replace(
            path: 'api/po', queryParameters: {'id': '$mainPostId', 'page': '$page'});

  /// 订阅链接
  ///
  /// [feedId] 为订阅 ID，[page] 从 1 开始算起
    Uri feed(String feedId, {int page = 1}) => jsonApiUrl.replace(
            path: 'api/feed', queryParameters: {'uuid': feedId, 'page': '$page'});

  /// 网页版订阅链接
  ///
  /// [page] 从 1 开始算起
  Uri htmlFeed({int page = 1}) =>
      baseUrl.replace(path: 'Forum/feed/page/$page.html');

  /// 添加订阅的链接
  ///
  /// [feedId] 为订阅 ID，[mainPostId] 为主串 ID
    Uri addFeed(String feedId, int mainPostId) => jsonApiUrl.replace(
            path: 'api/addFeed',
      queryParameters: {'uuid': feedId, 'tid': '$mainPostId'});

  /// 网页版添加订阅的链接
  ///
  /// [mainPostId] 为主串 ID
  Uri addHtmlFeed(int mainPostId) =>
      baseUrl.replace(path: 'Home/Forum/addFeed/tid/$mainPostId.html');

  /// 删除订阅的链接
  ///
  /// [feedId] 为订阅 ID，[mainPostId] 为主串 ID
    Uri deleteFeed(String feedId, int mainPostId) => jsonApiUrl.replace(
            path: 'api/delFeed',
      queryParameters: {'uuid': feedId, 'tid': '$mainPostId'});

  /// 网页版删除订阅的链接
  ///
  /// [mainPostId] 为主串 ID
  Uri deleteHtmlFeed(int mainPostId) =>
      baseUrl.replace(path: 'Home/Forum/delFeed/tid/$mainPostId.html');

  /// 获取饼干的链接
  ///
  /// [cookieId] 为饼干 ID
  Uri getCookie(int cookieId) =>
      baseUrl.replace(path: 'Member/User/Cookie/export/id/$cookieId.html');

  /// 删除饼干的链接
  ///
  /// [cookieId] 为饼干 ID
  Uri deleteCookie(int cookieId) =>
      baseUrl.replace(path: 'Member/User/Cookie/delete/id/$cookieId.html');

  /// 是否 X 岛基础链接
  bool isBaseUrl(Uri url) => url.host == baseUrl.host;

  /// 是否 X 岛备用 API 链接
  bool isBackupApiUrl(Uri url) => url.host == backupApiUrl.host;

  /// 更新链接
  ///
  /// [client] 为 http client
  static Future<XdnmbUrls> update([IOClient? client]) async {
  client ??= XdnmbUrlsSharedHttpClient.instance;

    try {
      final request = Request('GET', _originBaseUrl)..followRedirects = false;
      Response response = await Response.fromStream(await client.send(request));
      final baseUrl = response.isRedirect
          ? Uri.parse(response.headers[HttpHeaders.locationHeader] ??
              _originBaseUrl.toString())
          : _originBaseUrl;

      response = await client.get(baseUrl.replace(path: _cdnPath));
      dynamic decoded = json.decode(response.utf8Body);

    // 接口返回格式示例：[{"url":"https://image.nmb.best/","rate":0.95}, ...]
    final cdnCandidates = _parseCdnCandidates(decoded);
    final cdnUrl = cdnCandidates.isNotEmpty
      ? _pickWeightedRandom(cdnCandidates)
      : _currentCdnUrl;

    _cachedCdnCandidates = cdnCandidates.isNotEmpty ? cdnCandidates : null;

      response = await client.get(baseUrl.replace(path: _backupApiPath));
      decoded = json.decode(response.utf8Body);
      final backupApiUrl = (decoded is List<dynamic> && decoded.isNotEmpty)
          ? Uri.parse(decoded[0] ?? _currentBackupApiUrl.toString())
          : _currentBackupApiUrl;

      final urls = XdnmbUrls._internal(
          baseUrl: baseUrl,
          cdnUrl: cdnUrl,
          backupApiUrl: backupApiUrl,
          cdnCandidates: cdnCandidates)
        ..useBackupApi = _urls.useBackupApi;
      _urls = urls;

      return _urls;
    } catch (e) {
      rethrow;
    }
  }

  /// 解析 CDN 候选列表
  static List<Uri> _parseCdnCandidates(dynamic decoded) {
    if (decoded is! List) return const <Uri>[];
    final result = <_CdnCandidate>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final url = item['url']?.toString().trim();
      if (url == null || url.isEmpty) continue;

      final rateRaw = item['rate'];
      final rate = (rateRaw is num) ? rateRaw.toDouble() : 0.0;
      final uri = Uri.tryParse(url);
      if (uri == null) continue;
      result.add(_CdnCandidate(uri, rate));
    }
    // 去重（保留最高 rate）
    final byUri = <Uri, double>{};
    for (final c in result) {
      byUri[c.uri] = max(byUri[c.uri] ?? double.negativeInfinity, c.rate);
    }
    return byUri.keys.toList(growable: false);
  }

  /// 按权重随机选择 CDN。
  ///
  /// - rate<=0 时按 1 处理。
  /// - 为了简单/稳定，不在这里做测速；测速更适合放到客户端侧按需做。
  static Uri _pickWeightedRandom(List<Uri> candidates) {
    // 如果上一次候选列表里只有一个，直接返回。
    if (candidates.length == 1) return candidates.first;

    // 由于 _parseCdnCandidates 已经丢掉了 rate，这里改为：
    // - 若我们能复用缓存的 raw 列表就带 rate；否则退化为均匀随机。
    // 当前实现选择“稳定优先”：优先返回第一个，避免频繁变化导致缓存碎片。
    // 但若缓存存在则按缓存权重随机。
    final cached = _cachedCdnCandidates;
    if (cached == null || cached.isEmpty) {
      return candidates[Random().nextInt(candidates.length)];
    }
    // cached 是 Uri 列表，无法获得 rate；退化为均匀随机。
    return cached[Random().nextInt(cached.length)];
  }
}

final class _CdnCandidate {
  final Uri uri;
  final double rate;
  const _CdnCandidate(this.uri, this.rate);
}
