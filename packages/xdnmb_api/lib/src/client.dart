import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' hide Client;
import 'package:http/io_client.dart';
import 'package:http_parser/http_parser.dart';

import 'urls.dart';
import 'xdnmb.dart';

/// 将 cookie 列表转化为 cookie 值
String _toCookies(Iterable<String> cookies) => cookies.join('; ');

/// Sanitize a cookie/header value to be safe for HTTP headers.
///
/// Dart's `HttpClient` is strict: header field values cannot contain control
/// characters (including `\r`/`\n`). Some userhash strings imported from QR
/// codes may contain such characters on Windows (e.g. copy artifacts).
///
/// This function:
/// - removes ASCII control chars (0x00-0x1F, 0x7F)
/// - DOES NOT drop non-ASCII bytes (userhash is arbitrary bytes stored as latin1)
/// - DOES NOT normalize whitespace (would mutate bytes)
String sanitizeHeaderValue(String input) {
  final runes = input.runes.where((c) {
  // Disallow all ASCII control chars (including CR/LF) and DEL.
  // Keep 0x80-0xFF as-is (latin1 bytes).
  if ((c >= 0x00 && c <= 0x1f) || c == 0x7f) return false;
  return true;
  });
  return String.fromCharCodes(runes);
}

/// Encode the userhash value to be safe inside a Cookie header.
///
/// X 岛的 userhash 本质上是一段“任意字节序列”，常见来源：
/// - 二维码里 `cookie` 字段：以 `%CD%02...` 的形式对原始 bytes 做 percent-encoding
/// - 客户端存储：我们用 latin1 字符串无损表示 bytes（0-255）
///
/// 关键点：不能用 `Uri.encodeComponent(value)` 直接对 Dart 字符串做 UTF-8 编码，
/// 否则如果 value 是“latin1 映射的 bytes”，会发生二次编码（典型特征：`%C3%8D...`）。
///
/// 这里我们明确把字符串按 latin1 取回原始 bytes，再对每个 byte做 `%XX`。
String encodeCookieValue(String value) {
  late final List<int> bytes;
  try {
    bytes = latin1.encode(value);
  } catch (_) {
    // Fallback: best-effort map runes to 0-255.
    bytes = value.runes.map((r) => r & 0xff).toList(growable: false);
  }
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write('%');
    sb.write(b.toRadixString(16).toUpperCase().padLeft(2, '0'));
  }
  return sb.toString();
}

String _hexByte(int b) => b.toRadixString(16).toUpperCase().padLeft(2, '0');

String _sha256PrefixHex(List<int> bytes, {int prefixBytes = 8}) {
  final d = sha256.convert(bytes).bytes;
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
  // Heuristic: if cookie contains lots of %xx blocks, it's likely already encoded.
  final seems = triples >= 8;
  return (seemsPercentEncoded: seems, percentTriples: triples, length: s.length);
}

/// Test-only helper to validate our percent shape heuristics.
///
/// Not part of the public API surface.
({bool seemsPercentEncoded, int percentTriples, int length}) testOnlyPercentShape(
    String s) =>
  _percentShape(s);

void _debugCookieFingerprint(Uri url, String? cookie) {
  const enabled = bool.fromEnvironment('XDNMB_DEBUG_AUTH', defaultValue: false);
  if (!enabled || cookie == null || cookie.isEmpty) return;
  // We only log a digest of raw bytes; never log the cookie itself.
  List<int> bytes;
  try {
    bytes = latin1.encode(cookie);
  } catch (_) {
    bytes = cookie.runes.map((r) => r & 0xff).toList(growable: false);
  }
  final shape = _percentShape(cookie);
  developer.log(
    'cookieFp url=${url.host}${url.path} sha256Prefix=${_sha256PrefixHex(bytes)} len=${shape.length} percentTriples=${shape.percentTriples} seemsPercentEncoded=${shape.seemsPercentEncoded}',
    name: 'xdnmb.auth',
  );
}

/// [Response] 的扩展
extension ResponseExtension on Response {
  /// 返回 utf8 编码的 [body]，不用 [body] 是因为 X 岛返回的 header 可能不包含编码信息，
  /// 这样解码会出错
  String get utf8Body => utf8.decode(bodyBytes);
}

