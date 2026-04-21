import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/post_history_store.dart';
import '../../app/app_state.dart';
import '../../app/composer_controller.dart';
import '../../app/settings_controller.dart';
import '../widgets/cdn_fallback_image.dart';
import '../widgets/list_preview.dart';
import '../widgets/thread_list_item.dart';
import 'thread_page.dart';

final class PostHistoryPage extends StatefulWidget {
  const PostHistoryPage({super.key});

  @override
  State<PostHistoryPage> createState() => _PostHistoryPageState();
}

final class _PostHistoryPageState extends State<PostHistoryPage> {
  final _store = PostHistoryStore();
  late Future<List<PostHistoryEntry>> _future;

  /// Cached best-effort fetched thread heads for reply entries.
  ///
  /// Key: mainPostId
  final Map<int, PostHistoryEntry> _threadHeadCache = <int, PostHistoryEntry>{};

  Future<void> _confirmRemoveAt(int storeIndex, PostHistoryEntry e) async {
    final where = e.isReply
        ? '回串 No.${e.mainPostId ?? '-'}'
        : '发串 fid=${e.forumId ?? '-'}';
    final title = (e.title == null || e.title!.trim().isEmpty)
        ? where
        : '${e.title!.trim()}（$where）';

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除记录？'),
        content: Text('将移除：$title'),
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
    await _store.removeAt(storeIndex);
    _reload();
  }

  @override
  void initState() {
    super.initState();
    _future = _store.readAll();
  }

  void _reload() {
    _threadHeadCache.clear();
    final next = _store.readAll();
    setState(() {
      _future = next;
    });
  }

  Future<PostHistoryEntry?> _ensureThreadHeadFor(PostHistoryEntry reply) async {
    final tid = reply.mainPostId;
    if (tid == null) return null;

    // Already has enough info.
    final hasLocal = (reply.threadContent?.trim().isNotEmpty == true) ||
        (reply.threadUserHash?.trim().isNotEmpty == true) ||
        (reply.threadThumbImageUrl?.trim().isNotEmpty == true);
    if (hasLocal) return reply;

    final cached = _threadHeadCache[tid];
    if (cached != null) return cached;

    try {
      // Use a lightweight fetch: thread page #1.
      final head = await (context.read<AppState>()).repo
          .getThreadPage(tid, 1, forceRefresh: false);

      final mainPost = head.mainPost;
      final filled = PostHistoryEntry(
        isReply: reply.isReply,
        content: reply.content,
        postedAt: reply.postedAt,
        mainPostId: reply.mainPostId,
        replyPostId: reply.replyPostId,
        forumId: reply.forumId,
        title: reply.title,
        threadUserHash:
            mainPost.userHash.trim().isEmpty ? null : mainPost.userHash.trim(),
        threadIsAdmin: mainPost.isAdmin,
        threadPostTime: mainPost.postTime,
        threadReplyCount: mainPost.replyCount,
  threadThumbImageUrl: null,
        threadContent: mainPost.content,
      );
      _threadHeadCache[tid] = filled;
      return filled;
    } catch (_) {
      // ignore: best-effort only
      return null;
    }
  }

