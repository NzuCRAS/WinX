import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xdnmb_api/xdnmb_api.dart' as api;

import '../../app/app_state.dart';
import 'thread_page.dart';
import 'start_page.dart';
import 'history_page.dart';
import 'my_posts_page.dart';
import 'subscription_page.dart';
import 'user_manage_page.dart';
import 'settings_page.dart';
import 'composer_page.dart';
import '../../data/history_store.dart';
import '../../data/forum_groups.dart';
import '../../data/local_prefs.dart';
import '../../data/common_forums_store.dart';
import '../widgets/post_content.dart';
import '../widgets/thread_list_item.dart';

final _fontTagRe = RegExp(
  r'<font\s+color="([^"]+)">([\s\S]*?)<\/font>',
  caseSensitive: false,
);

final class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

final class _HomePageState extends State<HomePage> {
  api.ForumList? _forumList;
  Object? _error;
  bool _loading = true;

  int? _selectedForumId;
  String? _selectedForumName;
  bool _selectedIsTimeline = false;

  int _sectionIndex = 0; // 0=start, 1=forum, 2=sub, 3=history, 4=myPosts, 5=user
  bool _sidebarExpanded = true;

  // paging
  int _page = 1;
  bool _loadingPage = false;
  bool _hasMore = true;
  final List<api.ForumThread> _threads = [];
  final ScrollController _scrollController = ScrollController();

  bool _announcementChecked = false;

  // Random cover (homepage hero)
  Uri? _randomCoverUrl;
  bool _randomCoverLoading = false;
  Object? _randomCoverError;
  int _randomCoverNonce = 0;

  final _historyStore = HistoryStore();
  final _commonForumsStore = CommonForumsStore();

