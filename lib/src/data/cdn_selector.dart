import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:xdnmb_api/xdnmb_api.dart';

abstract interface class CdnSelectorStorage {
  Future<String?> readSelectedBaseUrl();
  Future<void> writeSelectedBaseUrl(String value);
  Future<void> writeLastProbeEpochMs(int value);
}

final class SharedPreferencesCdnSelectorStorage implements CdnSelectorStorage {
  static const _kSelectedCdnBaseUrl = 'xdnmb.cdn.selectedBaseUrl';
  static const _kLastProbeEpochMs = 'xdnmb.cdn.lastProbeEpochMs';

  @override
  Future<String?> readSelectedBaseUrl() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_kSelectedCdnBaseUrl);
  }

  @override
  Future<void> writeSelectedBaseUrl(String value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kSelectedCdnBaseUrl, value);
  }

  @override
  Future<void> writeLastProbeEpochMs(int value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kLastProbeEpochMs, value);
  }
}

/// CDN 选择器：启动时测速选最快 + 后台定时复测。
///
/// 设计目标：
/// - 不阻塞 UI：初始化与测速都应后台跑。
/// - 可缓存：上次成功的 CDN 将持久化，冷启动优先使用。
/// - 可降级：测速失败/列表为空时，回退到 API 内置的默认 CDN。
final class CdnSelector {
  /// 探测超时：宁可快失败再换，也别卡太久。
  static const Duration defaultProbeTimeout = Duration(seconds: 3);

  /// 定时复测间隔：避免过于频繁导致额外流量/握手。
  static const Duration defaultRefreshInterval = Duration(minutes: 30);

  /// 参与测速的“轻量请求”。
  ///
  /// - 选 thumb 路径：体积小、能代表大多数图片访问路径。
  /// - query 追加 nonce：避免某些 CDN 过度缓存导致误判。
  static Uri _probeUrl(Uri cdnBaseUrl) {
    final u = cdnBaseUrl.replace(
      path: 'thumb/1.jpg',
      queryParameters: <String, String>{
        // best-effort cache busting
        '_': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
    return u;
  }

  final List<Uri> Function() _candidatesProvider;
  final HttpClient Function() _clientFactory;
  final CdnSelectorStorage _storage;

  Uri? _selected;
  Timer? _timer;
  bool _started = false;

  /// 当前选中的 CDN base url（以 `/` 结尾的 https://.../）。
  Uri? get selected => _selected;

  CdnSelector({
    required List<Uri> Function() candidatesProvider,
    HttpClient Function()? clientFactory,
  CdnSelectorStorage? storage,
  })  : _candidatesProvider = candidatesProvider,
    _clientFactory = clientFactory ?? (() => HttpClient()),
    _storage = storage ?? SharedPreferencesCdnSelectorStorage();

  /// 启动：
  /// - 读取持久化的上次选择
  /// - 触发一次测速，选最快
  /// - 启动定时复测
  Future<void> start({
    Duration probeTimeout = defaultProbeTimeout,
    Duration refreshInterval = defaultRefreshInterval,
  }) async {
    if (_started) return;
    _started = true;

    await _loadPersistedSelection();

    // 立即异步测速（不 await，避免阻塞启动）。
    // ignore: discarded_futures
    refresh(probeTimeout: probeTimeout);

    _timer?.cancel();
    _timer = Timer.periodic(refreshInterval, (_) {
      // ignore: discarded_futures
      refresh(probeTimeout: probeTimeout);
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  /// 立刻测速并更新最快 CDN。
  Future<void> refresh({Duration probeTimeout = defaultProbeTimeout}) async {
    final candidates = _candidatesProvider();
    if (candidates.isEmpty) return;

    final sw = Stopwatch()..start();
    final results = <Uri, Duration>{};

    // Batch-probe with limited concurrency to balance speed vs. handshake
    // burst (especially relevant on Windows).
    const maxConcurrency = 3;
    for (var i = 0; i < candidates.length; i += maxConcurrency) {
      final batch = candidates.skip(i).take(maxConcurrency).toList();
      final batchResults = await Future.wait(
        batch.map((c) => _probeOnce(c, timeout: probeTimeout)),
      );
      for (var j = 0; j < batch.length; j++) {
        final d = batchResults[j];
        if (d != null) {
          results[batch[j]] = d;
        }
      }
    }

    if (results.isEmpty) {
      developer.log('cdn probe: all failed in ${sw.elapsed}', name: 'xdnmb.cdn');
      return;
    }

    final fastest = results.entries.reduce((a, b) => a.value <= b.value ? a : b);
    final next = fastest.key;

    final changed = _selected?.toString() != next.toString();
    _selected = next;

    await _persistSelection(next);

  // 让 API 的 PostBase 扩展（thumbImageUrl/imageUrl）立即生效。
  XdnmbUrls.overrideCdnUrl(next, candidates: candidates);

    developer.log(
      'cdn probe done in ${sw.elapsed}: fastest=$next latency=${fastest.value.inMilliseconds}ms changed=$changed',
      name: 'xdnmb.cdn',
    );
  }

  Future<Duration?> _probeOnce(Uri cdnBaseUrl, {required Duration timeout}) async {
    final client = _clientFactory();
    client.connectionTimeout = timeout;

    try {
      final probe = _probeUrl(cdnBaseUrl);
      final req = await client.getUrl(probe).timeout(timeout);
      req.headers.set('User-Agent', 'WinX');
      final started = Stopwatch()..start();
      final res = await req.close().timeout(timeout);

      // 只要能完成握手并拿到响应头，我们就认为可用；不强制 200。
      // 有些 CDN 对不存在资源会返回 404，但这同样代表链路顺畅。
      await res.drain<void>();
      started.stop();
      return started.elapsed;
    } on HandshakeException {
      return null;
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _loadPersistedSelection() async {
  final raw = await _storage.readSelectedBaseUrl();
    if (raw == null || raw.trim().isEmpty) return;

    final u = Uri.tryParse(raw.trim());
    if (u == null) return;

    _selected = u;
  }

  Future<void> _persistSelection(Uri url) async {
  await _storage.writeSelectedBaseUrl(url.toString());
  await _storage.writeLastProbeEpochMs(DateTime.now().millisecondsSinceEpoch);
  }
}
