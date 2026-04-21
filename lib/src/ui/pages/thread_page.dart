import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:xdnmb_api/xdnmb_api.dart' as api;

import '../../app/app_state.dart';
import '../../app/composer_controller.dart';
import '../../app/cookie_controller.dart';
import '../../app/settings_controller.dart';
import '../../data/history_store.dart';
import '../../data/local_prefs.dart';
import '../../data/subscription_store.dart';
import '../../data/thread_cursor.dart';
import '../../data/perf_log.dart';
import '../../data/xdnmb_repository.dart';
import '../widgets/composer_panel.dart';
import '../widgets/resizable_divider.dart';
import '../widgets/thread_post_item.dart';

enum _LoadDirection { refresh, append, prepend }

final class _ScrollAnchor {
  final int index;
  final double leadingEdge;
  const _ScrollAnchor({required this.index, required this.leadingEdge});
}

final class ThreadPage extends StatefulWidget {
  final int mainPostId;
  final String? title;
  final int? flashPostId;
  /// If known, the 1-based page to open initially. This skips page probing
  /// for deep reply jumps (e.g. from post history).
  final int? initialPage;

  const ThreadPage({
    super.key,
    required this.mainPostId,
    this.title,
    this.flashPostId,
    this.initialPage,
  });

  @override
  State<ThreadPage> createState() => _ThreadPageState();
}

final class _ThreadPageState extends State<ThreadPage> {
  final _subStore = const SubscriptionStore();
  final _historyStore = HistoryStore();
  bool _subWorking = false;

  bool _loading = true;
  // 进入串内后，如果需要根据 cursor/flash 做定位跳转，
  // 在定位完成前先用遮罩挡住内容，避免用户短暂看到串首。
  bool _hideContentUntilJump = false;
  Object? _error;

  ComposerController? _composerRef;
  XdnmbRepository? _repoRef;

  bool _onlyPo = false;
  String? _poUserHash;

  int _page = 1;
  bool _loadingPage = false;
  bool _hasMore = true;
  final ItemScrollController _itemScroll = ItemScrollController();
  final ItemPositionsListener _itemPositions = ItemPositionsListener.create();

  // True while [_loadSurroundingPages] is running. Used to defer
  // jump-failure handling until all surrounding pages are loaded.
  bool _isLoadingSurrounding = false;

  // postId -> page mapping.  Because deleted replies make the actual reply
  // count per page inconsistent, we cannot derive the page from a flat index
  // via simple arithmetic.  Instead we record the exact page for each loaded
  // reply post.
  final Map<int, int> _postIdToPage = {};

  // Held so we can flush progress in [dispose] without touching [context].
  LocalPrefs? _prefsRef;

  // Last known reading anchor, updated on every scroll persist so we can
  // save the *most recent* position when the page is destroyed.
  int? _lastReadPostId;
  int? _lastReadPage;

  // ---- Cursor v2 (KV-JSON) ----
  // Main thread cursor: single source of truth per thread.
  static const String _kThreadMainCursorPrefix = 'xdnmb.threadCursor.main.';
  // Reply cursor: keyed by threadId + replyPostId.
  static const String _kThreadReplyCursorPrefix = 'xdnmb.threadCursor.reply.';

  // Reply jump target (from post history).
  int? _jumpTargetPostId;
  int? _flashingPostId; // The post currently being flash-highlighted
  int _flashPhase = 0; // increments to trigger rebuilds during flashing
  bool _showBackToTop = false;

  // ── In-thread search ──
  bool _searchMode = false;
  final _searchController = TextEditingController();
  final List<int> _searchMatches = [];
  int _currentSearchMatch = -1;

  // Safety timer: force-reveal content if jump takes too long.
  Timer? _jumpTimeout;

  // Flattened view: first main post then replies.
  final _posts = <api.PostBase>[];
  List<int> _inThreadPostIds = const [];

  // XDNMB API: each thread page contains up to 19 replies (main post not counted).
  static const int _kRepliesPerPage = 19;

  // Tracks the loaded reply page range.
  int? _loadedMinReplyPage;
  int? _loadedMaxReplyPage;

  int _pageFromFlatIndex(int index) {
    // index==0 is main post.
    if (index <= 0) return 1;
    final replyOffset = index - 1;
    final basePage = _loadedMinReplyPage ?? 1;
    final page = basePage + (replyOffset ~/ _kRepliesPerPage);
    PerfLog.log('thread.pageFromFlatIndex index=$index basePage=$basePage replyOffset=$replyOffset page=$page loadedMin=$_loadedMinReplyPage loadedMax=$_loadedMaxReplyPage posts=${_posts.length}');
    return page;
  }

  int? _maxPageHint;

  int? _extractMaxPage(api.PostBase mainPost) {
    final v = mainPost.maxPage;
    if (v == null) return null;
    if (v <= 0) return null;
    return v;
  }

