import 'dart:convert';

/// Unified cursor model for thread reading progress.
///
/// Design goals:
/// - Fast restore path: only need a postId anchor (and an index hint) so we can
///   jump as soon as page 1 is loaded.
/// - Stable across entry points: same thread cursor used by forum list /
///   subscription / history, unless it's a reply-jump.
/// - Reply-jump has its own cursor key space (threadId + page + reply index)
///   to avoid polluting the main thread cursor.
sealed class ThreadCursor {
  const ThreadCursor();

  Map<String, Object?> toJson();

  String toJsonString() => jsonEncode(toJson());
}

/// Cursor for normal thread browsing (single cursor per thread head id).
final class ThreadMainCursor extends ThreadCursor {
  final int threadId; // mainPostId
  final int anchorPostId;
  final int? topIndexHint;
  /// 1-based page where the anchor post lives. Helps deep-jump without probing.
  final int? page;

  const ThreadMainCursor({
    required this.threadId,
    required this.anchorPostId,
    this.topIndexHint,
    this.page,
  });

  @override
  Map<String, Object?> toJson() => {
        'type': 'main',
        'threadId': threadId,
        'anchorPostId': anchorPostId,
        'topIndexHint': topIndexHint,
        'page': page,
      };

  static ThreadMainCursor? tryParseJsonString(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      if (m['type']?.toString() != 'main') return null;
      final threadId = int.tryParse(m['threadId']?.toString() ?? '');
      final anchorPostId = int.tryParse(m['anchorPostId']?.toString() ?? '');
      final topIndexHint = int.tryParse(m['topIndexHint']?.toString() ?? '');
      final page = int.tryParse(m['page']?.toString() ?? '');
      if (threadId == null || anchorPostId == null) return null;
      return ThreadMainCursor(
        threadId: threadId,
        anchorPostId: anchorPostId,
        topIndexHint: topIndexHint,
        page: page,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Cursor for reply-jump browsing.
///
/// Keyed by (threadId + page + replyIndexInPage), and stores the reply postId
/// to anchor.
final class ThreadReplyCursor extends ThreadCursor {
  final int threadId;
  final int page;
  final int replyIndexInPage;
  final int anchorPostId;

  const ThreadReplyCursor({
    required this.threadId,
    required this.page,
    required this.replyIndexInPage,
    required this.anchorPostId,
  });

  @override
  Map<String, Object?> toJson() => {
        'type': 'reply',
        'threadId': threadId,
        'page': page,
        'replyIndexInPage': replyIndexInPage,
        'anchorPostId': anchorPostId,
      };

  static ThreadReplyCursor? tryParseJsonString(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      if (m['type']?.toString() != 'reply') return null;
      final threadId = int.tryParse(m['threadId']?.toString() ?? '');
      final page = int.tryParse(m['page']?.toString() ?? '');
      final replyIndexInPage =
          int.tryParse(m['replyIndexInPage']?.toString() ?? '');
      final anchorPostId = int.tryParse(m['anchorPostId']?.toString() ?? '');
      if (threadId == null || page == null || replyIndexInPage == null || anchorPostId == null) {
        return null;
      }
      return ThreadReplyCursor(
        threadId: threadId,
        page: page,
        replyIndexInPage: replyIndexInPage,
        anchorPostId: anchorPostId,
      );
    } catch (_) {
      return null;
    }
  }
}