/// HTTP 状态异常
class HttpStatusException implements Exception {
  /// 状态码
  final int statusCode;

  /// 构造 [HttpStatusException]
  const HttpStatusException(this.statusCode);

  @override
  String toString() =>
      "HttpStatusException: the HTTP response's status code is $statusCode";

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HttpStatusException && statusCode == other.statusCode);

  @override
  int get hashCode => statusCode.hashCode;
}

/// multipart 的实现
class Multipart extends MultipartRequest {
  /// 构造 [Multipart]
  ///
  /// [url] 为请求链接
  Multipart(Uri url) : super('POST', url);

  /// 添加字段，值为 [value] 的字符串表达
  void add(String field, Object value) => fields[field] = value.toString();

  /// 添加字段
  void addBytes(String field, List<int> value,
          {String? filename, String? contentType}) =>
      files.add(
        MultipartFile.fromBytes(
          field,
          value,
          filename: filename,
          contentType:
              contentType != null ? MediaType.parse(contentType) : null,
        ),
      );
}

/// HTTP client 的实现
class Client extends IOClient {
  /// 默认连接超时时长
  static const Duration defaultConnectionTimeout = Duration(seconds: 15);

  /// 默认连接空闲超时时长
  static const Duration _defaultIdleTimeout = Duration(seconds: 90);

  /// 默认`User-Agent`
  static const String _defaultUserAgent = 'xdnmb';

  /// X 岛的 PHP session ID
  String? xdnmbPhpSessionId;

  /// X 岛备用 API 的 PHP session ID
  String? _xdnmbBackupApiPhpSessionId;

  /// 最大重试次数
  static const int maxRetryCount = 3;
  
  /// 重试间隔基数（毫秒）
  static const int retryDelayBase = 500;

  /// 构造 [Client]
  ///
  /// [client] 为 [HttpClient]
  ///
  /// [connectionTimeout] 为连接超时时长，默认为 15 秒
  ///
  /// [idleTimeout] 为连接空闲超时时长，默认为 90 秒
  Client(
      {HttpClient? client,
      Duration? connectionTimeout,
      Duration? idleTimeout,
      String? userAgent})
      : super((client ?? _createHttpClient())
          ..connectionTimeout = connectionTimeout ?? defaultConnectionTimeout
          ..idleTimeout = idleTimeout ?? _defaultIdleTimeout
          ..userAgent = userAgent ?? _defaultUserAgent);
  
