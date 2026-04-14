import 'dart:convert';
import 'dart:io';

import 'package:xdnmb_api/xdnmb_api.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  // Usage:
  //   dart run tool/debug_feed.dart <uuid> [page]
  // Optional env:
  //   XdnmbUserHash=...  (if the feed needs cookie)

  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/debug_feed.dart <uuid> [page]');
    exitCode = 64;
    return;
  }

  final uuid = args[0];
  final page = args.length >= 2 ? int.tryParse(args[1]) ?? 1 : 1;

  final userHash = Platform.environment['XdnmbUserHash'];
  final api = XdnmbApi(userHash: userHash);
  if (userHash != null && userHash.trim().isNotEmpty) {
    api.xdnmbCookie = XdnmbCookie(userHash);
  }

  try {
    // 1) Raw JSON probe (bypass model parsing) to verify server payload.
    final rawUrl = XdnmbUrls().feed(uuid, page: page);
    final rawResp = await http.get(rawUrl);
    stdout.writeln('rawUrl=$rawUrl status=${rawResp.statusCode}');
    if (rawResp.statusCode == 200) {
      final body = utf8.decode(rawResp.bodyBytes);

      dynamic decoded;
      try {
        decoded = json.decode(body);
      } catch (e) {
        stdout.writeln('raw json decode failed: $e');
        decoded = null;
      }

      if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        final first = decoded.first as Map;
        stdout.writeln('rawKeys(first)=${first.keys.toList()}');
        dynamic readKey(String k) => first[k];
        stdout.writeln('rawFirst.id=${readKey('id')}');
        stdout.writeln('rawFirst.reply_count=${readKey('reply_count')}');
        stdout.writeln('rawFirst.recent_replies=${readKey('recent_replies')}');
      } else {
        stdout.writeln('rawDecodedType=${decoded.runtimeType} bodyPrefix=${body.substring(0, body.length < 200 ? body.length : 200)}');
      }
    }

    stdout.writeln('--- parsed model ---');
    final feeds = await api.getFeed(uuid, page: page);
    if (feeds.isEmpty) {
      stdout.writeln('feed is empty');
      return;
    }

    stdout.writeln('count=${feeds.length}');
    for (final f in feeds.take(5)) {
      stdout.writeln(jsonEncode({
        'id': f.id,
        'fid': f.forumId,
        'replyCount': f.replyCount,
        'recentRepliesLen': f.recentReplies.length,
        'title': f.title,
      }));
    }
  } catch (e, st) {
    stderr.writeln('error: $e');
    stderr.writeln(st);
    exitCode = 1;
  }
}
