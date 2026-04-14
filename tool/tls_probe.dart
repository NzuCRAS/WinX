import 'dart:convert';
import 'dart:io';

Future<void> _probe(Uri u) async {
  final c = HttpClient();
  c.connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await c.getUrl(u);
    req.headers.set('User-Agent', 'xdnmb_client_probe');
    final res = await req.close();
    final body = await utf8.decodeStream(res);
    stdout.writeln('OK $u -> ${res.statusCode}, len=${body.length}');
  } catch (e, st) {
    stderr.writeln('FAIL $u -> $e');
    stderr.writeln(st);
  } finally {
    c.close(force: true);
  }
}

Future<void> main() async {
  final urls = <Uri>[
    Uri.parse('https://api.nmb.best/api/getTimelineList'),
    Uri.parse('https://www.nmbxd1.com/'),
    Uri.parse('https://image.nmb.best/'),
  ];

  for (final u in urls) {
    await _probe(u);
  }
}