  // In-memory cache for fast sidebar rendering.
  final Set<int> _commonForumIds = <int>{};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadForumList());
  WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowAnnouncementOnce());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshRandomCover());
  }

  Future<void> _refreshRandomCover() async {
    if (_randomCoverLoading) return;
    setState(() {
      _randomCoverLoading = true;
      _randomCoverError = null;
    });

  try {
      final repo = context.read<AppState>().repo;
      final url = await repo.getRandomCoverUrl();
      if (!mounted) return;
      setState(() {
        _randomCoverUrl = url;
    _randomCoverNonce++;
        _randomCoverLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _randomCoverError = e;
        _randomCoverLoading = false;
      });
    }
  }

  Future<void> _refreshCurrentSection() async {
    // Always best-effort refresh the random cover.
    // ignore: discarded_futures
    _refreshRandomCover();

    // 0=start, 1=forum, 2=sub, 3=history, 4=myPosts, 5=user
    if (_sectionIndex == 1) {
      await _refreshThreads();
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      return;
    }

    // Refresh forum list (also refreshes sidebar common forums cache).
    await _loadForumList();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingPage) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _loadNextPage();
    }
  }

  Future<void> _loadForumList() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final app = context.read<AppState>();
    try {
      final list = await app.repo.getForumList();

      // getForumList() 里 id<0 的时间线条目通常只有一个（例如 -1: "时间线"），
      // 真正的子时间线（综合线/创作线/...）需要从 getTimelineList() 单独获取。
      List<api.Timeline>? timelines = list.timelineList;
      try {
        timelines = await app.repo.getTimelineList();
      } catch (_) {
        // ignore; fallback to list.timelineList
      }

      final mergedList = api.ForumList(list.forumGroupList, list.forumList, timelines);
      setState(() {
        _forumList = mergedList;
        _loading = false;
      });

  // ignore: discarded_futures
  _loadCommonForums();

      // auto select first forum
      if (_selectedForumId == null && list.forumList.isNotEmpty) {
        await _selectForum(list.forumList.first);
      }
    } catch (e) {
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadCommonForums() async {
    try {
      final all = await _commonForumsStore.readAll();
      if (!mounted) return;
      setState(() {
        _commonForumIds
          ..clear()
          ..addAll(all.map((e) => e.forumId));
      });
    } catch (_) {
      // ignore
    }
  }

  Future<void> _toggleCommonForum(api.Forum forum) async {
    final isCommon = _commonForumIds.contains(forum.id);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isCommon ? '移除常用' : '加入常用'),
        content: Text(
          isCommon
              ? '确定将“${_normalizeForListPreview(forum.showName)}”从常用中移除吗？'
              : '确定将“${_normalizeForListPreview(forum.showName)}”加入常用吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    if (isCommon) {
      await _commonForumsStore.remove(forum.id);
    } else {
      await _commonForumsStore.add(
        forumId: forum.id,
        showName: forum.showName,
      );
    }
    await _loadCommonForums();
  }

  Future<void> _selectForum(api.Forum forum) async {
    setState(() {
      _selectedForumId = forum.id;
  _selectedForumName = _normalizeForListPreview(forum.showName);
  _selectedIsTimeline = forum.forumGroupId == -1;
      _page = 1;
      _threads.clear();
      _hasMore = true;
      _loadingPage = false;
    });
    await _loadPage(1);
  }

  /// Parse forum names that contain simple HTML-like tags from API, e.g.
  /// 任天堂<font color="DeepSkyBlue">N</font><font color="red">S</font>
  ///
  /// We only support <font color="...">text</font> here.
  /// Unknown colors fall back to default text style.
  /// Inline newlines/spaces are preserved, but we still apply list preview
  /// normalization to avoid multi-line glitches.
  /// Inline tags are not nested in current API usage.
  /// Inline spans are clamped by the widget's maxLines/overflow.
  /// Inline styles are local; parent style sets base color.
  /// Inline text is normalized via _normalizeForListPreview.
  ///
  /// Return value is suitable for Text.rich().
  TextSpan _parseForumNameToSpan(
    BuildContext context,
    String raw,
    TextStyle? baseStyle,
  ) {
  // The API sometimes returns forum names with newlines and spaces between
  // tags, e.g.
  // 任天堂<font ...>N</font>\n <font ...>S</font>
  // We normalize list preview first, then collapse whitespace between tags
  // so the regex can see a continuous string.
  var normalizedRaw = _normalizeForListPreview(raw);
  normalizedRaw = normalizedRaw.replaceAll(RegExp(r'\n\s*'), '');
    final matches = _fontTagRe.allMatches(normalizedRaw).toList(growable: false);
    if (matches.isEmpty) {
      return TextSpan(text: normalizedRaw, style: baseStyle);
    }

    Color? colorFromSpec(String spec) {
      final s = spec.trim();
      if (s.isEmpty) return null;

      // #RRGGBB or #AARRGGBB
      if (s.startsWith('#')) {
        final hex = s.substring(1);
        if (hex.length == 6) {
          final v = int.tryParse(hex, radix: 16);
          return v == null ? null : Color(0xFF000000 | v);
        }
        if (hex.length == 8) {
          final v = int.tryParse(hex, radix: 16);
          return v == null ? null : Color(v);
        }
      }

      switch (s.toLowerCase()) {
        case 'deepskyblue':
          return const Color(0xFF00BFFF);
        case 'red':
          return Colors.red;
        case 'blue':
          return Colors.blue;
        case 'skyblue':
          return const Color(0xFF87CEEB);
        case 'dodgerblue':
          return const Color(0xFF1E90FF);
        default:
          return null;
      }
    }

    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final m in matches) {
      if (m.start > cursor) {
        spans.add(TextSpan(
          text: normalizedRaw.substring(cursor, m.start),
          style: baseStyle,
        ));
      }

      final colorSpec = m.group(1) ?? '';
      final innerText = m.group(2) ?? '';
      final c = colorFromSpec(colorSpec);
      spans.add(TextSpan(
        text: innerText,
        style: c == null ? baseStyle : baseStyle?.copyWith(color: c),
      ));

      cursor = m.end;
    }

    if (cursor < normalizedRaw.length) {
      spans.add(TextSpan(
        text: normalizedRaw.substring(cursor),
        style: baseStyle,
      ));
    }

    return TextSpan(style: baseStyle, children: spans);
  }

  Future<void> _loadPage(int page, {bool forceRefresh = false}) async {
    final app = context.read<AppState>();
    final forumId = _selectedForumId;
    if (forumId == null) return;

    setState(() {
      _loadingPage = true;
    });

    try {
    final items = _selectedIsTimeline
      ? await app.repo
        .getTimelinePage(forumId, page, forceRefresh: forceRefresh)
      : await app.repo
        .getForumPage(forumId, page, forceRefresh: forceRefresh);
      setState(() {
        if (page == 1) {
          _threads
            ..clear()
            ..addAll(items);
        } else {
          _threads.addAll(items);
        }
        _page = page;
        _hasMore = items.isNotEmpty; // conservative
        _loadingPage = false;
      });
    } catch (e) {
      setState(() {
        _loadingPage = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('加载失败：$e')));
      }
    }
  }

  Future<void> _loadNextPage() async {
    if (!_hasMore) return;
    await _loadPage(_page + 1);
  }

  Future<void> _refreshThreads() async {
    await _loadPage(1, forceRefresh: true);
  }

  // 主页不提供跳页：跳页仅在串内（ThreadPage）保留。

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

  return Scaffold(
      appBar: AppBar(
        title: Text('xdnmb（${_selectedForumName ?? '未选择'}）'),
        actions: [
          IconButton(
            tooltip: '刷新页面',
            onPressed: _refreshCurrentSection,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: '用户',
            onPressed: () => setState(() => _sectionIndex = 5),
            icon: Icon(
              context.watch<AppState>().hasCookie
                  ? Icons.verified_user_outlined
                  : Icons.person_outline,
            ),
          ),
          IconButton(
            tooltip: '岛规',
            onPressed: _openIslandRulesThread,
            icon: const Icon(Icons.rule_folder_outlined),
          ),
          IconButton(
            tooltip: '版规',
            onPressed: _selectedForumId == null ? null : _showForumRules,
            icon: const Icon(Icons.rule_outlined),
          ),
        ],
      ),
      floatingActionButton: (_sectionIndex == 1 &&
              _selectedForumId != null &&
              _selectedIsTimeline == false)
          ? FloatingActionButton.extended(
              onPressed: () async {
                final fid = _selectedForumId;
                if (fid == null) return;
                final ok = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => ComposerPage.newThread(
                    forumId: fid,
                    forumName: _selectedForumName,
                  ),
                );
                if (ok == true) {
                  await _loadPage(1, forceRefresh: true);
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(0);
                  }
                }
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('发串'),
            )
          : null,
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
                          onPressed: _loadForumList, child: const Text('重试')),
                    ],
                  ),
                )
              : Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: _sidebarExpanded ? 300 : 72,
                      child: _buildLeftSidebar(app),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildRightPane()),
                  ],
                ),
    );
  }

  Widget _buildLeftSidebar(AppState app) {
    final list = _forumList;
    if (list == null) return const SizedBox.shrink();

    final groups = buildSidebarGroups(list);
  final commonForums = list.forumList
    .where((f) => _commonForumIds.contains(f.id))
    .toList(growable: false);

    final theme = Theme.of(context);
    final baseTextStyle = theme.textTheme.bodyMedium?.copyWith(
          fontSize: app.contentFontSize,
          height: app.contentLineHeight,
          fontFamily: app.fontFamily,
        );

    return Material(
      color: theme.colorScheme.surface,
      child: DefaultTextStyle(
        style: baseTextStyle ?? const TextStyle(),
        child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (_sidebarExpanded)
                      InkWell(
                        onTap: () => setState(() => _sectionIndex = 0),
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset('assets/岛娘.png', width: 34, height: 34),
                      )
                    else
                      Expanded(
                        child: Center(
                          child: InkWell(
                            onTap: () => setState(() => _sectionIndex = 0),
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset('assets/岛娘.png', width: 34, height: 34),
                          ),
                        ),
                      ),
                    if (_sidebarExpanded) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _sectionIndex = 0),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              'xdnmb',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontFamily: app.fontFamily,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment:
                      _sidebarExpanded ? Alignment.centerRight : Alignment.center,
                  child: IconButton(
                    tooltip: _sidebarExpanded ? '收起侧栏' : '展开侧栏',
                    onPressed: () =>
                        setState(() => _sidebarExpanded = !_sidebarExpanded),
                    icon: Icon(_sidebarExpanded
                        ? Icons.chevron_left
                        : Icons.chevron_right),
                  ),
                ),
              ],
            ),
          ),
          if (!_sidebarExpanded)
            const SizedBox(height: 8)
          else ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
              alignment: WrapAlignment.start,
              spacing: 6,
              runSpacing: 6,
              children: [
                _SidebarAction(
                  icon: Icons.rss_feed_outlined,
                  label: '订阅',
                  expanded: _sidebarExpanded,
                  selected: _sectionIndex == 2,
                  onTap: () => setState(() => _sectionIndex = 2),
                ),
                _SidebarAction(
                  icon: Icons.history,
                  label: '历史',
                  expanded: _sidebarExpanded,
                  selected: _sectionIndex == 3,
                  onTap: () => setState(() => _sectionIndex = 3),
                ),
                _SidebarAction(
                  icon: Icons.edit_note_outlined,
                  label: '发言',
                  expanded: _sidebarExpanded,
                  selected: _sectionIndex == 4,
                  onTap: () => setState(() => _sectionIndex = 4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const SizedBox(height: 8),
          if (_sidebarExpanded) ...[
            if (commonForums.isNotEmpty)
              ExpansionTile(
                title: const Text('常用'),
                initiallyExpanded: true,
                children: [
                  for (final forum in commonForums)
                    InkWell(
                      onSecondaryTap: () => _toggleCommonForum(forum),
                      child: ListTile(
                        dense: true,
                        selected:
                            forum.id == _selectedForumId && _sectionIndex == 1,
                        trailing: const Icon(Icons.push_pin, size: 16),
                        title: Text.rich(
                          _parseForumNameToSpan(
                            context,
                            forum.showName,
                            baseTextStyle,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () async {
                          setState(() => _sectionIndex = 1);
                          await _selectForum(forum);
                        },
                      ),
                    ),
                ],
              ),
            ...groups.map((g) {
              if (g.title == '时间线') {
                final timelines = g.timelines ?? const <api.Timeline>[];
                String displayNameOf(api.Timeline t) {
                  final dn = t.displayName.trim();
                  return dn.isNotEmpty ? dn : t.name.trim();
                }

                final sortedTimelines = timelines.toList()
                  ..sort((a, b) => a.id.compareTo(b.id));

                return ExpansionTile(
                  title: const Text('时间线'),
                  initiallyExpanded: false,
                  children: [
                    if (timelines.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Text(
                          '（暂未获取到子时间线）',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: (app.contentFontSize - 2).clamp(10, 999),
                            height: app.contentLineHeight,
                            fontFamily: app.fontFamily,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    for (final t in sortedTimelines)
                      ListTile(
                        dense: true,
                        selected: t.id == _selectedForumId && _sectionIndex == 1,
                        title: Text(
                          displayNameOf(t),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () async {
                          setState(() => _sectionIndex = 1);
                          await _selectForum(api.Forum(
                            id: t.id,
                            name: t.name,
                            displayName: t.displayName,
                            message: t.message,
                            forumGroupId: -1,
                            sort: t.id,
                            threadCount: 0,
                          ));
                        },
                      ),
                  ],
                );
              }

              return ExpansionTile(
                title: Text(g.title),
                initiallyExpanded: false,
                children: [
                  for (final forum in g.forums)
                    InkWell(
                      onSecondaryTap: () => _toggleCommonForum(forum),
                      child: ListTile(
                        dense: true,
                        selected:
                            forum.id == _selectedForumId && _sectionIndex == 1,
                        trailing: _commonForumIds.contains(forum.id)
                            ? const Icon(Icons.push_pin, size: 16)
                            : null,
                        title: Text.rich(
                          _parseForumNameToSpan(
                            context,
                            forum.showName,
                            baseTextStyle,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () async {
                          setState(() => _sectionIndex = 1);
                          await _selectForum(forum);
                        },
                      ),
                    )
                ],
              );
            }),
      ],
          if (!_sidebarExpanded)
            ...groups
                .where((g) => g.title != '时间线')
                .expand((g) => g.forums)
                .map((forum) {
              return IconButton(
                tooltip: _normalizeForListPreview(forum.showName),
                onPressed: () async {
                  setState(() => _sectionIndex = 1);
                  await _selectForum(forum);
                },
                icon: const Icon(Icons.forum_outlined),
              );
            })
          ],
        ],
        ),
      ),
    );
  }

  Future<void> _openIslandRulesThread() async {
    // 固定串：岛规 No.50000001
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ThreadPage(mainPostId: 50000001),
      ),
    );
  }

  Future<void> _maybeShowAnnouncementOnce() async {
    if (_announcementChecked) return;
    _announcementChecked = true;
    if (!mounted) return;
  final prefs = context.read<LocalPrefs>();
  final app = context.read<AppState>();
  final nav = Navigator.of(context);

  final skip = await prefs.getSkipAnnouncement();
    if (skip) return;

    String content;
    try {
    final notice = await app.repo.getNotice();
      final raw = notice.content.trim().isEmpty ? '（空）' : notice.content;
      content = normalizeDialogHtml(raw);
    } catch (e) {
      // 公告失败不打扰用户；下次再试。
      return;
    }

    if (!mounted) return;
    final dontShowAgain = await showDialog<bool>(
      context: context,
      builder: (context) {
        var dontShowAgain = false;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('公告'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: PostContent(text: content, postId: 0),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: dontShowAgain,
                    onChanged: (v) => setState(() => dontShowAgain = v ?? false),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('不再显示'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('关闭'),
              ),
              FilledButton(
                onPressed: () => nav.pop(dontShowAgain),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      },
    );

    if (dontShowAgain == true) {
      await prefs.setSkipAnnouncement(true);
    }
  }

  Future<void> _showForumRules() async {
    final forumId = _selectedForumId;
    final forumName = _selectedForumName;
    if (forumId == null) return;

    String content;
    try {
      // 网页版通常更完整
      final htmlForum = await context.read<AppState>().repo.getHtmlForumInfo(
            forumId,
          );
      content = normalizeDialogHtml(htmlForum.message);
    } catch (_) {
      // 回退：forumList 的 message（接口字段就是“版规/版块信息”）
      String? msg;
      final list = _forumList;
      if (list != null) {
        msg = list.forumList
            .where((f) => f.id == forumId)
            .map((f) => f.message)
            .cast<String?>()
            .firstWhere((m) => m != null, orElse: () => null);
      }
      content = (msg == null || msg.trim().isEmpty)
          ? '（无）'
          : normalizeDialogHtml(msg);
    }

  if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('版规：${forumName ?? forumId}'),
        content: SingleChildScrollView(
          child: PostContent(text: content, postId: -forumId),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          )
        ],
      ),
    );
  }

  Widget _buildRightPane() {
    switch (_sectionIndex) {
      case 0:
  return _buildStartWithRandomCover();
      case 1:
        return _buildRightThreads();
      case 2:
        return const SubscriptionPage();
      case 3:
        return const HistoryPage();
      case 4:
        return const MyPostsPage();
      case 5:
        return const UserManagePage();
      default:
        return const StartPage();
    }
  }

  Widget _buildStartWithRandomCover() {
  // Start page with a single random cover under the title area.
    return LayoutBuilder(
      builder: (context, c) {
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            StartPage(
              randomCoverUrl: _randomCoverUrl,
              randomCoverLoading: _randomCoverLoading,
              randomCoverError: _randomCoverError?.toString(),
              randomCoverNonce: _randomCoverNonce,
            ),
          ],
        );
      },
    );
  }

  Widget _buildRightThreads() {
    if (_selectedForumId == null) {
      return const StartPage();
    }

    return RefreshIndicator(
      onRefresh: _refreshThreads,
      child: ListView.separated(
        controller: _scrollController,
        itemCount: _threads.length + 1,
  separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == _threads.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: _loadingPage
                    ? const CircularProgressIndicator()
                    : Text(_hasMore ? '上拉加载更多' : '没有更多了'),
              ),
            );
          }

          final t = _threads[index];
          final p = t.mainPost;
      final trimmedTitle = p.title.trim();
      final hasVisibleTitle =
        trimmedTitle.isNotEmpty && trimmedTitle != '无标题';
          return ThreadListItem(
            thumbUrl: p.thumbImageUrl,
            title: hasVisibleTitle ? trimmedTitle : null,
            content: p.content,
            cookie: p.userHash,
            time: p.postTime,
            isAdmin: p.isAdmin,
            onTap: () {
              // Best-effort record visit at entry point.
              // ignore: discarded_futures
              _historyStore.recordVisit(
                threadId: p.id,
                title: hasVisibleTitle ? trimmedTitle : null,
              );
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ThreadPage(
                    mainPostId: p.id,
                    title: hasVisibleTitle ? trimmedTitle : null,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

final class _SidebarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarAction(
      {required this.icon,
      required this.label,
      required this.expanded,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = selected ? cs.primaryContainer : cs.surfaceContainerHighest;
    final fg = selected ? cs.onPrimaryContainer : cs.onSurfaceVariant;

    if (!expanded) {
      return Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: fg),
          ),
        ),
      );
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: fg, size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style:
                      Theme.of(context).textTheme.labelLarge?.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

String _normalizeForListPreview(String input) {
  var s = input;
  s = s.replaceAll(RegExp(r'<\s*br\s*\/?>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<\s*\/p\s*>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<\s*p\s*>', caseSensitive: false), '');
  s = s.replaceAll(
      RegExp(r'<\s*\/\s*font\s*>', caseSensitive: false), '');
  s = s.replaceAll(
      RegExp(r'<\s*font\b[^>]*>', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  s = s
      .replaceAll('&gt;', '>')
      .replaceAll('&lt;', '<')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  // Match in-thread rendering: collapse any consecutive newlines into ONE.
  // This prevents "no blank line in source but shows a blank line".
  s = s.replaceAll(RegExp(r'\n{2,}'), '\n');
  return s;
}
