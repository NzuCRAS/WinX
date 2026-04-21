import 'database_helper.dart';
import 'perf_log.dart';

final class HistoryEntry {
  final int threadId;
  final String? title;
  final String? userHash;
  final bool? isAdmin;
  final DateTime? postTime;
  final int? replyCount;
  final String? thumbImageUrl;
  final String? content;
  final DateTime visitedAt;

  const HistoryEntry({
    required this.threadId,
    this.title,
    this.userHash,
    this.isAdmin,
    this.postTime,
    this.replyCount,
    this.thumbImageUrl,
    this.content,
    required this.visitedAt,
  });

  Map<String, Object?> toJson() => {
        'threadId': threadId,
        'title': title,
        'userHash': userHash,
        'isAdmin': isAdmin,
        'postTime': postTime?.toIso8601String(),
        'replyCount': replyCount,
        'thumbImageUrl': thumbImageUrl,
        'content': content,
        'visitedAt': visitedAt.toIso8601String(),
      };

  static HistoryEntry? fromJson(Map<String, Object?> json) {
    final id = json['threadId'];
    if (id is! int) return null;
    final at = DateTime.tryParse((json['visitedAt'] as String?) ?? '');
    final postTime = DateTime.tryParse((json['postTime'] as String?) ?? '');
    final replyCount = json['replyCount'];
    return HistoryEntry(
      threadId: id,
      title: json['title'] as String?,
      userHash: json['userHash'] as String?,
      isAdmin: json['isAdmin'] as bool?,
      postTime: postTime,
      replyCount: replyCount is int ? replyCount : null,
      thumbImageUrl: json['thumbImageUrl'] as String?,
      content: json['content'] as String?,
      visitedAt: at ?? DateTime.now(),
    );
  }
}

final class HistoryStore {
  HistoryStore({DatabaseHelper? db}) : _db = db ?? DatabaseHelper();

  final DatabaseHelper _db;

  Future<List<HistoryEntry>> readAll() async {
  return PerfLog.time('history.readAll', _db.getAllHistory);
  }

  Future<void> recordVisit({
    required int threadId,
    String? title,
    String? userHash,
    bool? isAdmin,
    DateTime? postTime,
    int? replyCount,
    String? thumbImageUrl,
    String? content,
  }) async {
    await PerfLog.time(
      'history.recordVisit',
      () => _db.insertHistory(
        HistoryEntry(
          threadId: threadId,
          title: title,
          userHash: userHash,
          isAdmin: isAdmin,
          postTime: postTime,
          replyCount: replyCount,
          thumbImageUrl: thumbImageUrl,
          content: content,
          visitedAt: DateTime.now(),
        ),
      ),
    );
  }

  Future<void> remove(int threadId) async {
  await PerfLog.time('history.remove', () => _db.deleteHistory(threadId));
  }

  Future<void> clear() async {
  await PerfLog.time('history.clear', _db.clearHistory);
  }
}
