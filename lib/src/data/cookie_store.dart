import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

String _sanitizeUserHash(String input) {
  // IMPORTANT: userhash is arbitrary bytes. We may store it as latin1 string
  // (0x00-0xFF). Do NOT drop 0x80-0xFF, otherwise we destroy the cookie.
  // Only remove header-breaking control characters.
  final runes = input.runes.where((c) {
    // Disallow: NUL, CR, LF, DEL.
    if (c == 0x00 || c == 0x0d || c == 0x0a || c == 0x7f) return false;
    return true;
  });
  // Do NOT normalize whitespace: that would mutate bytes.
  return String.fromCharCodes(runes);
}

bool _looksLikePercentEncoded(String s) {
  // Stronger heuristic:
  // - Count %xx blocks
  // - If the string is mostly composed of %xx blocks, treat it as encoded.
  final re = RegExp(r'%[0-9a-fA-F]{2}');
  final matches = re.allMatches(s).toList(growable: false);
  if (matches.length < 8) return false;

  // If the string contains lots of non-% characters, it's likely *not* a pure
  // percent-encoded cookie text, but raw bytes that happen to include '%'.
  // We must NOT decode in that case, otherwise we'd "double decode" and lose
  // bytes.
  final nonPercentChars = s.runes.where((c) => c != 0x25 /* % */).length;
  if (nonPercentChars > matches.length * 2) {
    return false;
  }

  // Compute how many characters are "covered" by %xx blocks.
  final covered = matches.length * 3;
  // If >80% of the string is percent triplets, it's almost certainly encoded.
  return covered >= (s.length * 0.8);
}

int _hexValue(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
  if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
  return -1;
}

String _decodePercentToLatin1(String input) {
  final bytes = <int>[];
  for (var i = 0; i < input.length; i++) {
    final c = input.codeUnitAt(i);
    if (c == 0x25 /* % */ && i + 2 < input.length) {
      final hi = _hexValue(input.codeUnitAt(i + 1));
      final lo = _hexValue(input.codeUnitAt(i + 2));
      if (hi >= 0 && lo >= 0) {
        bytes.add((hi << 4) | lo);
        i += 2;
        continue;
      }
    }
    bytes.add(c);
  }
  return latin1.decode(bytes, allowInvalid: true);
}

String normalizeUserHashForStorage(String userHash) {
  final trimmed = userHash.trim();
  if (trimmed.isEmpty) return '';

  // If userHash is already percent-encoded text, decode it back to raw bytes.
  if (_looksLikePercentEncoded(trimmed)) {
    return _sanitizeUserHash(_decodePercentToLatin1(trimmed));
  }
  return _sanitizeUserHash(trimmed);
}

/// Securely stores multiple forum cookies (userhash) in slots.
///
/// - Slots are stored as JSON (encrypted by flutter_secure_storage).
/// - A separate key stores the active slot id.
/// - We keep a migration path from the legacy single-cookie keys.
final class CookieSlot {
  final String id;
  final String userHash;
  final String? name;
  /// User-visible note/alias for this cookie.
  final String? note;

  /// Whether this slot is the default cookie for posting.
  final bool isDefaultPost;

  /// Whether this slot is the default cookie for auth-required browsing.
  final bool isDefaultAuth;
  final int createdAtMs;

  const CookieSlot({
    required this.id,
    required this.userHash,
    this.name,
  this.note,
  this.isDefaultPost = false,
  this.isDefaultAuth = false,
    required this.createdAtMs,
  });

