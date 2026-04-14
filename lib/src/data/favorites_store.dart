import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

final class FavoriteThread {
  final int threadId;
  final String? title;
  final DateTime addedAt;

  const FavoriteThread({
    required this.threadId,
    this.title,
    required this.addedAt,
  });

  Map<String, Object?> toJson() => {
        'threadId': threadId,
        'title': title,
        'addedAt': addedAt.toIso8601String(),
      };

  static FavoriteThread? fromJson(Map<String, Object?> json) {
    final id = json['threadId'];
    if (id is! int) return null;
    final at = DateTime.tryParse((json['addedAt'] as String?) ?? '');
    return FavoriteThread(
      threadId: id,
      title: json['title'] as String?,
      addedAt: at ?? DateTime.now(),
    );
  }
}

final class FavoritesStore {
  static const _kFavorites = 'xdnmb.favorites.threads';

  const FavoritesStore();

  Future<List<FavoriteThread>> readAll() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kFavorites);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <FavoriteThread>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        final m = e.map((k, v) => MapEntry(k.toString(), v));
        final fav = FavoriteThread.fromJson(m);
        if (fav != null) out.add(fav);
      }
      // newest first
      out.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<bool> isFavorite(int threadId) async {
    final all = await readAll();
    return all.any((e) => e.threadId == threadId);
  }

  Future<void> toggle({required int threadId, String? title}) async {
    final sp = await SharedPreferences.getInstance();
    final all = await readAll();
    final idx = all.indexWhere((e) => e.threadId == threadId);
    if (idx >= 0) {
      all.removeAt(idx);
    } else {
      all.insert(
        0,
        FavoriteThread(threadId: threadId, title: title, addedAt: DateTime.now()),
      );
    }
    await sp.setString(_kFavorites, jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  Future<void> remove(int threadId) async {
    final sp = await SharedPreferences.getInstance();
    final all = await readAll();
    all.removeWhere((e) => e.threadId == threadId);
    await sp.setString(_kFavorites, jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kFavorites);
  }
}
