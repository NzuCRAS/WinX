import 'database_helper.dart';

final class ThreadProgress {
  final int threadId;
  final int page;
  final double offset;
  final DateTime updatedAt;

  const ThreadProgress({
    required this.threadId,
    required this.page,
    required this.offset,
    required this.updatedAt,
  });
}

final class ThreadProgressStore {
  ThreadProgressStore({DatabaseHelper? db}) : _db = db ?? DatabaseHelper();

  final DatabaseHelper _db;

  Future<ThreadProgress?> read(int threadId) async {
    final v = await _db.getThreadProgress(threadId);
    if (v == null) return null;
    return ThreadProgress(
      threadId: threadId,
      page: v.page,
      offset: v.offset,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> write({
    required int threadId,
    required int page,
    required double offset,
  }) async {
    await _db.upsertThreadProgress(
      threadId: threadId,
      page: page,
      offset: offset,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> clear(int threadId) => _db.deleteThreadProgress(threadId);
}
