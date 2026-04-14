import 'package:xdnmb_api/xdnmb_api.dart';

/// A small mapping layer for sidebar grouping.
///
/// The server API doesn't expose the high-level categories (综合/亚文化/创作...).
/// We start with a fallback based on [Forum.forumGroupId]. You can later provide
/// a custom mapping by forum id/name.
final class SidebarGroup {
  final String title;
  final List<Forum> forums;
  final List<Timeline>? timelines;

  const SidebarGroup({required this.title, required this.forums, this.timelines});
}

List<SidebarGroup> buildSidebarGroups(ForumList list) {
  final out = <SidebarGroup>[];

  // Timeline group (if exists): represented as a single top-level group
  // named "时间线". The UI will render it as nested groups.
  final timelines = list.timelineList;
  if (timelines != null && timelines.isNotEmpty) {
    out.add(
      SidebarGroup(
        title: '时间线',
  forums: const [],
  timelines: timelines,
      ),
    );
  }

  // Group by forumGroupId first.
  final map = <int, List<Forum>>{};
  for (final f in list.forumList) {
    map.putIfAbsent(f.forumGroupId, () => []).add(f);
  }

  String titleFor(int forumGroupId) {
    final fromApi = list.forumGroupList
        .where((g) => g.id == forumGroupId)
        .map((g) => g.name)
        .cast<String?>()
        .firstWhere((e) => e != null, orElse: () => null);
    return fromApi ?? '分区 $forumGroupId';
  }

  final keys = map.keys.toList()..sort();

  out.addAll([
    for (final k in keys)
      SidebarGroup(
          title: titleFor(k),
          forums: (map[k]!..sort((a, b) => a.sort.compareTo(b.sort))))
  ]);

  return out;
}
