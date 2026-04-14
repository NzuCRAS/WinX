import 'package:flutter/material.dart';

import '../../data/history_store.dart';
import '../widgets/thread_list_item.dart';
import 'thread_page.dart';

final class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

final class _HistoryPageState extends State<HistoryPage> {
  final _store = HistoryStore();
  late Future<List<HistoryEntry>> _future;

  Future<void> _confirmRemove(HistoryEntry e) async {
    final title = (e.title == null || e.title!.trim().isEmpty)
        ? null
        : e.title!.trim();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除历史？'),
        content: Text('将移除：${title ?? 'No.${e.threadId}'}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _store.remove(e.threadId);
    _reload();
  }

  @override
  void initState() {
    super.initState();
    _future = _store.readAll();
  }

  void _reload() {
    setState(() => _future = _store.readAll());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '清空',
            onPressed: () async {
              await _store.clear();
              _reload();
            },
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: FutureBuilder<List<HistoryEntry>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('加载失败：${snap.error}'));
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return const Center(child: Text('（空）'));
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final e = items[index];
        final rawTitle = e.title?.trim() ?? '';
        final title = rawTitle.isEmpty || rawTitle == '无标题'
          ? null
          : rawTitle;

              return InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) =>
                          ThreadPage(mainPostId: e.threadId, title: e.title),
                    ),
                  );
                },
                onSecondaryTap: () {
                  // ignore: discarded_futures
                  _confirmRemove(e);
                },
                child: ThreadListItem(
          thumbUrl: e.thumbImageUrl,
                  title: title,
          content: (e.content == null || e.content!.trim().isEmpty)
            ? 'No.${e.threadId}'
            : e.content!.trim(),
          cookie: e.userHash?.trim() ?? '',
          time: e.postTime ?? e.visitedAt,
          isAdmin: e.isAdmin ?? false,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
