import 'package:flutter/material.dart';
import 'package:xdnmb_api/xdnmb_api.dart';

import '../data/cookie_store.dart';
import '../data/xdnmb_repository.dart';

/// Manages cookie slots, active cookie, and auth/post defaults.
///
/// Separated from AppState so UI pages can watch only cookie changes
/// without rebuilding on unrelated settings changes.
final class CookieController extends ChangeNotifier {
  final CookieStore _store;
  final XdnmbApi _api;
  final XdnmbRepository _repo;

  List<CookieSlot> slots = const [];
  String? activeSlotId;
  String? defaultPostSlotId;
  String? defaultAuthSlotId;
  String? cookieName;

  CookieController({
    required CookieStore store,
    required XdnmbApi api,
    required XdnmbRepository repo,
  })  : _store = store,
        _api = api,
        _repo = repo;

  Future<void> init() async {
    slots = await _store.readSlots();
    activeSlotId = await _store.readActiveSlotId();
    final defaultPost = await _store.readDefaultPostSlot();
    final defaultAuth = await _store.readDefaultAuthSlot();
    defaultPostSlotId = defaultPost?.id;
    defaultAuthSlotId = defaultAuth?.id;

    final CookieSlot? browsingSlot = defaultAuth ?? await _store.readActiveSlot();
    cookieName = browsingSlot?.name;

    if (browsingSlot != null) {
      _api.xdnmbCookie = XdnmbCookie(browsingSlot.userHash, name: browsingSlot.name);
    }

    _repo.setAuthCookie(defaultAuth?.userHash == null
        ? null
        : XdnmbCookie(defaultAuth!.userHash, name: defaultAuth.name).cookie);
  }

  bool get hasCookie => _api.xdnmbCookie != null;

  String? get defaultPostCookieHeader {
    final slot = defaultPostCookieSlot;
    if (slot == null) return null;
    return XdnmbCookie(slot.userHash, name: slot.name).cookie;
  }

  CookieSlot? _findSlot(String? id) {
    if (id == null) return null;
    for (final s in slots) {
      if (s.id == id) return s;
    }
    return null;
  }

  CookieSlot? get defaultPostCookieSlot => _findSlot(defaultPostSlotId);
  CookieSlot? get defaultAuthCookieSlot => _findSlot(defaultAuthSlotId);

  CookieSlot? get activeCookieSlot {
    if (slots.isEmpty) return null;
    final id = activeSlotId;
    if (id == null) return slots.first;
    return slots.firstWhere((s) => s.id == id, orElse: () => slots.first);
  }

  Future<void> importCookie({required XdnmbCookie cookie}) async {
    _api.xdnmbCookie = cookie;
    await _store.upsertSlot(userHash: cookie.userHash, name: cookie.name);

    final slotId = await _store.readActiveSlotId();
    if (slotId != null) {
      await _store.setDefaultAuthSlot(slotId);
      await _store.setDefaultPostSlot(slotId);
    }

    slots = await _store.readSlots();
    activeSlotId = await _store.readActiveSlotId();
    final defaultPost = await _store.readDefaultPostSlot();
    final defaultAuth = await _store.readDefaultAuthSlot();
    defaultPostSlotId = defaultPost?.id;
    defaultAuthSlotId = defaultAuth?.id;
    cookieName = cookie.name;
    notifyListeners();
  }

  Future<void> switchCookieSlot(String slotId) async {
    await _store.setActiveSlot(slotId);
    activeSlotId = slotId;
    final slot = (await _store.readActiveSlot());
    _api.xdnmbCookie = slot == null ? null : XdnmbCookie(slot.userHash, name: slot.name);
    cookieName = slot?.name;
    notifyListeners();
  }

  Future<void> updateSlotMeta(
    String slotId, {
    String? name,
    String? note,
  }) async {
    await _store.updateSlot(slotId, name: name, note: note);
    slots = await _store.readSlots();
    final defaultPost = await _store.readDefaultPostSlot();
    final defaultAuth = await _store.readDefaultAuthSlot();
    defaultPostSlotId = defaultPost?.id;
    defaultAuthSlotId = defaultAuth?.id;
    _repo.setAuthCookie(defaultAuth?.userHash == null
        ? null
        : XdnmbCookie(defaultAuth!.userHash, name: defaultAuth.name).cookie);
    notifyListeners();
  }

  Future<void> setDefaultPostSlot(String slotId) async {
    await _store.setDefaultPostSlot(slotId);
    slots = await _store.readSlots();
    final defaultPost = await _store.readDefaultPostSlot();
    defaultPostSlotId = defaultPost?.id;
    notifyListeners();
  }

  Future<void> setDefaultAuthSlot(String slotId) async {
    await _store.setDefaultAuthSlot(slotId);
    slots = await _store.readSlots();
    final defaultAuth = await _store.readDefaultAuthSlot();
    defaultAuthSlotId = defaultAuth?.id;

    final slot = _findSlot(slotId);
    _api.xdnmbCookie = slot == null ? null : XdnmbCookie(slot.userHash, name: slot.name);
    cookieName = slot?.name;

    _repo.setAuthCookie(slot == null ? null : XdnmbCookie(slot.userHash, name: slot.name).cookie);
    _repo.clearCaches();
    notifyListeners();
  }

  Future<void> deleteSlot(String slotId) async {
    await _store.deleteSlot(slotId);
    slots = await _store.readSlots();
    activeSlotId = await _store.readActiveSlotId();
    final defaultPost = await _store.readDefaultPostSlot();
    final defaultAuth = await _store.readDefaultAuthSlot();
    defaultPostSlotId = defaultPost?.id;
    defaultAuthSlotId = defaultAuth?.id;
    _repo.setAuthCookie(defaultAuth?.userHash == null
        ? null
        : XdnmbCookie(defaultAuth!.userHash, name: defaultAuth.name).cookie);
    final slot = await _store.readActiveSlot();
    _api.xdnmbCookie = slot == null ? null : XdnmbCookie(slot.userHash, name: slot.name);
    cookieName = slot?.name;
    notifyListeners();
  }

  Future<void> clearAll() async {
    _api.xdnmbCookie = null;
    await _store.clearAll();
    slots = const [];
    activeSlotId = null;
    defaultPostSlotId = null;
    defaultAuthSlotId = null;
    _repo.clearCaches();
    _repo.setAuthCookie(null);
    cookieName = null;
    notifyListeners();
  }
}