  Future<void> _showDebugDump() async {
    final text = await _store.debugDump();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发言历史（调试导出）'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: SelectableText(text),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!context.mounted) return;
              Navigator.of(context).pop();
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(content: Text('已复制到剪贴板')),
              );
            },
            child: const Text('复制并关闭'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('发言历史'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '发串'),
              Tab(text: '回串'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '导出调试信息',
              onPressed: _showDebugDump,
              icon: const Icon(Icons.bug_report_outlined),
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
        body: FutureBuilder<List<PostHistoryEntry>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('加载失败：${snap.error}'));
            }

            final all = snap.data ?? const [];
            final newThreads = <({PostHistoryEntry e, int index})>[];
            final replies = <({PostHistoryEntry e, int index})>[];
            for (var i = 0; i < all.length; i++) {
              final e = all[i];
              if (e.isReply) {
                replies.add((e: e, index: i));
              } else {
                newThreads.add((e: e, index: i));
              }
            }


      Widget buildThreadList(
        List<({PostHistoryEntry e, int index})> items) {
              if (items.isEmpty) {
                return const Center(child: Text('（空）'));
              }
              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final e = items[i].e;
                  final storeIndex = items[i].index;

          final where = e.isReply
            ? '回串 No.${e.mainPostId ?? '-'}'
            : '发串 fid=${e.forumId ?? '-'}';
                  final mainTitle = (e.title == null || e.title!.trim().isEmpty)
                      ? null
                      : e.title!.trim();

          final hasThreadHead = e.mainPostId != null &&
            (e.threadContent?.trim().isNotEmpty == true ||
              e.threadUserHash?.trim().isNotEmpty == true ||
              e.threadThumbImageUrl?.trim().isNotEmpty == true);

                  Widget buildMainCard() {
                    final card = ThreadListItem(
                      thumbUrl: null,
                      title: mainTitle,
                      content: e.content,
                      cookie: e.isReply ? '[reply]$where' : where,
                      time: e.postedAt,
                      onTap: () {
                        // New thread entry: jump to thread head.
                        if (!e.isReply && e.mainPostId != null) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => ThreadPage(
                                mainPostId: e.mainPostId!,
                                title: e.title,
                              ),
                            ),
                          );
                          return;
                        }

                        // Reply entry: jump to reply position if possible.
                        if (e.isReply && e.mainPostId != null) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => ThreadPage(
                                mainPostId: e.mainPostId!,
                                title: e.title,
                                flashPostId: e.replyPostId,
                                initialPage: e.replyPage,
                              ),
                            ),
                          );
                          return;
                        }

                        // Fallback: open composer (rare).
                        if (!e.isReply && e.forumId != null) {
                          final composer = context.read<ComposerController>();
                          composer.openPanel(
                            ComposerArgs(
                              mode: ComposerMode.newThread,
                              forumId: e.forumId!,
                              initialContent: e.content,
                            ),
                          );
                        }
                      },
                    );

                    // Make replies visually distinct: indent + left color bar.
                    if (!e.isReply) return card;

                    final cs = Theme.of(context).colorScheme;
                    return Padding(
                      padding: const EdgeInsets.only(left: 18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: 4,
                            decoration: BoxDecoration(
                              color: cs.error.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: card),
                        ],
                      ),
                    );
                  }

                  Widget buildThreadHeadCard() {
                    final tid = e.mainPostId;
                    if (tid == null) return const SizedBox.shrink();

                    final rawTitle = e.title?.trim() ?? '';
                    final title = rawTitle.isEmpty || rawTitle == '无标题'
                        ? null
                        : rawTitle;

                    return Opacity(
                      opacity: 0.92,
                      child: ThreadListItem(
                        thumbUrl: e.threadThumbImageUrl,
                        title: title,
                        content: (e.threadContent == null ||
                                e.threadContent!.trim().isEmpty)
                            ? 'No.$tid'
                            : e.threadContent!.trim(),
                        cookie: e.threadUserHash?.trim() ?? '',
                        time: e.threadPostTime ?? e.postedAt,
                        isAdmin: e.threadIsAdmin ?? false,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => ThreadPage(
                                mainPostId: tid,
                                title: title,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }

                  // For "new thread" entries, user expectation is to see the
                  // thread head card (same as normal forum list).
                  if (!e.isReply) {
                    return InkWell(
                      onSecondaryTap: () {
                        // ignore: discarded_futures
                        _confirmRemoveAt(storeIndex, e);
                      },
                      child: hasThreadHead
                          ? buildThreadHeadCard()
                          : ThreadListItem(
                              thumbUrl: null,
                              title: mainTitle,
                              content: e.content,
                              cookie: where,
                              time: e.postedAt,
                              onTap: () {
                                final tid = e.mainPostId;
                                if (tid == null) return;
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => ThreadPage(
                                      mainPostId: tid,
                                      title: e.title,
                                    ),
                                  ),
                                );
                              },
                            ),
                    );
                  }

                  // Reply entries: always show the reply record itself. The
                  // thread head is best-effort (local cache or fetched).
                  return InkWell(
                    onSecondaryTap: () {
                      // ignore: discarded_futures
                      _confirmRemoveAt(storeIndex, e);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        buildMainCard(),
                        if (e.isReply && e.mainPostId != null) ...[
                          const Divider(height: 1),
                          if (hasThreadHead)
                            buildThreadHeadCard()
                          else
                            FutureBuilder<PostHistoryEntry?>(
                              key: ValueKey<int>(e.mainPostId!),
                              future: _ensureThreadHeadFor(e),
                              builder: (context, snap) {
                                final filled = snap.data;
                                if (filled == null) {
                                  // Minimal fallback: show No.tid card so user
                                  // can still tap to open the thread.
                                  final tid = e.mainPostId;
                                  if (tid == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return Opacity(
                                    opacity: 0.86,
                                    child: ThreadListItem(
                                      thumbUrl: null,
                                      title: null,
                                      content: 'No.$tid',
                                      cookie: '',
                                      time: e.postedAt,
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) => ThreadPage(
                                              mainPostId: tid,
                                              title: e.title,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                }

                                // Render the fetched head via the same helper.
                                return Opacity(
                                  opacity: 0.92,
                                  child: ThreadListItem(
                                    thumbUrl: filled.threadThumbImageUrl,
                                    title: (filled.title?.trim().isEmpty ??
                                            true)
                                        ? null
                                        : filled.title!.trim(),
                                    content:
                                        (filled.threadContent?.trim().isEmpty ??
                                                true)
                                            ? 'No.${filled.mainPostId}'
                                            : filled.threadContent!.trim(),
                                    cookie: filled.threadUserHash?.trim() ?? '',
                                    time: filled.threadPostTime ??
                                        filled.postedAt,
                                    isAdmin: filled.threadIsAdmin ?? false,
                                    onTap: () {
                                      final tid = filled.mainPostId;
                                      if (tid == null) return;
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => ThreadPage(
                                            mainPostId: tid,
                                            title: filled.title,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                        ],
                      ],
                    ),
                  );
                },
              );
            }

            Widget buildReplyList() {
              if (replies.isEmpty) {
                return const Center(child: Text('（空）'));
              }

              Widget buildReplyLine(
                  ({PostHistoryEntry e, int index}) item) {
                final e = item.e;
                final storeIndex = item.index;
                final tid = e.mainPostId;
                final target = e.replyPostId;
                final cs = Theme.of(context).colorScheme;
                final settings = context.watch<SettingsController>();
                final meta = Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant);

                final previewStyle = TextStyle(
                  fontSize: settings.contentFontSize,
                  height: settings.contentLineHeight,
                  fontFamily: settings.fontFamily.isEmpty ? null : settings.fontFamily,
                );

                String fmtTime(DateTime dt) {
                  final y = dt.year.toString().padLeft(4, '0');
                  final m = dt.month.toString().padLeft(2, '0');
                  final d = dt.day.toString().padLeft(2, '0');
                  final hh = dt.hour.toString().padLeft(2, '0');
                  final mm = dt.minute.toString().padLeft(2, '0');
                  final ss = dt.second.toString().padLeft(2, '0');
                  return '$y-$m-$d $hh:$mm:$ss';
                }

                return InkWell(
                  onTap: () {
                    if (tid == null) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ThreadPage(
                          mainPostId: tid,
                          title: e.title,
                          flashPostId: target,
                          initialPage: e.replyPage,
                        ),
                      ),
                    );
                  },
                  onLongPress: () {
                    // ignore: discarded_futures
                    _confirmRemoveAt(storeIndex, e);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Reply meta ──
                        Text.rich(
                          TextSpan(
                            style: meta,
                            children: [
                              TextSpan(
                                text: '回复',
                                style: meta?.copyWith(
                                  color: cs.error,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const TextSpan(text: '  '),
                              TextSpan(
                                text: fmtTime(e.postedAt.toLocal()),
                              ),
                              if (target != null) ...[
                                const TextSpan(text: '  '),
                                TextSpan(
                                  text: 'No.$target',
                                  style: meta?.copyWith(color: cs.primary),
                                ),
                              ],
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // ── Reply content ──
                        Text(
                          normalizeForListPreview(e.content.trim()),
                          maxLines: settings.previewMaxLines,
                          overflow: TextOverflow.ellipsis,
                          style: previewStyle,
                        ),
                        const SizedBox(height: 8),
                        // ── Parent thread (indented, gray) ──
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (e.threadThumbImageUrl != null &&
                                  e.threadThumbImageUrl!.trim().isNotEmpty) ...[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: CdnFallbackCachedNetworkImage(
                                    imageUrl: e.threadThumbImageUrl!,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      width: 48,
                                      height: 48,
                                      color: cs.surfaceContainerHighest,
                                      alignment: Alignment.center,
                                      child: const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    ),
                                    errorWidget: (context, url, error) => Container(
                                      width: 48,
                                      height: 48,
                                      color: cs.surfaceContainerHighest,
                                      child: const Icon(Icons.broken_image_outlined, size: 20),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text.rich(
                                      TextSpan(
                                        style: meta,
                                        children: [
                                          TextSpan(
                                            text: (e.threadUserHash
                                                            ?.trim()
                                                            .isNotEmpty ==
                                                        true)
                                                ? e.threadUserHash!.trim()
                                                : '无名氏',
                                            style: meta?.copyWith(
                                              color:
                                                  (e.threadIsAdmin ?? false)
                                                      ? cs.error
                                                      : cs.primary,
                                              fontWeight:
                                                  (e.threadIsAdmin ?? false)
                                                      ? FontWeight.w700
                                                      : null,
                                            ),
                                          ),
                                          if (e.threadPostTime != null) ...[
                                            const TextSpan(text: '  '),
                                            TextSpan(
                                                text: fmtTime(
                                                    e.threadPostTime!
                                                        .toLocal())),
                                          ],
                                          if (tid != null) ...[
                                            const TextSpan(text: '  '),
                                            TextSpan(
                                              text: 'No.$tid',
                                              style: meta?.copyWith(
                                                  color: cs.primary),
                                            ),
                                          ],
                                        ],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      normalizeForListPreview(
                                          e.threadContent?.trim() ??
                                              '（无内容）'),
                                      maxLines: settings.previewMaxLines,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.merge(previewStyle),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                itemCount: replies.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1),
                itemBuilder: (context, i) => buildReplyLine(replies[i]),
              );
            }

            return TabBarView(
              children: [
                buildThreadList(newThreads),
                buildReplyList(),
              ],
            );
          },
        ),
      ),
    );
  }
}
