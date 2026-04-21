import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/draft_store.dart';

enum ComposerMode { newThread, reply }

enum ComposerDisplayMode { panel, dialog }

/// Immutable configuration for opening the composer.
final class ComposerArgs {
  final ComposerMode mode;
  final int? forumId;
  final String? forumName;
  final int? mainPostId;
  final String? initialContent;

  const ComposerArgs({
    required this.mode,
    this.forumId,
    this.forumName,
    this.mainPostId,
    this.initialContent,
  });
}

/// Global composer state. Lives in [AppState] so the editor persists across
/// page navigations and can be shown as a panel or dialog.
final class ComposerController extends ChangeNotifier {
  // ── Config ──
  ComposerArgs? _args;
  ComposerArgs? get args => _args;

  // ── Text controllers ──
  final titleCtrl = TextEditingController();
  final contentCtrl = TextEditingController();
  final focusNode = FocusNode();

  // ── Editor state ──
  bool watermark = false;
  bool posting = false;
  String? imagePath;
  String? selectedCookieSlotId;
  bool emoticonExpanded = false;

  // ── Display state ──
  bool isOpen = false;
  ComposerDisplayMode displayMode = ComposerDisplayMode.panel;
  double panelWidth = 420;
  final panelWidthNotifier = ValueNotifier<double>(420);
  bool isAlwaysOnTop = false;

  // ── Sub-window tracking ──
  String? _activeWindowId;
  String? get activeWindowId => _activeWindowId;

  // ── Sub-window alive check (fallback when windowClosed msg is missed) ──
  Timer? _windowAliveCheckTimer;

  // ── Cross-window refresh signal ──
  final _refreshSignal = ValueNotifier<int>(0);
  ValueNotifier<int> get refreshSignal => _refreshSignal;

  /// Called from main window when a sub-window reports post success.
  void notifyRefreshFromSubWindow() {
    _refreshSignal.value++;
    notifyListeners();
  }

  // ── Draft internals ──
  final _draftStore = const DraftStore();
  bool _draftLoaded = false;
  bool _restoringDraft = false;
  bool _draftClearedOnSuccess = false;
  int _draftTicket = 0;
  bool showDraftSaved = false;

  // ── Keys ──
  static const _kPanelWidth = 'xdnmb.composer.panelWidth';

  bool get isReply => _args?.mode == ComposerMode.reply;

  String get windowTitle {
    if (_args == null) return '';
    return _args!.mode == ComposerMode.newThread
        ? '发串${_args!.forumName == null ? '' : ' · ${_args!.forumName}'}'
        : '回串 · No.${_args!.mainPostId}';
  }

  // ── Lifecycle ──

  ComposerController() {
    titleCtrl.addListener(_onDraftRelevantChanged);
    contentCtrl.addListener(_onDraftRelevantChanged);
  }

  @override
  void dispose() {
    titleCtrl.removeListener(_onDraftRelevantChanged);
    contentCtrl.removeListener(_onDraftRelevantChanged);
    titleCtrl.dispose();
    contentCtrl.dispose();
    focusNode.dispose();
    panelWidthNotifier.dispose();
    _refreshSignal.dispose();
    super.dispose();
  }

  // ── Public state setters (wrap notifyListeners) ──

  void setImagePath(String? path) {
    imagePath = path;
    notifyListeners();
  }

  void setWatermark(bool value) {
    watermark = value;
    notifyListeners();
  }

  void setSelectedCookieSlotId(String? id) {
    selectedCookieSlotId = id;
    notifyListeners();
  }

  void setEmoticonExpanded(bool expanded) {
    emoticonExpanded = expanded;
    notifyListeners();
  }

  void setPosting(bool value) {
    posting = value;
    notifyListeners();
  }

  // ── Open / Close ──

  void openPanel(ComposerArgs args, {String? defaultCookieSlotId}) {
    _args = args;
    displayMode = ComposerDisplayMode.panel;
    isOpen = true;
    selectedCookieSlotId ??= defaultCookieSlotId;
    _loadPanelWidth();
    _draftLoaded = false;
    _draftClearedOnSuccess = false;
    notifyListeners();
    Future.microtask(_restoreDraftIfAny);
  }

