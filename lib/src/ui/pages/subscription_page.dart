import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xdnmb_api/xdnmb_api.dart' as api;

import '../../app/app_state.dart';
import '../../data/subscription_store.dart';
import '../widgets/thread_list_item.dart';
import 'thread_page.dart';

final class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

final class _SubscriptionPageState extends State<SubscriptionPage> {
  final _store = const SubscriptionStore();

  // Doc: JSON /feed returns at most 10 items per page.
  static const int _pageSize = 10;

  final _feedIdCtrl = TextEditingController();
  String? _loadedFeedId;

  bool _loading = false;
  Object? _error;
  List<api.Feed> _items = const [];
  int _page = 1;
  bool _hasMore = true;

  final ScrollController _scrollController = ScrollController();
  bool _loadingMore = false;
  final Set<int> _seenIds = <int>{};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // ignore: discarded_futures
    Future.microtask(_init);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_loading || _loadingMore || !_hasMore) return;

    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 320) {
      // ignore: discarded_futures
      _loadMore();
    }
  }

  Future<void> _init() async {
    final id = await _store.readFeedId();
    if (!mounted) return;
    setState(() {
      _loadedFeedId = id;
      _feedIdCtrl.text = id;
    });
    await _refresh();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _feedIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveFeedId() async {
    await _store.writeFeedId(_feedIdCtrl.text);
    final id = await _store.readFeedId();
    if (!mounted) return;
    setState(() => _loadedFeedId = id);
    await _refresh();
  }

  Future<void> _refresh() async {
    final id = await _store.readFeedId();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
      _hasMore = true;
      _items = const [];
    });

    _seenIds
      ..clear()
      ..addAll(_items.map((e) => e.id));

    try {
      final repo = context.read<AppState>().repo;
      final data = await repo.getFeed(id, page: 1);
      if (!mounted) return;

      final unique = <api.Feed>[];
      for (final f in data) {
        if (_seenIds.add(f.id)) unique.add(f);
      }
      setState(() {
        _items = unique;
        _loading = false;
        _hasMore = data.length >= _pageSize;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final id = await _store.readFeedId();
    if (!mounted) return;
    setState(() {
      _loadingMore = true;
      _error = null;
    });
    try {
      final repo = context.read<AppState>().repo;
      final nextPage = _page + 1;
      final data = await repo.getFeed(id, page: nextPage);
      if (!mounted) return;

      final unique = <api.Feed>[];
      for (final f in data) {
        if (_seenIds.add(f.id)) unique.add(f);
      }
      setState(() {
        _page = nextPage;
        _items = [..._items, ...unique];
        _hasMore = data.length >= _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loadingMore = false;
      });
    }
  }

  Future<void> _confirmUnsubscribe(api.Feed f) async {
    final title = f.title.trim().isEmpty || f.title == '无标题'
        ? null
        : f.title.trim();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消订阅？'),
        content: Text('将从订阅流移除：${title ?? 'No.${f.id}'}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('不取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('取消订阅'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final feedId = await _store.readFeedId();
    if (!mounted) return;
    try {
      final repo = context.read<AppState>().repo;
      await repo.deleteFeed(feedId, f.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已取消订阅：No.${f.id}（ID=$feedId）')),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('取消订阅失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('订阅'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _feedIdCtrl,
                    decoration: InputDecoration(
                      labelText: '订阅ID（uuid）',
                      hintText: SubscriptionStore.defaultFeedId,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _saveFeedId(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _loading ? null : _saveFeedId,
                  child: const Text('保存'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _error != null
                  ? ListView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('加载失败：$_error'),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: _loading ? null : _refresh,
                                  child: const Text('重试'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
          : ListView.separated(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _items.length + 1,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (index == _items.length) {
                            final isLoading = _loading || _loadingMore;
                            if (_items.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.all(16),
                                child: Center(
                                  child: Text(
                                    isLoading ? '加载中…' : '（空）',
                                    style: TextStyle(color: cs.onSurfaceVariant),
                                  ),
                                ),
                              );
                            }

                            if (!_hasMore) {
                              return Padding(
                                padding: const EdgeInsets.all(16),
                                child: Center(
                                  child: Text(
                                    '没有更多了',
                                    style: TextStyle(color: cs.onSurfaceVariant),
                                  ),
                                ),
                              );
                            }

                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: Center(
                                child: FilledButton.tonal(
                                  onPressed: isLoading ? null : _loadMore,
                                  child: Text(isLoading ? '加载中…' : '点击加载更多'),
                                ),
                              ),
                            );
                          }

                          final f = _items[index];
                          final title =
                              f.title.trim().isEmpty || f.title == '无标题'
                                  ? null
                                  : f.title.trim();
                          final thumbUrl = f.thumbImageUrl;

                          return ThreadListItem(
                            thumbUrl: thumbUrl,
                            isSage: f.isSage,
                            title: title,
                            content: f.content,
                            cookie: f.userHash,
                            time: f.postTime,
                            isAdmin: f.isAdmin,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => ThreadPage(
                                      mainPostId: f.id, title: title),
                                ),
                              );
                            },
                            onSecondaryTap: () {
                              // ignore: discarded_futures
                              _confirmUnsubscribe(f);
                            },
                          );
                        },
                      ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _loadedFeedId == null
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Text(
                '当前订阅ID：${_loadedFeedId!}',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
    );
  }
}
