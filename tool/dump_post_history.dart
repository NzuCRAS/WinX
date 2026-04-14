import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dump local post history stored in SharedPreferences.
///
/// NOTE:
/// This file cannot be executed with plain `dart run` (and usually also not with
/// `flutter pub run`) because `shared_preferences` requires a Flutter engine
/// (dart:ui). In CLI mode you'll see:
///   "Dart library 'dart:ui' is not available on this platform."
///
/// Preferred alternative:
/// - Use an in-app debug action/page to export this key.
Future<void> main() async {
  final sp = await SharedPreferences.getInstance();
  const key = 'xdnmb.history.posts';
  final raw = sp.getString(key);

  if (raw == null) {
    if (kDebugMode) debugPrint('[$key] <null>');
    return;
  }

  if (kDebugMode) debugPrint('[$key] raw.length=${raw.length}');

  dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (e) {
  if (kDebugMode) debugPrint('jsonDecode failed: $e');
    return;
  }

  if (decoded is! List) {
  if (kDebugMode) debugPrint('decoded is not List: ${decoded.runtimeType}');
    return;
  }

  var replies = 0;
  var threads = 0;
  var nullMainPostId = 0;
  var nullForumId = 0;
  var nullReplyPostId = 0;

  for (final e in decoded) {
    if (e is! Map) continue;
    final m = e.map((k, v) => MapEntry(k.toString(), v));
    final isReply = m['isReply'] == true;
    if (isReply) {
      replies++;
    } else {
      threads++;
    }
    if (m['mainPostId'] == null) nullMainPostId++;
    if (m['forumId'] == null) nullForumId++;
    if (isReply && m['replyPostId'] == null) nullReplyPostId++;
  }

  if (kDebugMode) {
    debugPrint('total=${decoded.length} threads=$threads replies=$replies');
    debugPrint('null mainPostId=$nullMainPostId null forumId=$nullForumId');
    debugPrint('replies with null replyPostId=$nullReplyPostId');
  }

  // Print last 10 entries summary (most recent should be at front).
  final n = decoded.length < 10 ? decoded.length : 10;
  if (kDebugMode) debugPrint('--- first $n entries ---');
  for (var i = 0; i < n; i++) {
    final e = decoded[i];
    if (e is! Map) continue;
    final m = e.map((k, v) => MapEntry(k.toString(), v));
    final isReply = m['isReply'] == true;
    if (kDebugMode) {
      debugPrint(
        '#$i ${isReply ? 'reply' : 'thread'} mainPostId=${m['mainPostId']} replyPostId=${m['replyPostId']} forumId=${m['forumId']} postedAt=${m['postedAt']}',
      );
    }
  }
}
