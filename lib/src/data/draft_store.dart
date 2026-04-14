import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Composer draft persisted locally.
///
/// Note: image is stored as a local file path (desktop). If the file is moved
/// or deleted, UI should tolerate it.
final class ComposerDraft {
  final String? title;
  final String content;
  final bool watermark;
  final String? imagePath;
  final String? selectedPostCookieSlotId;

  const ComposerDraft({
    required this.content,
    this.title,
    this.watermark = false,
    this.imagePath,
    this.selectedPostCookieSlotId,
  });

  Map<String, Object?> toJson() => {
        'title': title,
        'content': content,
        'watermark': watermark,
        'imagePath': imagePath,
        'selectedPostCookieSlotId': selectedPostCookieSlotId,
      };

  static ComposerDraft fromJson(Map<String, Object?> json) {
    return ComposerDraft(
      title: json['title'] as String?,
      content: (json['content'] as String?) ?? '',
      watermark: (json['watermark'] as bool?) ?? false,
      imagePath: json['imagePath'] as String?,
      selectedPostCookieSlotId: json['selectedPostCookieSlotId'] as String?,
    );
  }
}

final class DraftStore {
  static const _kNewThread = 'xdnmb.draft.newThread';
  static const _kReply = 'xdnmb.draft.reply';

  const DraftStore();

  String _key(bool isReply) => isReply ? _kReply : _kNewThread;

  Future<ComposerDraft?> read({required bool isReply}) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key(isReply));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return ComposerDraft.fromJson(
          decoded.map((k, v) => MapEntry(k.toString(), v)));
    } catch (_) {
      return null;
    }
  }

  Future<void> write({required bool isReply, required ComposerDraft draft}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key(isReply), jsonEncode(draft.toJson()));
  }

  Future<void> clear({required bool isReply}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key(isReply));
  }
}