  void openDialog(ComposerArgs args, {String? defaultCookieSlotId}) {
    _args = args;
    displayMode = ComposerDisplayMode.dialog;
    isOpen = true;
    selectedCookieSlotId ??= defaultCookieSlotId;
    _draftLoaded = false;
    _draftClearedOnSuccess = false;
    notifyListeners();
    Future.microtask(_restoreDraftIfAny);
  }

  void close() {
    if (posting) return;
    _saveDraftNow();
    isOpen = false;
    displayMode = ComposerDisplayMode.panel;
    notifyListeners();
  }

  /// Save draft and pop out to a real independent sub-window.
  Future<void> popOutToWindow() async {
    if (posting) return;
    await _saveDraftNow();

    final args = jsonEncode({
      'mode': _args?.mode == ComposerMode.newThread ? 'newThread' : 'reply',
      'forumId': _args?.forumId,
      'forumName': _args?.forumName,
      'mainPostId': _args?.mainPostId,
      'initialContent': _args?.initialContent,
      'cookieSlotId': selectedCookieSlotId,
      'title': windowTitle,
    });

    final window = await WindowController.create(
      WindowConfiguration(
        arguments: args,
        hiddenAtLaunch: false,
      ),
    );
    _activeWindowId = window.windowId;
    await window.show();

    // Close the embedded panel; user now edits in the sub-window.
    isOpen = false;
    displayMode = ComposerDisplayMode.panel;
    notifyListeners();

    // Start heartbeat to detect if the sub-window is closed without
    // sending the windowClosed message (desktop_multi_window lifecycle
    // is not fully reliable on all platforms).
    _startWindowAliveCheck();
  }

  /// Send quote text to the active sub-window if it exists.
  /// Returns true if sent successfully, false if no window or it closed.
  Future<bool> sendQuoteToWindow(String text) async {
    if (_activeWindowId == null) return false;
    try {
      await WindowController.fromWindowId(_activeWindowId!)
          .invokeMethod('insertQuote', text);
      return true;
    } catch (_) {
      _activeWindowId = null;
      notifyListeners();
      return false;
    }
  }

  /// Called by the main window when a sub-window reports that it has closed.
  void clearWindowId() {
    _stopWindowAliveCheck();
    _activeWindowId = null;
    notifyListeners();
  }

  /// Best-effort check whether the tracked sub-window is still alive.
  /// If not, clears [_activeWindowId] and notifies listeners.
  Future<void> checkWindowAlive() async {
    if (_activeWindowId == null) return;
    try {
      final window = WindowController.fromWindowId(_activeWindowId!);
      await window
          .invokeMethod('ping')
          .timeout(const Duration(seconds: 1));
    } catch (_) {
      _stopWindowAliveCheck();
      _activeWindowId = null;
      notifyListeners();
    }
  }

