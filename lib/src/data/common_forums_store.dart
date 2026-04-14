import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Stores user-picked "common" forums for the sidebar.
///
/// - Keyed by forumId.
/// - We also store [showName] so we can render even before forum list is loaded
///   (best-effort; it can be refreshed from api later).
final class CommonForumEntry {
  final int forumId;
  final String showName;
  final DateTime addedAt;

  const CommonForumEntry({
    required this.forumId,
    required this.showName,
    required this.addedAt,
  });

  Map<String, Object?> toJson() => {
        'forumId': forumId,
        'showName': showName,
        'addedAt': addedAt.toIso8601String(),
      };

  static CommonForumEntry fromJson(Map<String, Object?> json) {
    final id = (json['forumId'] as num).toInt();
    final name = (json['showName'] as String?) ?? '';
    final atRaw = (json['addedAt'] as String?) ?? '';
    final at = DateTime.tryParse(atRaw) ?? DateTime.fromMillisecondsSinceEpoch(0);
    return CommonForumEntry(forumId: id, showName: name, addedAt: at);
  }
}

final class CommonForumsStore {
  static const _k = 'xdnmb.commonForums.v1';

  const CommonForumsStore();

  Future<List<CommonForumEntry>> readAll() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_k);
    if (raw == null || raw.trim().isEmpty) return const [];

    try {
      final arr = jsonDecode(raw);
      if (arr is! List) return const [];
      return arr
          .whereType<Map>()
          .map((e) => CommonForumEntry.fromJson(e.cast<String, Object?>()))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<bool> contains(int forumId) async {
    final all = await readAll();
    return all.any((e) => e.forumId == forumId);
  }

  Future<void> add({required int forumId, required String showName}) async {
    final sp = await SharedPreferences.getInstance();
    final all = (await readAll()).toList(growable: true);
    all.removeWhere((e) => e.forumId == forumId);
    all.insert(
      0,
      CommonForumEntry(
        forumId: forumId,
        showName: showName,
        addedAt: DateTime.now(),
      ),
    );

    await sp.setString(
      _k,
      jsonEncode(all.map((e) => e.toJson()).toList(growable: false)),
    );
  }

  Future<void> remove(int forumId) async {
    final sp = await SharedPreferences.getInstance();
    final all = (await readAll()).where((e) => e.forumId != forumId).toList();
    await sp.setString(
      _k,
      jsonEncode(all.map((e) => e.toJson()).toList(growable: false)),
    );
  }
}
