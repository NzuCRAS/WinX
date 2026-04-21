import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xdnmb_api/xdnmb_api.dart';

import 'package:xdnmb_client/src/data/cdn_selector.dart';

final class _MemStorage implements CdnSelectorStorage {
  String? selected;
  int? lastProbe;

  @override
  Future<String?> readSelectedBaseUrl() async => selected;

  @override
  Future<void> writeLastProbeEpochMs(int value) async {
    lastProbe = value;
  }

  @override
  Future<void> writeSelectedBaseUrl(String value) async {
    selected = value;
  }
}

final class _FakeHttpClient implements HttpClient {
  final Map<String, Duration> latencyByHost;
  final Set<String> failHosts;

  _FakeHttpClient({required this.latencyByHost, required this.failHosts});

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return _FakeRequest(
      host: url.host,
      latencyByHost: latencyByHost,
      failHosts: failHosts,
    );
  }

  @override
  void close({bool force = false}) {}

  // ---- Unused members (minimal stub) ----
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeRequest implements HttpClientRequest {
  final String host;
  final Map<String, Duration> latencyByHost;
  final Set<String> failHosts;

  _FakeRequest({
    required this.host,
    required this.latencyByHost,
    required this.failHosts,
  });

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  Future<HttpClientResponse> close() async {
    if (failHosts.contains(host)) {
      throw const HandshakeException('fake handshake');
    }
    final latency = latencyByHost[host] ?? Duration.zero;
    // Simulate response latency inside close() so _probeOnce's Stopwatch
    // captures it.
    await Future<void>.delayed(latency);
    return _FakeResponse();
  }

  // ---- Unused members ----
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  int get statusCode => 404;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    // empty body
    return const Stream<List<int>>.empty().listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  // ---- Unused members ----
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  // ---- Unused members ----
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CdnSelector picks the fastest candidate and overrides XdnmbUrls',
      () async {
    final a = Uri.parse('https://a.example/');
    final b = Uri.parse('https://b.example/');

    final selector = CdnSelector(
      candidatesProvider: () => [a, b],
      clientFactory: () => _FakeHttpClient(
        latencyByHost: {
          'a.example': const Duration(milliseconds: 50),
          'b.example': const Duration(milliseconds: 5),
        },
        failHosts: {},
      ),
  storage: _MemStorage(),
    );

    await selector.refresh(probeTimeout: const Duration(seconds: 1));

    expect(selector.selected?.host, equals('b.example'));
    expect(XdnmbUrls().cdnUrl.host, equals('b.example'));
  });

  test('CdnSelector ignores failed hosts and still selects a working one',
      () async {
    final a = Uri.parse('https://a.example/');
    final b = Uri.parse('https://b.example/');

    final selector = CdnSelector(
      candidatesProvider: () => [a, b],
      clientFactory: () => _FakeHttpClient(
        latencyByHost: {
          'b.example': const Duration(milliseconds: 1),
        },
        failHosts: {'a.example'},
      ),
  storage: _MemStorage(),
    );

    await selector.refresh(probeTimeout: const Duration(seconds: 1));

    expect(selector.selected?.host, equals('b.example'));
  });
}