  @override
  void initState() {
    super.initState();
    final flash = widget.flashPostId;
    final initialPage = widget.initialPage;

    final app = context.read<AppState>();
    _repoRef = app.repo;
    _prefsRef = app.prefs;
    _repoRef!.startThreadSession(widget.mainPostId, _onlyPo);

    final composer = context.read<ComposerController>();
    _composerRef = composer;
    composer.refreshSignal.addListener(_onRefreshSignal);

    // If caller already knows the page (e.g. from post history), use it
    // directly and skip all probing.
    if (initialPage != null && initialPage > 0) {
      _page = initialPage;
      if (flash != null && flash != widget.mainPostId) {
        _jumpTargetPostId = flash;
        _hideContentUntilJump = true;
        _startJumpTimeout();
      }
      PerfLog.log('thread.init path=knownPage threadId=${widget.mainPostId} page=$_page jumpTarget=$_jumpTargetPostId');
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final ok = await _loadPage(_page, direction: _LoadDirection.refresh);
        if (mounted && ok) await _loadSurroundingPages(_page);
        if (mounted) await _seedMainCursorIfAbsent();
      });
    } else if (flash != null && flash != widget.mainPostId) {
      _jumpTargetPostId = flash;
      _hideContentUntilJump = true;
      _startJumpTimeout();
      PerfLog.log('thread.init path=replyJump threadId=${widget.mainPostId} flashPostId=$flash');
      _initWithReplyJump(flash);
    } else {
      // Normal browsing: restore main cursor before loading so we can
      // start from the correct page instead of always page 1.
      PerfLog.log('thread.init path=normalBrowse threadId=${widget.mainPostId}');
      _initWithMainCursor();
    }
  }

  void _onRefreshSignal() {
    if (mounted) {
      _loadPage(1,
          direction: _LoadDirection.refresh, forceRefresh: true);
    }
  }

  Future<void> _initWithReplyJump(int flash) async {
    final prefs = context.read<AppState>().prefs;
    final key = '$_kThreadReplyCursorPrefix${widget.mainPostId}.$flash';
    final raw = await prefs.getThreadCursor(key);
    if (mounted && raw != null) {
      final c = ThreadReplyCursor.tryParseJsonString(raw);
      if (c != null && c.threadId == widget.mainPostId && c.page > 0) {
        _page = c.page;
        _jumpTargetPostId = c.anchorPostId;
        PerfLog.log('thread.replyCursor.restore ok threadId=${widget.mainPostId} page=$_page anchor=$_jumpTargetPostId');
      } else {
        PerfLog.log('thread.replyCursor.restore invalid threadId=${widget.mainPostId} raw=${raw.substring(0, min(80, raw.length))}');
      }
    } else {
      PerfLog.log('thread.replyCursor.restore miss threadId=${widget.mainPostId} key=$key');
    }
    // No reply cursor → start from thread head; do NOT set _jumpTargetPostId.
    if (mounted) {
      final ok = await _loadPage(_page, direction: _LoadDirection.refresh);
      if (mounted && ok) await _loadSurroundingPages(_page);
      if (mounted) await _seedMainCursorIfAbsent();
    }
  }

  Future<void> _initWithMainCursor() async {
    final prefs = context.read<AppState>().prefs;

    // v2: try restore from unified cursor blob.
    final mainCursorKey = '$_kThreadMainCursorPrefix${widget.mainPostId}';
    final rawCursor = await prefs.getThreadCursor(mainCursorKey);
    final mainCursor =
        rawCursor == null ? null : ThreadMainCursor.tryParseJsonString(rawCursor);

    if (!mounted) {
      _loadPage(_page);
      return;
    }

    if (mainCursor != null && mainCursor.threadId == widget.mainPostId) {
      _jumpTargetPostId = mainCursor.anchorPostId;
      if (mainCursor.page != null && mainCursor.page! > 0) {
        _page = mainCursor.page!;
        _hideContentUntilJump = true;
        _startJumpTimeout();
      }
      PerfLog.log('thread.mainCursor.restore ok threadId=${widget.mainPostId} page=$_page anchor=$_jumpTargetPostId');
    } else {
      PerfLog.log('thread.mainCursor.restore miss threadId=${widget.mainPostId} raw=${rawCursor == null ? 'null' : rawCursor.substring(0, min(80, rawCursor.length))}');
    }
    // No cursor → start from thread head (page 1). The cursor will be
    // seeded at page 1 in _loadPage when data arrives.

    if (mounted) {
      final ok = await _loadPage(_page, direction: _LoadDirection.refresh);
      if (mounted && ok) {
        if (_page > 1) {
          await _loadSurroundingPages(_page);
        } else if (_jumpTargetPostId != null) {
          // Page 1: the target post is already in _posts; try scrolling to it.
          _tryJumpOrLoadMore();
        }
      }
    }
  }

  /// DEPRECATED: logic moved to [_initWithMainCursor] and [_initWithReplyJump].
  /// Kept temporarily for reference; will be removed in a follow-up.

  Future<void> _triggerFlash(int postId) async {
    if (!mounted) return;
    setState(() => _flashingPostId = postId);
    // 2~3 次浅灰闪烁（每次 150ms on/off）。
    for (var i = 0; i < 3; i++) {
      if (!mounted) return;
      setState(() => _flashPhase++);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      setState(() => _flashPhase++);
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (!mounted) return;
    setState(() => _flashingPostId = null);
  }

  void _startJumpTimeout() {
    _jumpTimeout?.cancel();
    _jumpTimeout = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      if (_hideContentUntilJump) {
        setState(() => _hideContentUntilJump = false);
      }
    });
  }

  void _cancelJumpTimeout() {
    _jumpTimeout?.cancel();
    _jumpTimeout = null;
  }

  /// Snapshot the current scroll position and persist it as the main cursor.
  /// Safe to call from [dispose] because it uses [_prefsRef] instead of
  /// [context.read].
  void _persistReadingProgress() {
    if (_posts.isEmpty) return;
    // Skip while jump animation is in progress; the intermediate scroll
    // position is not meaningful reading progress.
    if (_hideContentUntilJump) return;

    final positions = _itemPositions.itemPositions.value;
    if (positions.isEmpty) return;

    final visible = positions
        .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
        .toList(growable: false);
    if (visible.isEmpty) return;

    // Save the *bottom-most* visible item as the reading anchor.
    // Users read top-to-bottom; the last seen item is a better
    // progress marker than the top-of-screen item.
    visible.sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
    final last = visible.last;
    // Convert item index to post index (accounting for top loader offset).
    final rawPostIdx = _showTopLoader ? last.index - 1 : last.index;
    final postIdx = rawPostIdx.clamp(0, _posts.length - 1);
    final postId = _posts[postIdx].id;

    final prefs = _prefsRef;
    if (prefs == null) return;

    // Derive page via the exact lookup table (falls back to arithmetic when
    // the post hasn't been recorded yet, e.g. very first load).
    final locatedPage = _postIdToPage[postId] ?? _pageFromFlatIndex(postIdx);
    final arithmeticPage = _pageFromFlatIndex(postIdx);
    _lastReadPostId = postId;
    _lastReadPage = locatedPage;

    PerfLog.log('thread.persist postId=$postId postIdx=$postIdx locatedPage=$locatedPage(arithmetic=$arithmeticPage) mapSize=${_postIdToPage.length}');

    // v2 (preferred): KV-JSON blob.
    final mainCursorKey = '$_kThreadMainCursorPrefix${widget.mainPostId}';
    final cursor = ThreadMainCursor(
      threadId: widget.mainPostId,
      anchorPostId: postId,
      topIndexHint: postIdx,
      page: locatedPage,
    );
    // ignore: discarded_futures
    prefs.setThreadCursor(mainCursorKey, cursor.toJsonString());
  }

  @override
  void dispose() {
    // Snapshot the final scroll position at exit time rather than
    // debouncing on every scroll event.
    _persistReadingProgress();

    _jumpTimeout?.cancel();
    _jumpTimeout = null;
    _composerRef?.refreshSignal.removeListener(_onRefreshSignal);
    _composerRef = null;
    _repoRef?.endThreadSession(widget.mainPostId, _onlyPo);
    _repoRef = null;
    _prefsRef = null;
    super.dispose();
  }

  /// Convert a [_posts] array index to the actual ScrollablePositionedList
  /// item index, accounting for the optional top loader item.
  int _itemIndexForPostIndex(int postIndex) {
    return postIndex + (_showTopLoader ? 1 : 0);
  }

  void _scrollToPostId(
    int postId, {
    required double alignment,
    required bool flash,
  }) {
    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx < 0) {
      PerfLog.log('thread.scroll.miss postId=$postId posts=${_posts.length}');
      return;
    }

    // If called before list attaches, schedule once after next frame.
    if (!_itemScroll.isAttached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_posts.isEmpty) return;
        if (!_itemScroll.isAttached) return;
        // Ensure index is still valid after potential reload.
        final nextIdx = _posts.indexWhere((p) => p.id == postId);
        if (nextIdx < 0) return;
        _scrollToPostId(postId, alignment: alignment, flash: flash);
      });
      return;
    }

    final itemIdx = _itemIndexForPostIndex(idx);
    PerfLog.log('thread.scroll postId=$postId postIdx=$idx itemIdx=$itemIdx alignment=$alignment flash=$flash');
    final f = _itemScroll.scrollTo(
      index: itemIdx,
      alignment: alignment,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );

    // 定位完成后再展示内容，形成”无缝跳转”。
    // 注意：scrollTo 的 Future 在列表 attach 且动画结束后完成。
    // 这里不等待图片加载，只保证首屏位置正确。
    if (_hideContentUntilJump) {
      // ignore: discarded_futures
      f.then((_) {
        if (!mounted) return;
        if (_hideContentUntilJump) {
          setState(() => _hideContentUntilJump = false);
        }
        _cancelJumpTimeout();
        PerfLog.log('thread.scroll.done postId=$postId');
      });
    }
    if (flash) {
      // ignore: discarded_futures
      f.then((_) {
  if (!mounted) return;
        // Only flash if the post still exists.
  if (_posts.indexWhere((p) => p.id == postId) < 0) return;
  _triggerFlash(postId);
      });
    }
  }

  /// Try to jump to target once. If found, scroll and flash.
  /// If not found, give up and reveal content (we already loaded the
  /// correct page from the cursor, so the target should be there).
  void _tryJumpOrLoadMore() {
    final id = _jumpTargetPostId;
    if (id == null) return;
    final idx = _posts.indexWhere((p) => p.id == id);
    if (idx >= 0) {
      PerfLog.log('thread.jump.found id=$id idx=$idx posts=${_posts.length} loadedMin=$_loadedMinReplyPage loadedMax=$_loadedMaxReplyPage');
      // 立即清除 jump target，防止 _loadSurroundingPages 末尾的
      // _handleJumpFailed callback 被错误触发。
      _jumpTargetPostId = null;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final isFromReplyHistory = widget.flashPostId != null;

        _scrollToPostId(id, alignment: 0.0, flash: isFromReplyHistory);

        // If we're jumping from reply history, persist a reply cursor keyed by
        // (threadId + replyPostId) so future jumps are immediate.
        if (isFromReplyHistory) {
          final prefs = context.read<AppState>().prefs;
          final key =
              '$_kThreadReplyCursorPrefix${widget.mainPostId}.$id';

          // Re-lookup the post index because surrounding pages may have
          // changed _posts / _loadedMinReplyPage since the outer frame.
          final currentIdx = _posts.indexWhere((p) => p.id == id);
          if (currentIdx < 0) return;

          // Persist a cursor with the located page so next time we can jump directly.
          final locatedPage = _postIdToPage[id] ?? _pageFromFlatIndex(currentIdx);
          final replyIndexInPage =
              ((currentIdx - 1) % _kRepliesPerPage).clamp(0, 999999);
          final cursor = ThreadReplyCursor(
            threadId: widget.mainPostId,
            page: locatedPage,
            replyIndexInPage: replyIndexInPage,
            anchorPostId: id,
          );
          PerfLog.log('thread.replyCursor.save id=$id page=$locatedPage replyIdx=$replyIndexInPage');
          // ignore: discarded_futures
          prefs.setThreadCursor(key, cursor.toJsonString());
        }
      });
    } else if (!_isLoadingSurrounding) {
      // Target not found and surrounding load is done -- give up.
      PerfLog.log('thread.jump.notFound id=$id posts=${_posts.length} loadedMin=$_loadedMinReplyPage loadedMax=$_loadedMaxReplyPage isLoadingSurrounding=false');
      _handleJumpFailed();
    } else {
      PerfLog.log('thread.jump.defer id=$id posts=${_posts.length} isLoadingSurrounding=true');
    }
    // If surrounding is still loading, keep _jumpTargetPostId alive so
    // the final retry in [_loadSurroundingPages] has a chance to find it.
  }

  /// Common cleanup when jump fails (post deleted or unreachable).
  void _handleJumpFailed() {
    final fallbackId = _jumpTargetPostId;
    _jumpTargetPostId = null;

    // 优先通过精确的 postId 在已加载内容中查找回退位置，
    // 避免依赖不稳定的 flat index（恢复时 _posts 长度可能完全不同）。
    if (fallbackId != null) {
      final idx = _posts.indexWhere((p) => p.id == fallbackId);
      if (idx >= 0) {
        PerfLog.log('thread.jump.fallbackByPostId id=$fallbackId idx=$idx');
        _scrollToPostId(fallbackId, alignment: 0.0, flash: false);
        return;
      }
    }

    // 找不到 postId（帖子已被删除或不在已加载范围内），直接显示内容。
    PerfLog.log('thread.jump.fallbackNone fallbackId=$fallbackId posts=${_posts.length}');
    if (_hideContentUntilJump) {
      setState(() => _hideContentUntilJump = false);
    }
    _cancelJumpTimeout();
  }

  /// Seed a default main cursor at thread head if none exists yet.
  /// Called after the first successful page load to ensure non-reply
  /// entry points always have a cursor to restore.
  Future<void> _seedMainCursorIfAbsent() async {
    final prefs = _prefsRef;
    if (prefs == null) return;
    final mainCursorKey = '$_kThreadMainCursorPrefix${widget.mainPostId}';
    final existing = await prefs.getThreadCursor(mainCursorKey);
    if (existing == null && _posts.isNotEmpty) {
      final headId = _posts.first.id;
      final cursor = ThreadMainCursor(
        threadId: widget.mainPostId,
        anchorPostId: headId,
        topIndexHint: 0,
        page: 1,
      );
      // ignore: discarded_futures
      prefs.setThreadCursor(mainCursorKey, cursor.toJsonString());
    }
  }

  void _onScroll() {
    final positions = _itemPositions.itemPositions.value;

    // Back to top button: show when first visible index is deep enough.
    var show = false;
    if (positions.isNotEmpty) {
      final minIndex = positions
          .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
          .fold<int?>(null, (min, p) {
        if (min == null) return p.index;
        return p.index < min ? p.index : min;
      });
      show = (minIndex ?? 0) >= 5;
    }
    if (show != _showBackToTop) setState(() => _showBackToTop = show);

    final settings = context.read<SettingsController>();
    if (!settings.autoLoadOnScroll || _loadingPage) return;

    // ---- Auto-load previous page when near top ----
    if (_hasPreviousPage) {
      final firstVisible = positions
          .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
          .fold<int?>(null, (min, p) {
        if (min == null) return p.index;
        return p.index < min ? p.index : min;
      });
      final topThreshold = _showTopLoader ? 2 : 1;
      if (firstVisible != null && firstVisible <= topThreshold) {
        _loadPreviousPage();
        return; // Prevent double-trigger in same frame.
      }
    }

    // ---- Auto-load next page when near bottom ----
    if (_hasMore) {
      final lastVisible = positions
          .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
          .fold<int?>(null, (max, p) {
        if (max == null) return p.index;
        return p.index > max ? p.index : max;
      });
      // Adjust for top loader offset when comparing against _posts length.
      final adjustedLast = _showTopLoader && lastVisible != null
          ? lastVisible - 1
          : lastVisible;
      if (adjustedLast != null && adjustedLast >= _posts.length - 4) {
        _loadNextPage();
      }
    }
  }

  /// Loads a single thread page.
  ///
  /// Returns `true` if the page was loaded successfully, `false` otherwise.
  /// Callers that chain [_loadSurroundingPages] should check the return value
  /// to avoid wasting requests on a broken network path.
  Future<bool> _loadPage(
    int page, {
    bool forceRefresh = false,
    _LoadDirection direction = _LoadDirection.append,
    bool adjustScroll = true,
  }) async {
    if (_loadingPage) return false;
    if (!mounted) return false;

    final perf = PerfLog.stage('thread.loadPage');
    perf.check(
      'start',
      fields: {
        'threadId': widget.mainPostId,
        'page': page,
        'force': forceRefresh,
        'onlyPo': _onlyPo,
        'direction': direction.name,
      },
    );

    // Record scroll anchor before prepend so we can restore visual position.
    _ScrollAnchor? anchor;
    if (direction == _LoadDirection.prepend && _itemScroll.isAttached) {
      final positions = _itemPositions.itemPositions.value;
      if (positions.isNotEmpty) {
        final visible = positions
            .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
            .toList(growable: false);
        if (visible.isNotEmpty) {
          visible.sort((a, b) =>
              a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
          final top = visible.first;
          // Only anchor if user is not already at the very top.
          final topPostIndex = _showTopLoader ? top.index - 1 : top.index;
          if (topPostIndex > 0) {
            anchor = _ScrollAnchor(
              index: topPostIndex,
              leadingEdge: top.itemLeadingEdge,
            );
          }
        }
      }
    }

    setState(() {
      if (direction == _LoadDirection.refresh || _posts.isEmpty) {
        _loading = true;
        _error = null;
      }
      _loadingPage = true;
    });
    perf.check('setState.loading');

    try {
      final repo = context.read<AppState>().repo;
      perf.check('request.start');
      final thread = _onlyPo
          ? await repo.getOnlyPoThreadPage(
              widget.mainPostId,
              page,
              forceRefresh: forceRefresh,
            )
          : await repo.getThreadPage(
              widget.mainPostId,
              page,
              forceRefresh: forceRefresh,
            );

      perf.check(
        'request.end',
        fields: {
          'replies': thread.replies.length,
          'hasTitle': (thread.mainPost.title.trim().isNotEmpty),
        },
      );

      if (!mounted) return true;

      _poUserHash ??= thread.mainPost.userHash;
      _maxPageHint ??= _extractMaxPage(thread.mainPost);

      final beforeCount = _posts.length;
      setState(() {
        if (direction == _LoadDirection.refresh || _posts.isEmpty) {
          _posts
            ..clear()
            ..add(thread.mainPost)
            ..addAll(thread.replies);
          _loadedMinReplyPage = page;
          _loadedMaxReplyPage = page;
          _postIdToPage.clear();
        } else if (direction == _LoadDirection.append) {
          _posts.addAll(thread.replies);
          _loadedMaxReplyPage = page;
        } else if (direction == _LoadDirection.prepend) {
          // Insert after mainPost (index 1).
          _posts.insertAll(1, thread.replies);
          _loadedMinReplyPage = page;
        }
        // Record exact page mapping for every loaded reply.
        for (final reply in thread.replies) {
          _postIdToPage[reply.id] = page;
        }
        _inThreadPostIds = _posts.map((e) => e.id).toList(growable: false);
        if (direction != _LoadDirection.prepend) {
          _page = page;
        }
        _hasMore = thread.replies.isNotEmpty;
        _loading = false;
        _loadingPage = false;
      });

      // Record thread visit on first load (covers both page-1 entry and
      // deep-jump entry via reply history / initialPage).
      if (direction == _LoadDirection.refresh) {
        final mainPost = thread.mainPost;
        // ignore: discarded_futures
        _historyStore.recordVisit(
          threadId: widget.mainPostId,
          title: mainPost.title.trim().isEmpty ? null : mainPost.title.trim(),
          userHash: mainPost.userHash.trim().isEmpty ? null : mainPost.userHash.trim(),
          isAdmin: mainPost.isAdmin,
          postTime: mainPost.postTime,
          replyCount: mainPost.replyCount,
          thumbImageUrl: mainPost.thumbImageUrl,
          content: mainPost.content,
        );
      }

      // Restore scroll position after prepend.
      if (direction == _LoadDirection.prepend && anchor != null && adjustScroll) {
        final insertedCount = thread.replies.length;
        final newPostIndex = anchor.index + insertedCount;
        final newItemIndex = _itemIndexForPostIndex(newPostIndex);
        final targetAlignment = anchor.leadingEdge;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!_itemScroll.isAttached) return;
          if (newItemIndex >= _posts.length + (_showTopLoader ? 1 : 0)) return;
          _itemScroll.jumpTo(
            index: newItemIndex,
            alignment: targetAlignment,
          );
        });
      }

      // ---- Adjacent page prefetch (best-effort) ----
      if (mounted) {
        final repo = context.read<AppState>().repo;
        // ignore: discarded_futures
        repo.prefetchThreadAdjacentPages(
          mainPostId: widget.mainPostId,
          currentPage: page,
          onlyPo: _onlyPo,
        );
      }

      perf.check(
        'setState.data',
        fields: {
          'postsBefore': beforeCount,
          'postsAfter': _posts.length,
          'hasMore': _hasMore,
        },
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        perf.end('firstFrame', {
          'posts': _posts.length,
          'mounted': mounted,
        });
      });

      // On first page load, seed a default cursor at thread head if none exists.
      if (page == 1) {
        await _seedMainCursorIfAbsent();

        if (!mounted) return true;
        if (_jumpTargetPostId != null && !_hideContentUntilJump) {
          setState(() => _hideContentUntilJump = true);
          _startJumpTimeout();
        }
      }

      if (!mounted) return true;
      return true;
    } catch (e) {
      if (!mounted) return false;
      perf.end(
        'error',
        {
          'err': e.toString(),
        },
      );
      setState(() {
        _error = e;
        _loading = false;
        _loadingPage = false;
        _hideContentUntilJump = false;
      });
      return false;
    }
  }

  bool get _hasPreviousPage =>
      (_loadedMinReplyPage ?? 1) > 1;

  bool get _showTopLoader => _hasPreviousPage;

  Widget _buildTopLoader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: FilledButton.tonal(
          onPressed: _loadingPage ? null : () => _loadPreviousPage(),
          child: Text(_loadingPage ? '加载中…' : '加载上一页'),
        ),
      ),
    );
  }

  Future<void> _loadPreviousPage() async {
    final target = (_loadedMinReplyPage ?? 1) - 1;
    if (target < 1) return;
    await _loadPage(target, direction: _LoadDirection.prepend);
  }

  Future<void> _loadNextPage() async {
    final target = (_loadedMaxReplyPage ?? 1) + 1;
    await _loadPage(target, direction: _LoadDirection.append);
  }

  /// After jumping to a target page, proactively load surrounding pages
  /// so the user can scroll in either direction without waiting.
  /// Loads up to 2 pages before and 2 pages after [centerPage].
  Future<void> _loadSurroundingPages(int centerPage) async {
    if (!mounted) return;
    final perf = PerfLog.stage('thread.loadSurrounding');
    _isLoadingSurrounding = true;
    PerfLog.log('thread.loadSurrounding start centerPage=$centerPage jumpTarget=$_jumpTargetPostId posts=${_posts.length}');

    // Load forward pages first (append, no scroll adjustment needed).
    for (var p = centerPage + 1; p <= centerPage + 2; p++) {
      if (!_hasMore) break;
      final ok = await _loadPage(p, direction: _LoadDirection.append);
      if (!mounted) return;
      if (!ok) break;
    }
    perf.check('forwardLoaded', fields: {'posts': _posts.length, 'hasMore': _hasMore});

    // Capture anchor before backward loads for a single restore.
    // For reply-jumps we skip restoration because the scrollTo animation
    // races with prepend setState storms; the jump handler positions the
    // list instead. For normal cursor restores we must restore so prepend
    // insertions don't shift the viewport away from the target post.
    final isReplyJump = widget.flashPostId != null;
    final shouldRestoreScroll =
        !_hideContentUntilJump && !isReplyJump;
    _ScrollAnchor? anchor;
    if (shouldRestoreScroll && _itemScroll.isAttached) {
      final positions = _itemPositions.itemPositions.value;
      if (positions.isNotEmpty) {
        final visible = positions
            .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
            .toList(growable: false);
        if (visible.isNotEmpty) {
          visible.sort((a, b) =>
              a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
          final top = visible.first;
          // Record the _posts index (not the raw item index) so we can
          // correctly compute the new item index after prepends.
          final topPostIndex = _showTopLoader ? top.index - 1 : top.index;
          anchor = _ScrollAnchor(
            index: topPostIndex,
            leadingEdge: top.itemLeadingEdge,
          );
        }
      }
    }

    // For reply-jumps (e.g. from post history), skip backward loads.
    // When all surrounding pages hit cache, the prepend setState storms
    // race with the scrollTo animation and shift item indices before the
    // scroll can complete, causing the list to land at the wrong post.
    // Backward pages will be loaded on-demand via auto-load when the user
    // scrolls up.
    if (!isReplyJump) {
      var totalInserted = 0;
      for (var p = centerPage - 1; p >= centerPage - 2; p--) {
        if (p < 1) break;
        final beforeLen = _posts.length;
        await _loadPage(p,
            direction: _LoadDirection.prepend, adjustScroll: false);
        if (!mounted) return;
        totalInserted += _posts.length - beforeLen;
      }
      perf.check('backwardLoaded', fields: {'totalInserted': totalInserted, 'posts': _posts.length});

      // Restore scroll position once after all backward loads.
      if (anchor != null && totalInserted > 0) {
        final newPostIndex = anchor.index + totalInserted;
        final newItemIndex = _itemIndexForPostIndex(newPostIndex);
        final targetAlignment = anchor.leadingEdge;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!_itemScroll.isAttached) return;
          if (newItemIndex >= _posts.length + (_showTopLoader ? 1 : 0)) return;
          _itemScroll.jumpTo(
            index: newItemIndex,
            alignment: targetAlignment,
          );
        });
      }
    }

    // If the jump target was not found in the center page, try once more
    // now that surrounding pages have also been loaded.
    if (_jumpTargetPostId != null) {
      PerfLog.log('thread.loadSurrounding retryJump jumpTarget=$_jumpTargetPostId posts=${_posts.length}');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tryJumpOrLoadMore();
      });
    }
    _isLoadingSurrounding = false;

    // Restore _page to the center page so the jump-to-page dialog and
    // footer loader show the correct page the user is actually viewing.
    setState(() => _page = centerPage);

    // If the target still could not be found after all surrounding pages
    // are loaded, give up and reveal content.
    if (_jumpTargetPostId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Defensive: retryJump callback may have already found the target and
        // cleared _jumpTargetPostId. Only handle failure if it's still set.
        if (_jumpTargetPostId != null) {
          PerfLog.log('thread.loadSurrounding jumpFailed jumpTarget=$_jumpTargetPostId posts=${_posts.length}');
          _handleJumpFailed();
        }
      });
    }
    perf.end('done', {'posts': _posts.length});
  }

  Widget _buildListFooter(BuildContext context) {
    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            '没有更多了',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: FilledButton.tonal(
          onPressed: _loadingPage ? null : () => _loadPage(_page + 1),
          child: Text(_loadingPage ? '加载中…' : '点击加载更多'),
        ),
      ),
    );
  }

  Future<void> _replyToPost(int postId) async {
    final cookieCtrl = context.read<CookieController>();
    final composer = context.read<ComposerController>();
    final quoteText = '>>No.$postId\n';

    // If a detached sub-window is open, send the quote there.
    final sent = await composer.sendQuoteToWindow(quoteText);
    if (sent) return;

    // Otherwise fall back to the embedded panel.
    composer.openPanel(
      ComposerArgs(
        mode: ComposerMode.reply,
        mainPostId: widget.mainPostId,
        initialContent: quoteText,
      ),
      defaultCookieSlotId: cookieCtrl.defaultPostSlotId,
    );
  }

  void _onRefInThread(int postId) {
    _scrollToPostId(postId, alignment: 0.15, flash: true);
  }

  Future<void> _jumpToPage() async {
    final controller = TextEditingController(text: '$_page');
    final int? page;
    try {
      page = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('跳转到页'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Tooltip(
                  message: '跳转到串首',
                  child: IconButton(
                    onPressed: () => Navigator.pop(context, 1),
                    icon: const Icon(Icons.first_page),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      hintText: '页码',
                    ),
                  ),
                ),
                Tooltip(
                  message: '跳转到串尾',
                  child: IconButton(
                    onPressed: () => Navigator.pop(context, -1),
                    icon: const Icon(Icons.last_page),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          FilledButton(
              onPressed: () {
                final v = int.tryParse(controller.text.trim());
                if (v == null || v <= 0) return;
                Navigator.pop(context, v);
              },
              child: const Text('跳转')),
        ],
      ),
    );

    if (page != null) {
      if (page == -1) {
        // Jump to last page based on replyCount/maxPage.
        // XDNMB thread pages: each page contains up to 19 replies.
        // (This is provided by xdnmb_api's Thread.maxPage.)
        if (_posts.isNotEmpty) {
          final last = _posts.first.maxPage;
          if (last != null) {
            await _loadPage(last,
                direction: _LoadDirection.refresh, forceRefresh: true);
            // After loading last page, scroll to bottom.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (!_itemScroll.isAttached) return;
              if (_posts.isEmpty) return;
              final lastPostIndex = _posts.length - 1;
              final lastItemIndex = _itemIndexForPostIndex(lastPostIndex);
              _itemScroll.jumpTo(index: lastItemIndex, alignment: 1);
            });
          } else {
            // If maxPage is not available, load the current page and scroll to bottom
            await _loadPage(_page);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (!_itemScroll.isAttached) return;
              if (_posts.isEmpty) return;
              final lastPostIndex = _posts.length - 1;
              final lastItemIndex = _itemIndexForPostIndex(lastPostIndex);
              _itemScroll.jumpTo(index: lastItemIndex, alignment: 1);
            });
          }
        } else {
          // If no posts are loaded, load first page
          await _loadPage(1);
        }
      } else {
        // Clear existing posts before loading new page
        setState(() {
          _posts.clear();
          _hasMore = true;
          _loadedMinReplyPage = null;
          _loadedMaxReplyPage = null;
          // Clear jump target to prevent scrolling to saved position
          _jumpTargetPostId = null;
        });
        await _loadPage(page,
            direction: _LoadDirection.refresh, forceRefresh: true);
        // Ensure scroll to top (mainPost) after loading.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!_itemScroll.isAttached) return;
          // Scroll to mainPost (index 0 in _posts → item index accounts for
          // the optional top loader).
          final mainPostItemIndex = _itemIndexForPostIndex(0);
          _itemScroll.jumpTo(index: mainPostItemIndex, alignment: 0);
        });
        // Proactively load surrounding pages for a seamless scroll experience.
        // ignore: discarded_futures
        _loadSurroundingPages(page);
      }
    }
    } finally {
      controller.dispose();
    }
  }

  // ── Search ──

  void _toggleSearchMode() {
    setState(() {
      _searchMode = !_searchMode;
      if (!_searchMode) {
        _searchController.clear();
        _searchMatches.clear();
        _currentSearchMatch = -1;
      }
    });
  }

  void _performSearch(String query) {
    _searchMatches.clear();
    _currentSearchMatch = -1;
    if (query.trim().isEmpty) {
      setState(() {});
      return;
    }
    final lower = query.toLowerCase();
    for (var i = 0; i < _posts.length; i++) {
      final p = _posts[i];
      final text = '${p.content} ${p.userHash} ${p.title} ${p.name}'
          .toLowerCase();
      if (text.contains(lower)) {
        _searchMatches.add(i);
      }
    }
    if (_searchMatches.isNotEmpty) {
      _currentSearchMatch = 0;
      _scrollToMatch(0);
    }
    setState(() {});
  }

  void _nextMatch() {
    if (_searchMatches.isEmpty) return;
    final next = (_currentSearchMatch + 1) % _searchMatches.length;
    _currentSearchMatch = next;
    _scrollToMatch(next);
    setState(() {});
  }

  void _prevMatch() {
    if (_searchMatches.isEmpty) return;
    final prev = (_currentSearchMatch - 1 + _searchMatches.length) %
        _searchMatches.length;
    _currentSearchMatch = prev;
    _scrollToMatch(prev);
    setState(() {});
  }

  void _scrollToMatch(int matchIndex) {
    if (!_itemScroll.isAttached) return;
    final postIndex = _searchMatches[matchIndex];
    final itemIndex = _itemIndexForPostIndex(postIndex);
    _itemScroll.scrollTo(
      index: itemIndex,
      alignment: 0.15,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _searchMode
          ? AppBar(
              title: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索串内内容…',
                  border: InputBorder.none,
                ),
                onChanged: _performSearch,
              ),
              actions: [
                if (_searchMatches.isNotEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '${_currentSearchMatch + 1}/${_searchMatches.length}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: '上一个',
                  onPressed: _prevMatch,
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: '下一个',
                  onPressed: _nextMatch,
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: '关闭搜索',
                  onPressed: _toggleSearchMode,
                  icon: const Icon(Icons.close),
                ),
              ],
            )
          : AppBar(
              title: Text(() {
                final t = widget.title?.trim();
                if (t == null || t.isEmpty || t == '无标题') return '串';
                return t;
              }()),
              actions: [
                IconButton(
                  tooltip: '搜索',
                  onPressed: _toggleSearchMode,
                  icon: const Icon(Icons.search),
                ),
                IconButton(
                  tooltip: '刷新页面',
                  onPressed: () async {
                    await _loadPage(1,
                        direction: _LoadDirection.refresh,
                        forceRefresh: true);
                    if (_itemScroll.isAttached) {
                      _itemScroll.jumpTo(index: 0, alignment: 0);
                    }
                  },
                  icon: const Icon(Icons.refresh_outlined),
                ),
                IconButton(
                  tooltip: '订阅此串（再次点击可取消）',
                  onPressed: _subWorking
                      ? null
                      : () async {
                          setState(() => _subWorking = true);
                          try {
                            final repo = context.read<AppState>().repo;
                            final feedId = await _subStore.readFeedId();

                            // 尝试添加；若已订阅则删除。
                            try {
                              await repo.addFeed(feedId, widget.mainPostId);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('订阅成功（ID=$feedId）')),
                              );
                            } catch (_) {
                              await repo.deleteFeed(feedId, widget.mainPostId);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('已取消订阅（ID=$feedId）')),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _subWorking = false);
                          }
                        },
                  icon: const Icon(Icons.bookmark_add_outlined),
                ),
                IconButton(
                  tooltip: '只看PO',
                  onPressed: () async {
                    final oldOnlyPo = _onlyPo;
                    setState(() {
                      _onlyPo = !_onlyPo;
                    });
                    _repoRef?.endThreadSession(widget.mainPostId, oldOnlyPo);
                    await _loadPage(1,
                        direction: _LoadDirection.refresh, forceRefresh: true);
                    _repoRef?.startThreadSession(widget.mainPostId, _onlyPo);
                    if (_itemScroll.isAttached) {
                      _itemScroll.jumpTo(index: 0, alignment: 0);
                    }
                  },
                  icon: Icon(
                    Icons.person_search_outlined,
                    color:
                        _onlyPo ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
                IconButton(
                  tooltip: '跳页',
                  onPressed: _jumpToPage,
                  icon: const Icon(Icons.menu_book_outlined),
                ),
              ],
            ),
      floatingActionButton: Builder(
        builder: (context) {
          final composer = context.watch<ComposerController>();
          // Hide FAB whenever any composer is open (embedded panel or
          // detached sub-window) to avoid duplicate editing areas.
          if (composer.isOpen || composer.activeWindowId != null) {
            // If a detached window is tracked but the embedded panel is
            // closed, do a best-effort alive check in case the window
            // died without sending the windowClosed message.
            if (!composer.isOpen && composer.activeWindowId != null) {
              // ignore: discarded_futures
              composer.checkWindowAlive();
            }
            return const SizedBox.shrink();
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_showBackToTop) ...[
                FloatingActionButton.small(
                  heroTag: 'backToTop',
                  onPressed: () {
                    if (!_itemScroll.isAttached) return;
                    _itemScroll.scrollTo(
                      index: 0,
                      alignment: 0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  },
                  tooltip: '回到顶部',
                  child: const Icon(Icons.arrow_upward),
                ),
                const SizedBox(height: 8),
              ],
              FloatingActionButton.extended(
                onPressed: () {
                  final cookieCtrl = context.read<CookieController>();
                  final composer = context.read<ComposerController>();
                  composer.openPanel(
                    ComposerArgs(
                      mode: ComposerMode.reply,
                      mainPostId: widget.mainPostId,
                    ),
                    defaultCookieSlotId: cookieCtrl.defaultPostSlotId,
                  );
                },
                icon: const Icon(Icons.reply_outlined),
                label: const Text('回串'),
              ),
            ],
          );
        },
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final composer = context.watch<ComposerController>();
          final showPanel = composer.isOpen && composer.displayMode == ComposerDisplayMode.panel;
          final maxPanelW = constraints.maxWidth * 0.55;

          return Row(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    // 正常内容层
                    _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('加载失败：$_error'),
                                    const SizedBox(height: 12),
                                    FilledButton(
                                        onPressed: () =>
                                            _loadPage(1, direction: _LoadDirection.refresh),
                                        child: const Text('重试')),
                                  ],
                                ),
                              )
                            : _posts.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text('（空）'),
                                        const SizedBox(height: 12),
                                        FilledButton(
                                          onPressed: () =>
                                              _loadPage(1, direction: _LoadDirection.refresh),
                                          child: const Text('重新加载'),
                                        ),
                                      ],
                                    ),
                                  )
                                : NotificationListener<ScrollNotification>(
                                    onNotification: (n) {
                                      if (n is ScrollUpdateNotification ||
                                          n is UserScrollNotification) {
                                        _onScroll();
                                      }
                                      return false;
                                    },
                                    child: ScrollablePositionedList.separated(
                                      itemScrollController: _itemScroll,
                                      itemPositionsListener: _itemPositions,
                                      itemCount: _posts.length +
                                          1 +
                                          (_showTopLoader ? 1 : 0),
                                      separatorBuilder: (context, index) =>
                                          const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        // Top loader inserted before mainPost.
                                        if (_showTopLoader && index == 0) {
                                          return _buildTopLoader(context);
                                        }
                                        final adjustedIndex =
                                            _showTopLoader ? index - 1 : index;
                                        if (adjustedIndex == _posts.length) {
                                          return _buildListFooter(context);
                                        }
                                        final p = _posts[adjustedIndex];
                                        return ThreadPostItem(
                                          post: p,
                                          index: adjustedIndex,
                                          poUserHash: _poUserHash,
                                          flashPostId: _flashingPostId,
                                          flashPhase: _flashPhase,
                                          onReply: () => _replyToPost(p.id),
                                          isSearchMatch:
                                              _searchMatches.contains(adjustedIndex),
                                          inThreadPostIds: _inThreadPostIds,
                                          onRefInThread: _onRefInThread,
                                        );
                                      },
                                    ),
                                  ),
                    // 无缝跳转遮罩层
                    if (!_loading && _error == null && _hideContentUntilJump)
                      Positioned.fill(
                        child: AbsorbPointer(
                          absorbing: true,
                          child: ColoredBox(
                            color: Theme.of(context)
                                .colorScheme
                                .surface
                                .withValues(alpha: 0.96),
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 12),
                                  Text('定位中…'),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (showPanel)
                ValueListenableBuilder<double>(
                  valueListenable: composer.panelWidthNotifier,
                  builder: (context, width, child) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const VerticalDivider(width: 1),
                        ResizableDivider(
                          width: width,
                          minWidth: 320,
                          maxWidth: maxPanelW,
                          onWidthChanged: (w) => composer.setPanelWidth(w),
                        ),
                        SizedBox(
                          width: width.clamp(320.0, maxPanelW),
                          child: child!,
                        ),
                      ],
                    );
                  },
                  child: ComposerPanel(
                    onSubmitSuccess: () async {
                      // After posting a reply, jump to the last page so the
                      // user can see their new reply immediately.
                      if (_posts.isNotEmpty) {
                        final maxPage = _extractMaxPage(_posts.first);
                        final targetPage = maxPage ?? _page;
                        await _loadPage(targetPage,
                            direction: _LoadDirection.refresh,
                            forceRefresh: true);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          if (!_itemScroll.isAttached) return;
                          if (_posts.isEmpty) return;
                          final lastPostIndex = _posts.length - 1;
                          final lastItemIndex =
                              _itemIndexForPostIndex(lastPostIndex);
                          _itemScroll.jumpTo(
                            index: lastItemIndex,
                            alignment: 1,
                          );
                        });
                      } else {
                        await _loadPage(1,
                            direction: _LoadDirection.refresh,
                            forceRefresh: true);
                        if (_itemScroll.isAttached) {
                          _itemScroll.jumpTo(index: 0, alignment: 0);
                        }
                      }
                    },
                  ),
                ),
            ],
          );
        },
      ),
        );
  }
}