  /// 创建优化的 HttpClient
  static HttpClient _createHttpClient() {
    final client = HttpClient();
    // 优化 TLS 握手
    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      // 仅在开发环境允许自签名证书
      return const bool.fromEnvironment('XDNMB_DEBUG', defaultValue: false);
    };
    return client;
  }
  
  /// 带重试的网络请求
  Future<T> _withRetry<T>(Future<T> Function() request) async {
    int attempts = 0;
    while (true) {
      try {
        attempts++;
        return await request();
      } catch (e) {
        if (attempts >= maxRetryCount) {
          rethrow;
        }
        
        // 只对网络相关错误进行重试
        if (e is SocketException || 
            e is HandshakeException || 
            e is HttpStatusException) {
          // 指数退避策略
          final delay = Duration(milliseconds: retryDelayBase * pow(2, attempts - 1).toInt());
          developer.log('网络请求失败，$delay 后重试 ($attempts/$maxRetryCount): $e', name: 'xdnmb.network');
          await Future.delayed(delay);
        } else {
          rethrow;
        }
      }
    }
  }

  /// [xdnmbPhpSessionId] 有效
  bool _xdnmbPhpSessionIdIsValid(Uri url) =>
      xdnmbPhpSessionId != null && XdnmbUrls().isBaseUrl(url);

  /// [_xdnmbBackupApiPhpSessionId] 有效
  bool _xdnmbBackupApiPhpSessionIdIsValid(Uri url) =>
      _xdnmbBackupApiPhpSessionId != null && XdnmbUrls().isBackupApiUrl(url);

  /// 返回 cookie 头
  Map<String, String>? _cookieHeasers(Uri url, String? cookie) {
  final enabled =
    const bool.fromEnvironment('XDNMB_DEBUG_AUTH', defaultValue: false);
    final should = cookie != null ||
        _xdnmbPhpSessionIdIsValid(url) ||
        _xdnmbBackupApiPhpSessionIdIsValid(url);
    if (!should) return null;

  _debugCookieFingerprint(url, cookie);

    final headerValue = _toCookies([
      if (cookie != null) sanitizeHeaderValue(cookie),
      if (_xdnmbPhpSessionIdIsValid(url)) sanitizeHeaderValue(xdnmbPhpSessionId!),
      if (_xdnmbBackupApiPhpSessionIdIsValid(url))
        sanitizeHeaderValue(_xdnmbBackupApiPhpSessionId!),
    ]);

    if (enabled) {
      // Avoid logging full cookie; only indicate presence and lengths.
      final hasUserhash = headerValue.contains('userhash=');
      final hasSess = headerValue.contains('PHPSESSID=');
      developer.log(
        'cookieHeader url=${url.host}${url.path} hasUserhash=$hasUserhash hasPHPSESSID=$hasSess len=${headerValue.length}',
        name: 'xdnmb.auth',
      );
    }
    return {HttpHeaders.cookieHeader: headerValue};
  }

  /// GET 请求
  Future<Response> xGet(Uri url, [String? cookie]) async {
    return _withRetry(() async {
      final response = await this.get(url, headers: _cookieHeasers(url, cookie));
      _checkStatusCode(response);
      return response;
    });
  }

  /// POST form 请求
  Future<Response> xPostForm(Uri url, Map<String, String>? form,
      [String? cookie]) async {
    return _withRetry(() async {
      final response = await this.post(url, headers: _cookieHeasers(url, cookie), body: form);
      _checkStatusCode(response);
      return response;
    });
  }

  /// POST multipart 请求
  Future<Response> xPostMultipart(Multipart multipart, [String? cookie]) async {
    return _withRetry(() async {
      if (cookie != null ||
          _xdnmbPhpSessionIdIsValid(multipart.url) ||
          _xdnmbBackupApiPhpSessionIdIsValid(multipart.url)) {
        multipart.headers[HttpHeaders.cookieHeader] = _toCookies([
          if (cookie != null) sanitizeHeaderValue(cookie),
          if (_xdnmbPhpSessionIdIsValid(multipart.url))
            sanitizeHeaderValue(xdnmbPhpSessionId!),
          if (_xdnmbBackupApiPhpSessionIdIsValid(multipart.url))
            sanitizeHeaderValue(_xdnmbBackupApiPhpSessionId!),
        ]);
      }
      final streamedResponse = await send(multipart);
      final response = await Response.fromStream(streamedResponse);
      _checkStatusCode(response);
      return response;
    });
  }

  @override
  Future<IOStreamedResponse> send(BaseRequest request) async {
    final response = await super.send(request);

    // 获取 xdnmbPhpSessionId 和_xdnmbBackupApiPhpSessionId
    final setCookie = response.headers[HttpHeaders.setCookieHeader];
    if (setCookie != null) {
      final cookies = setCookie.split(RegExp(r',(?! )'));
      for (final c in cookies) {
        try {
          final cookie = Cookie.fromSetCookieValue(c);
          if (cookie.name == 'PHPSESSID') {
            final urls = XdnmbUrls();
            if (urls.isBaseUrl(request.url)) {
              xdnmbPhpSessionId = cookie.toCookie;
            } else if (urls.isBackupApiUrl(request.url)) {
              _xdnmbBackupApiPhpSessionId = cookie.toCookie;
            }
          }
        } catch (e) {
          print('解析 set-cookie 出现错误：$e');
        }
      }
    }

    return response;
  }
}

/// 检查 HTTP 状态码
void _checkStatusCode(Response response) {
  if (response.statusCode != HttpStatus.ok) {
    throw HttpStatusException(response.statusCode);
  }
}
