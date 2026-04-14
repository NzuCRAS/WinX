import 'database_helper.dart';

/// Local post history (what the user has posted).
///
/// This is best-effort and only records successful submissions.
final class PostHistoryEntry {
  /// SQLite row id.
  ///
  /// Null for new entries before inserted.
  final int? id;

  /// The thread id this entry belongs to.
  ///
  /// - For replies: the replied thread id.
  /// - For new threads: the newly created thread id (resolved best-effort).
  final int? mainPostId;

  /// For replies: the newly created reply post id (best-effort).
  ///
  /// This enables "tap to jump to reply" in history UI.
  final int? replyPostId;
  final int? forumId;
  final bool isReply;
  final String? title;
  final String content;
  final DateTime postedAt;

  // Cached thread-head meta for list rendering (方案B).
  final String? threadUserHash;
  final bool? threadIsAdmin;
  final DateTime? threadPostTime;
  final int? threadReplyCount;
  final String? threadThumbImageUrl;
  final String? threadContent;

  const PostHistoryEntry({
  this.id,
    required this.isReply,
    required this.content,
    required this.postedAt,
    this.mainPostId,
  this.replyPostId,
    this.forumId,
    this.title,
  this.threadUserHash,
  this.threadIsAdmin,
  this.threadPostTime,
  this.threadReplyCount,
  this.threadThumbImageUrl,
  this.threadContent,
  });
}

final class PostHistoryStore {
  final DatabaseHelper _db;

  PostHistoryStore({DatabaseHelper? db}) : _db = db ?? DatabaseHelper();

  Future<List<PostHistoryEntry>> readAll() async {
  return _db.getAllPostHistory();
  }

  Future<void> record(PostHistoryEntry entry) async {
  await _db.insertPostHistory(entry);
  // Keep bounded; DatabaseHelper already caps to 500.
  }

  Future<void> removeAt(int index) async {
  final all = await readAll();
  if (index < 0 || index >= all.length) return;
  final id = all[index].id;
  if (id == null) return;
  await _db.deletePostHistory(id);
  }

  Future<void> clear() async {
  await _db.clearPostHistory();
  }

  /// Debug helper: dumps raw size and basic stats to a single string.
  ///
  /// This must be executed inside a running Flutter application.
  Future<String> debugDump({int sampleCount = 20}) async {
    final all = await readAll();
    final b = StringBuffer();
    b.writeln('[PostHistoryStore] backend=sqlite');
    b.writeln('total=${all.length}');

    var replies = 0;
    var threads = 0;
    var nullMainPostId = 0;
    var nullForumId = 0;
    var nullReplyPostId = 0;
    for (final e in all) {
      if (e.isReply) {
        replies++;
      } else {
        threads++;
      }
      if (e.mainPostId == null) nullMainPostId++;
      if (e.forumId == null) nullForumId++;
      if (e.isReply && e.replyPostId == null) nullReplyPostId++;
    }
    b.writeln('threads=$threads replies=$replies');
    b.writeln('null mainPostId=$nullMainPostId null forumId=$nullForumId');
    b.writeln('replies with null replyPostId=$nullReplyPostId');

    final n = all.length < sampleCount ? all.length : sampleCount;
    b.writeln('--- first $n entries ---');
    for (var i = 0; i < n; i++) {
      final e = all[i];
      b.writeln(
        '#$i ${e.isReply ? 'reply' : 'thread'} id=${e.id} mainPostId=${e.mainPostId} replyPostId=${e.replyPostId} forumId=${e.forumId} postedAt=${e.postedAt.toIso8601String()}',
      );
    }

    return b.toString();
  }
}
