import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:xdnmb_api/xdnmb_api.dart' as api;
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';

import '../../app/app_state.dart';
import '../../data/subscription_store.dart';
import 'composer_page.dart';
import '../widgets/post_content.dart';

final class _PostImage extends StatelessWidget {
  final api.PostBase post;

  const _PostImage({required this.post});

  Future<void> _download(BuildContext context, String url) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '保存原图',
      fileName: post.imageFile ?? 'image',
    );
    if (path == null) return;

    try {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
  await File(path).writeAsBytes(response.bodyBytes);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已保存')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!post.hasImage) return const SizedBox.shrink();
    if (!context.watch<AppState>().showImageInThread) {
      return const SizedBox.shrink();
    }

    final thumb = post.thumbImageUrl;
    final full = post.imageUrl;
    if (thumb == null || full == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          showDialog(
            context: context,
            builder: (context) => Dialog(
              child: _FullImageViewer(
                url: full,
                onDownload: () => _download(context, full),
              ),
            ),
          );
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: thumb,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (context, url, error) => Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('缩略图加载失败：$error'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _FullImageViewer extends StatefulWidget {
  final String url;
  final VoidCallback onDownload;

  const _FullImageViewer({required this.url, required this.onDownload});

  @override
  State<_FullImageViewer> createState() => _FullImageViewerState();
}

final class _FullImageViewerState extends State<_FullImageViewer> {
  var _nonce = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              tooltip: '刷新',
              onPressed: () => setState(() => _nonce++),
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '下载原图',
              onPressed: widget.onDownload,
              icon: const Icon(Icons.download_outlined),
            ),
            IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        Flexible(
          child: InteractiveViewer(
            minScale: 0.2,
            maxScale: 8,
            child: CachedNetworkImage(
              imageUrl: '${widget.url}${widget.url.contains('?') ? '&' : '?'}_=$_nonce',
              fit: BoxFit.contain,
              placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
              errorWidget: (context, url, error) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('大图加载失败：$error'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _formatToSeconds(DateTime dt) {
  final local = dt.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  final ss = local.second.toString().padLeft(2, '0');
  return '$y-$m-$d $hh:$mm:$ss';
}

final class ThreadPage extends StatefulWidget {
  final int mainPostId;
  final String? title;
  final int? flashPostId;

  const ThreadPage({
    super.key,
    required this.mainPostId,
    this.title,
    this.flashPostId,
  });

  @override
  State<ThreadPage> createState() => _ThreadPageState();
}

final class _ThreadPageState extends State<ThreadPage> {
  final _subStore = const SubscriptionStore();
  bool _subWorking = false;

  bool _loading = true;
  Object? _error;

  bool _onlyPo = false;
  String? _poUserHash;

  int _page = 1;
  bool _loadingPage = false;
  bool _hasMore = true;
  final ItemScrollController _itemScroll = ItemScrollController();
  final ItemPositionsListener _itemPositions = ItemPositionsListener.create();

  // Persist/restore reading progress per thread (anchor postId + alignment).
  static const String _kProgressAnchorPostIdPrefix =
    'xdnmb.threadProgress.anchorPostId.';
  static const String _kProgressTopIndexHintPrefix =
    'xdnmb.threadProgress.topIndexHint.';
  // Legacy key: old pixel offset.
  static const String _kLegacyScrollOffsetPrefix = 'xdnmb.threadScrollOffset.';
  DateTime _lastScrollPersistAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _scrollPersistScheduled;

  // Reply jump target (from post history).
  int? _jumpTargetPostId;
  int? _flashingPostId; // The post currently being flash-highlighted
  int _flashPhase = 0; // increments to trigger rebuilds during flashing
  bool _showBackToTop = false;

  // Flattened view: first main post then replies.
  final _posts = <api.PostBase>[];

  @override
  void initState() {
    super.initState();
    final flash = widget.flashPostId;
    // Guard: if flashPostId equals mainPostId, it's stale data from old code
    // that incorrectly stored the thread head id instead of the reply id.
    if (flash != null && flash != widget.mainPostId) {
      _jumpTargetPostId = flash;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPage(1));
  }

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

  void _persistReadingProgress() {
    if (!mounted) return;
    if (_posts.isEmpty) return;

    final positions = _itemPositions.itemPositions.value;
    if (positions.isEmpty) return;

    final visible = positions
        .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
        .toList(growable: false);
    if (visible.isEmpty) return;

    visible.sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
    final first = visible.first;
    final idx = first.index.clamp(0, _posts.length - 1);
    final postId = _posts[idx].id;

    final prefs = context.read<AppState>().prefs;
    final postIdKey = '$_kProgressAnchorPostIdPrefix${widget.mainPostId}';
  final indexHintKey =
    '$_kProgressTopIndexHintPrefix${widget.mainPostId}';
    // ignore: discarded_futures
    prefs.setThreadProgressAnchorPostId(postIdKey, postId);
    // ignore: discarded_futures
  prefs.setThreadProgressTopIndexHint(indexHintKey, idx);
  }

  void _schedulePersistReadingProgress() {
    if (!mounted) return;
    if (_posts.isEmpty) return;

    final now = DateTime.now();
    final sinceLast = now.difference(_lastScrollPersistAt);
    if (sinceLast >= const Duration(milliseconds: 500)) {
      _lastScrollPersistAt = now;
      _persistReadingProgress();
      return;
    }

    if (_scrollPersistScheduled != null) return;
    final delay = const Duration(milliseconds: 500) - sinceLast;
    _scrollPersistScheduled = Future<void>.delayed(delay, () {
      _scrollPersistScheduled = null;
      if (!mounted) return;
      _lastScrollPersistAt = DateTime.now();
      _persistReadingProgress();
    });
  }

  @override
  void dispose() {
    _persistReadingProgress();
    super.dispose();
  }

  /// On first page load, if no reply-jump target set, restore saved progress.
  Future<void> _maybeRestoreReadingProgress() async {
    if (_jumpTargetPostId != null) return;
    final prefs = context.read<AppState>().prefs;

    final postIdKey = '$_kProgressAnchorPostIdPrefix${widget.mainPostId}';
  final indexHintKey =
    '$_kProgressTopIndexHintPrefix${widget.mainPostId}';
    final savedPostId = await prefs.getThreadProgressAnchorPostId(postIdKey);
  final savedIndexHint = await prefs.getThreadProgressTopIndexHint(indexHintKey);

    // Legacy fallback: old pixel offset. We'll try to approximate to an item.
    final legacyOffsetKey = '$_kLegacyScrollOffsetPrefix${widget.mainPostId}';
    final legacyOffset = await prefs.getThreadScrollOffset(legacyOffsetKey);

    if (!mounted) return;

    if (savedPostId != null) {
      _jumpTargetPostId = savedPostId;
      // If the post gets deleted or is unavailable even after loading all pages,
      // fall back to a nearby index.
      _jumpIndexHint = savedIndexHint;
      return;
    }

    // If only legacy offset exists, best-effort: jump near top.
    // Without item heights, we can't map pixels->index precisely. We approximate
    // by using a coarse item height guess but immediately rewrite progress in
    // new format once user scrolls.
    if (legacyOffset != null && _posts.isNotEmpty) {
      final approxIndex = (legacyOffset / 220.0).floor().clamp(0, _posts.length - 1);
      final postId = _posts[approxIndex].id;
      _jumpTargetPostId = postId;
    _jumpIndexHint = approxIndex;
    }
  }

  int? _jumpIndexHint;

  void _scrollToPostId(
    int postId, {
    required double alignment,
    required bool flash,
  }) {
    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx < 0) return;
  if (!_itemScroll.isAttached) return;
    final f = _itemScroll.scrollTo(
      index: idx,
      alignment: alignment,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
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

  /// Try to jump to target, or auto-load next page if not found yet.
  void _tryJumpOrLoadMore() {
    final id = _jumpTargetPostId;
    if (id == null) return;
    final idx = _posts.indexWhere((p) => p.id == id);
    if (idx >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
  if (!mounted) return;
  final isFromReplyHistory = widget.flashPostId != null;
  _jumpTargetPostId = null;
  _jumpIndexHint = null;
  _scrollToPostId(id, alignment: 0.0, flash: isFromReplyHistory);
      });
    } else if (_hasMore) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) {
          await _loadPage(_page + 1);
          // After loading more pages, try again to jump to target
          if (mounted) {
            _tryJumpOrLoadMore();
          }
        }
      });
    } else {
      // Post not found and no more pages — fall back to index hint if any.
      final hint = _jumpIndexHint;
      _jumpTargetPostId = null;
      _jumpIndexHint = null;
      if (hint == null || _posts.isEmpty) return;
      final fallbackIndex = hint.clamp(0, _posts.length - 1);
      if (!_itemScroll.isAttached) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_itemScroll.isAttached) {
            _itemScroll.jumpTo(index: fallbackIndex, alignment: 0.0);
          }
        });
      } else {
        _itemScroll.jumpTo(index: fallbackIndex, alignment: 0.0);
      }
    }
  }

  void _onScroll() {
    // Back to top button: show when first visible index is deep enough.
    final positions = _itemPositions.itemPositions.value;
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

    // Debounced persist.
    _schedulePersistReadingProgress();

    final app = context.read<AppState>();
    if (!app.autoLoadOnScroll) return;
    if (!_hasMore || _loadingPage) return;
    // Auto-load when the last visible item is close to the end.
    final lastVisible = positions
        .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
        .fold<int?>(null, (max, p) {
      if (max == null) return p.index;
      return p.index > max ? p.index : max;
    });
    if (lastVisible != null && lastVisible >= _posts.length - 4) {
      _loadPage(_page + 1);
    }
  }

  Future<void> _loadPage(int page, {bool forceRefresh = false}) async {
    if (_loadingPage) return;
    setState(() {
      if (page == 1 || forceRefresh) {
        _loading = true;
        _error = null;
      }
      _loadingPage = true;
    });

  try {
  final repo = context.read<AppState>().repo;
    final thread = _onlyPo
      ? await repo.getOnlyPoThreadPage(widget.mainPostId, page,
        forceRefresh: forceRefresh)
      : await repo.getThreadPage(widget.mainPostId, page,
        forceRefresh: forceRefresh);

    _poUserHash ??= thread.mainPost.userHash;

      setState(() {
        if (page == 1 || forceRefresh) {
          // Clear existing posts when loading first page or forcing refresh
          _posts
            ..clear()
            ..add(thread.mainPost)
            ..addAll(thread.replies);
        } else {
          _posts.addAll(thread.replies);
        }
        _page = page;
        _hasMore = thread.replies.isNotEmpty;
        _loading = false;
        _loadingPage = false;
      });

      // Restore scroll position once after first data load, but not when jumping to page 1 explicitly
      if (page == 1) {
  await _maybeRestoreReadingProgress();
      }

      // Try to jump to target post (flash or restored position).
      if (_jumpTargetPostId != null) {
        // For multi-page loading, we need to wait until all necessary pages are loaded
        // before trying to scroll to the target position
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _tryJumpOrLoadMore();
          }
        });
      }
    } catch (e) {
      setState(() {
        _error = e;
        _loading = false;
        _loadingPage = false;
      });
    }
  }

  Future<void> _jumpToPage() async {
    final controller = TextEditingController(text: '$_page');
    final page = await showDialog<int>(
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
            await _loadPage(last, forceRefresh: true);
            // After loading last page, scroll to bottom.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (!_itemScroll.isAttached) return;
              if (_posts.isEmpty) return;
              _itemScroll.jumpTo(index: _posts.length - 1, alignment: 1);
            });
          } else {
            // If maxPage is not available, load the current page and scroll to bottom
            await _loadPage(_page);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (!_itemScroll.isAttached) return;
              if (_posts.isEmpty) return;
              _itemScroll.jumpTo(index: _posts.length - 1, alignment: 1);
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
          // Clear jump target to prevent scrolling to saved position
          _jumpTargetPostId = null;
        });
        await _loadPage(page, forceRefresh: true);
        // Ensure scroll to top after loading
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!_itemScroll.isAttached) return;
          _itemScroll.jumpTo(index: 0, alignment: 0);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
    title: Text(() {
      final t = widget.title?.trim();
      if (t == null || t.isEmpty || t == '无标题') return '串';
      return t;
    }()),
        actions: [
          IconButton(
            tooltip: '刷新页面',
            onPressed: () async {
              await _loadPage(1, forceRefresh: true);
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
              setState(() {
                _onlyPo = !_onlyPo;
              });
              await _loadPage(1, forceRefresh: true);
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
      floatingActionButton: Column(
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
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => ComposerPage.reply(
              mainPostId: widget.mainPostId,
            ),
          );
          if (ok == true) {
            await _loadPage(1, forceRefresh: true);
            if (_itemScroll.isAttached) {
              _itemScroll.jumpTo(index: 0, alignment: 0);
            }
          }
        },
        icon: const Icon(Icons.reply_outlined),
        label: const Text('回串'),
      ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('加载失败：$_error'),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: () => _loadPage(1, forceRefresh: true),
                          child: const Text('重试')),
                    ],
                  ),
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    // Best-effort: still use item positions for progress.
                    if (n is ScrollUpdateNotification ||
                        n is UserScrollNotification) {
                      _onScroll();
                    }
                    return false;
                  },
                  child: ScrollablePositionedList.separated(
                    itemScrollController: _itemScroll,
                    itemPositionsListener: _itemPositions,
                    itemCount: _posts.length + 1,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (index == _posts.length) {
                        if (!_hasMore) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Center(
                              child: Text(
                                '没有更多了',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: FilledButton.tonal(
                              onPressed: _loadingPage
                                  ? null
                                  : () => _loadPage(_page + 1),
                              child: Text(
                                  _loadingPage ? '加载中…' : '点击加载更多'),
                            ),
                          ),
                        );
                      }

                      final p = _posts[index];
                      final shouldFlash =
                          _flashingPostId != null && p.id == _flashingPostId;
                    final flashColor = Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.14);

                      final targetT = shouldFlash
                          ? ((_flashPhase.isEven) ? 1.0 : 0.0)
                          : 0.0;
                    return TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0.0, end: targetT),
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeInOut,
                      builder: (context, t, child) {
                        return Container(
                          color: Color.lerp(null, flashColor, t),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: child,
                        );
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (index == 0 && p.isSage == true) ...[
                            Text(
                              'SAGE ▼',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.error,
                                      fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _cookieUserHash(p),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                        color: p.isAdmin
                          ? Theme.of(context)
                            .colorScheme
                            .error
                          : Theme.of(context)
                            .colorScheme
                            .primary,
                        fontWeight: p.isAdmin
                          ? FontWeight.w700
                          : null),
                                      ),
                                    ),
                                    if (_poUserHash != null &&
                                        p.userHash == _poUserHash) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'PO',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onPrimary,
                                                  fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Center(
                                  child: Text(
                                    _formatToSeconds(p.postTime),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: () async {
                                      final ok = await showDialog<bool>(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (context) => ComposerPage.reply(
                                          mainPostId: widget.mainPostId,
                                          initialContent: '>>No.${p.id}\n',
                                        ),
                                      );
                                      if (ok == true) {
                                        await _loadPage(1, forceRefresh: true);
                                        if (_itemScroll.isAttached) {
                                          _itemScroll.jumpTo(index: 0, alignment: 0);
                                        }
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      child: Text(
                                        'No.${p.id}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _PostImage(post: p),
                          PostContent(text: p.content, postId: p.id),
                        ],
                      ),
                    );
                    },
                  ),
                ),
        );
  }
}

String _cookieUserHash(api.PostBase p) {
  final n = p.userHash.trim();
  return n.isEmpty ? '无名氏' : n;
}