  factory CookieSlot.fromJson(Map<String, dynamic> json) => CookieSlot(
        id: json['id'] as String,
  userHash: normalizeUserHashForStorage(json['userHash'] as String),
        name: json['name'] as String?,
  note: json['note'] as String?,
  isDefaultPost: (json['isDefaultPost'] as bool?) ?? false,
  isDefaultAuth: (json['isDefaultAuth'] as bool?) ?? false,
        createdAtMs: (json['createdAtMs'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'userHash': userHash,
        'name': name,
  'note': note,
  'isDefaultPost': isDefaultPost,
  'isDefaultAuth': isDefaultAuth,
        'createdAtMs': createdAtMs,
      };
}

final class CookieStore {
  // Legacy keys (v1)
  static const _kLegacyUserHash = 'xdnmb.userHash';
  static const _kLegacyCookieName = 'xdnmb.cookieName';

  // New keys (v2)
  static const _kSlots = 'xdnmb.cookieSlots.v2';
  static const _kActiveSlotId = 'xdnmb.activeCookieSlotId.v2';

  final FlutterSecureStorage _storage;

  CookieStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<void> _migrateIfNeeded() async {
    final existing = await _storage.read(key: _kSlots);
    if (existing != null) return;

    final legacyUserHash = await _storage.read(key: _kLegacyUserHash);
    if (legacyUserHash == null || legacyUserHash.trim().isEmpty) return;
    final legacyName = await _storage.read(key: _kLegacyCookieName);

    final slot = CookieSlot(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      userHash: normalizeUserHashForStorage(legacyUserHash),
      name: legacyName,
  isDefaultPost: true,
  isDefaultAuth: true,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    await _storage.write(key: _kSlots, value: jsonEncode([slot.toJson()]));
    await _storage.write(key: _kActiveSlotId, value: slot.id);

    // Keep legacy keys for backward compatibility, but you may delete later.
  }

  Future<void> _ensureSingleDefaults() async {
    final slots = await readSlots();
    if (slots.isEmpty) return;

    CookieSlot? defaultPost;
    CookieSlot? defaultAuth;
    for (final s in slots) {
      if (defaultPost == null && s.isDefaultPost) defaultPost = s;
      if (defaultAuth == null && s.isDefaultAuth) defaultAuth = s;
    }

    // If none set, fall back to active slot.
    if (defaultPost == null || defaultAuth == null) {
      final active = await readActiveSlot();
      if (active != null) {
        defaultPost ??= active;
        defaultAuth ??= active;
      }
    }

    // Normalize: keep only first default; clear others.
    final newSlots = <CookieSlot>[];
    for (final s in slots) {
      newSlots.add(CookieSlot(
        id: s.id,
        userHash: s.userHash,
        name: s.name,
        note: s.note,
        isDefaultPost: defaultPost != null ? s.id == defaultPost.id : false,
        isDefaultAuth: defaultAuth != null ? s.id == defaultAuth.id : false,
        createdAtMs: s.createdAtMs,
      ));
    }
    await _storage.write(key: _kSlots, value: jsonEncode(newSlots));
  }

  Future<List<CookieSlot>> readSlots() async {
    await _migrateIfNeeded();
    final raw = await _storage.read(key: _kSlots);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final slots = decoded
          .whereType<Map>()
          .map((e) => CookieSlot.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      // Best-effort in-place normalization fixup.
      final normalized = <CookieSlot>[];
      var changed = false;
      for (final s in slots) {
        final n = normalizeUserHashForStorage(s.userHash);
        if (n != s.userHash) changed = true;
        normalized.add(CookieSlot(
          id: s.id,
          userHash: n,
          name: s.name,
          note: s.note,
          isDefaultPost: s.isDefaultPost,
          isDefaultAuth: s.isDefaultAuth,
          createdAtMs: s.createdAtMs,
        ));
      }
      if (changed) {
        await _storage.write(key: _kSlots, value: jsonEncode(normalized));
      }
      return normalized;
    } catch (_) {
      return const [];
    }
  }

  Future<CookieSlot?> readDefaultPostSlot() async {
    await _ensureSingleDefaults();
    final slots = await readSlots();
    return slots.cast<CookieSlot?>().firstWhere((s) => s?.isDefaultPost == true,
        orElse: () => slots.isEmpty ? null : slots.first);
  }

  Future<CookieSlot?> readDefaultAuthSlot() async {
    await _ensureSingleDefaults();
    final slots = await readSlots();
    return slots.cast<CookieSlot?>().firstWhere((s) => s?.isDefaultAuth == true,
        orElse: () => slots.isEmpty ? null : slots.first);
  }

  Future<String?> readActiveSlotId() async {
    await _migrateIfNeeded();
    return _storage.read(key: _kActiveSlotId);
  }

  Future<CookieSlot?> readActiveSlot() async {
    final slots = await readSlots();
    if (slots.isEmpty) return null;
    final activeId = await readActiveSlotId();
    if (activeId == null) return slots.first;
    return slots.firstWhere((s) => s.id == activeId, orElse: () => slots.first);
  }

  Future<void> setActiveSlot(String id) async {
    await _storage.write(key: _kActiveSlotId, value: id);
  }

  Future<void> upsertSlot({required String userHash, String? name}) async {
  final normalizedUserHash = normalizeUserHashForStorage(userHash);
  if (normalizedUserHash.isEmpty) return;
    final slots = await readSlots();

    // If userHash already exists, update its name and activate it.
    final existingIndex =
    slots.indexWhere((s) => s.userHash.trim() == normalizedUserHash.trim());
    if (existingIndex >= 0) {
      final existing = slots[existingIndex];
      final updated = CookieSlot(
        id: existing.id,
        userHash: existing.userHash,
        name: name ?? existing.name,
        note: existing.note,
        isDefaultPost: existing.isDefaultPost,
        isDefaultAuth: existing.isDefaultAuth,
        createdAtMs: existing.createdAtMs,
      );
      final newSlots = [...slots]..[existingIndex] = updated;
      await _storage.write(key: _kSlots, value: jsonEncode(newSlots));
      await setActiveSlot(updated.id);
      await _ensureSingleDefaults();
      return;
    }

    final slot = CookieSlot(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
  userHash: normalizedUserHash,
      name: name,
  isDefaultPost: slots.isEmpty,
  isDefaultAuth: slots.isEmpty,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    final newSlots = [...slots, slot];
    await _storage.write(key: _kSlots, value: jsonEncode(newSlots));
    await setActiveSlot(slot.id);
    await _ensureSingleDefaults();
  }

  Future<void> updateSlot(
    String id, {
    String? name,
    String? note,
  }) async {
    final slots = await readSlots();
    final idx = slots.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final s = slots[idx];
    final updated = CookieSlot(
      id: s.id,
      userHash: s.userHash,
      name: name ?? s.name,
      note: note ?? s.note,
      isDefaultPost: s.isDefaultPost,
      isDefaultAuth: s.isDefaultAuth,
      createdAtMs: s.createdAtMs,
    );
    final newSlots = [...slots]..[idx] = updated;
    await _storage.write(key: _kSlots, value: jsonEncode(newSlots));
  }

  Future<void> setDefaultPostSlot(String id) async {
    final slots = await readSlots();
    if (slots.isEmpty) return;
    final newSlots = <CookieSlot>[];
    for (final s in slots) {
      newSlots.add(CookieSlot(
        id: s.id,
        userHash: s.userHash,
        name: s.name,
        note: s.note,
        isDefaultPost: s.id == id,
        isDefaultAuth: s.isDefaultAuth,
        createdAtMs: s.createdAtMs,
      ));
    }
    await _storage.write(key: _kSlots, value: jsonEncode(newSlots));
    await _ensureSingleDefaults();
  }

  Future<void> setDefaultAuthSlot(String id) async {
    final slots = await readSlots();
    if (slots.isEmpty) return;
    final newSlots = <CookieSlot>[];
    for (final s in slots) {
      newSlots.add(CookieSlot(
        id: s.id,
        userHash: s.userHash,
        name: s.name,
        note: s.note,
        isDefaultPost: s.isDefaultPost,
        isDefaultAuth: s.id == id,
        createdAtMs: s.createdAtMs,
      ));
    }
    await _storage.write(key: _kSlots, value: jsonEncode(newSlots));
    await _ensureSingleDefaults();
  }

  Future<void> deleteSlot(String id) async {
    final slots = await readSlots();
    final newSlots = slots.where((s) => s.id != id).toList();
    await _storage.write(key: _kSlots, value: jsonEncode(newSlots));

    final activeId = await readActiveSlotId();
    if (activeId == id) {
      if (newSlots.isEmpty) {
        await _storage.delete(key: _kActiveSlotId);
      } else {
        await setActiveSlot(newSlots.first.id);
      }
    }

  await _ensureSingleDefaults();
  }

  Future<void> clearAll() async {
    await _storage.delete(key: _kSlots);
    await _storage.delete(key: _kActiveSlotId);
    // legacy
    await _storage.delete(key: _kLegacyUserHash);
    await _storage.delete(key: _kLegacyCookieName);
  }
}