  void _startWindowAliveCheck() {
    _stopWindowAliveCheck();
    _windowAliveCheckTimer =
        Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_activeWindowId == null) {
        _stopWindowAliveCheck();
        return;
      }
      await checkWindowAlive();
    });
  }

  void _stopWindowAliveCheck() {
    _windowAliveCheckTimer?.cancel();
    _windowAliveCheckTimer = null;
  }

  void toggleFloat() {
    if (posting) return;
    _saveDraftNow();
    displayMode = displayMode == ComposerDisplayMode.panel
        ? ComposerDisplayMode.dialog
        : ComposerDisplayMode.panel;
    notifyListeners();
  }

  void toggleAlwaysOnTop() {
    isAlwaysOnTop = !isAlwaysOnTop;
    notifyListeners();
  }

  void setPanelWidth(double w) {
    panelWidth = w;
    panelWidthNotifier.value = w;
    // Width changes are broadcast via panelWidthNotifier only,
    // avoiding full-page rebuilds during drag.
  }

  // ── Draft ──

  void _onDraftRelevantChanged() {
    if (_restoringDraft) return;
    _scheduleSaveDraft();
  }

  void onImageChanged() => _scheduleSaveDraft();
  void onWatermarkChanged() => _scheduleSaveDraft();
  void onCookieChanged() => _scheduleSaveDraft();

  void _scheduleSaveDraft() {
    if (posting) return;
    if (_draftClearedOnSuccess) return;

    final ticket = ++_draftTicket;
    Future<void>.delayed(const Duration(milliseconds: 450)).then((_) async {
      if (ticket != _draftTicket) return;
      if (_restoringDraft) return;
      await _saveDraftNow();
    });
  }

  Future<void> _saveDraftNow() async {
    if (_draftClearedOnSuccess) return;

    final draft = ComposerDraft(
      title: titleCtrl.text.trim().isEmpty ? null : titleCtrl.text.trim(),
      content: contentCtrl.text,
      watermark: watermark,
      imagePath: imagePath,
      selectedPostCookieSlotId: selectedCookieSlotId,
    );
    await _draftStore.write(isReply: isReply, draft: draft);
    showDraftSaved = true;
    notifyListeners();
    Future<void>.delayed(const Duration(seconds: 2), () {
      showDraftSaved = false;
      notifyListeners();
    });
  }

  Future<void> _restoreDraftIfAny() async {
    if (_draftLoaded) return;
    _draftLoaded = true;

    final draft = await _draftStore.read(isReply: isReply);
    final initial = (_args?.initialContent ?? '').trimRight();
    if (draft == null && initial.isEmpty) return;

    _restoringDraft = true;
    try {
      if (_args?.mode == ComposerMode.newThread) {
        final t = draft?.title;
        if (t != null && t.trim().isNotEmpty) {
          titleCtrl.text = t;
        }
      }

      final restoredContent = (draft?.content ?? '').trimRight();
      final merged = _mergeInitialIntoDraft(
        draftContent: restoredContent,
        initialContent: initial,
      );
      if (merged.isNotEmpty) {
        contentCtrl.text = merged;
        contentCtrl.selection =
            TextSelection.collapsed(offset: contentCtrl.text.length);
      }

      final img = draft?.imagePath;
      if (img != null && img.trim().isNotEmpty) {
        imagePath = img;
      }
      watermark = draft?.watermark ?? watermark;
      selectedCookieSlotId =
          draft?.selectedPostCookieSlotId ?? selectedCookieSlotId;
    } finally {
      _restoringDraft = false;
    }

    notifyListeners();
    await _saveDraftNow();
  }

  static String _mergeInitialIntoDraft({
    required String draftContent,
    required String initialContent,
  }) {
    if (initialContent.isEmpty) return draftContent;
    if (draftContent.isEmpty) return '$initialContent\n';
    if (draftContent.contains(initialContent)) return draftContent;
    return '$initialContent\n$draftContent';
  }

  Future<void> clearDraft() async {
    _draftClearedOnSuccess = true;
    await _draftStore.clear(isReply: isReply);
  }

  // ── Panel width persistence ──

  Future<void> _loadPanelWidth() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final v = sp.getDouble(_kPanelWidth);
      if (v != null && v >= 320 && v <= 1200) {
        panelWidth = v;
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> persistPanelWidth() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble(_kPanelWidth, panelWidth);
    } catch (_) {
      // ignore
    }
  }

  // ── Text helpers ──

  void insertText(String text) {
    final v = contentCtrl.value;
    final start = v.selection.start;
    final end = v.selection.end;
    final selectionValid = start >= 0 && end >= 0;

    if (!selectionValid) {
      contentCtrl.text += text;
      contentCtrl.selection =
          TextSelection.collapsed(offset: contentCtrl.text.length);
      return;
    }

    final newText = v.text.replaceRange(start, end, text);
    final newOffset = start + text.length;
    contentCtrl.value = v.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
      composing: TextRange.empty,
    );
  }

  void resetState() {
    titleCtrl.clear();
    contentCtrl.clear();
    watermark = false;
    imagePath = null;
    selectedCookieSlotId = null;
    emoticonExpanded = false;
    _draftLoaded = false;
    _draftClearedOnSuccess = false;
    _draftTicket = 0;
    showDraftSaved = false;
  }
}
