import 'package:flutter/material.dart';

import '../../data/draft_store.dart';

enum _ComposerMode { newThread, reply }

/// Composer state for the sub-window (shared between App and Page).
final class WindowComposerController extends ChangeNotifier {
  final titleCtrl = TextEditingController();
  final contentCtrl = TextEditingController();
  final focusNode = FocusNode();

  bool watermark = false;
  bool _posting = false;
  bool get posting => _posting;
  set posting(bool value) {
    _posting = value;
    notifyListeners();
  }

  String? imagePath;
  String? selectedCookieSlotId;
  bool emoticonExpanded = false;
  bool showDraftSaved = false;

  bool _isAlwaysOnTop = false;
  bool get isAlwaysOnTop => _isAlwaysOnTop;
  set isAlwaysOnTop(bool value) {
    _isAlwaysOnTop = value;
    notifyListeners();
  }

  _ComposerMode? _mode;
  int? forumId;
  String? forumName;
  int? mainPostId;

  final _draftStore = const DraftStore();
  bool _draftLoaded = false;
  bool _restoringDraft = false;
  bool _draftClearedOnSuccess = false;
  int _draftTicket = 0;

  bool get isReply => _mode == _ComposerMode.reply;

  String get windowTitle {
    return _mode == _ComposerMode.newThread
        ? '发串${forumName == null ? '' : ' · $forumName'}'
        : '回串 · No.$mainPostId';
  }

  int get wordCount => contentCtrl.text.length;
  int get lineCount => contentCtrl.text.isEmpty ? 0 : '\n'.allMatches(contentCtrl.text).length + 1;

  void init(Map<String, dynamic> args) {
    _mode = args['mode'] == 'newThread'
        ? _ComposerMode.newThread
        : _ComposerMode.reply;
    forumId = args['forumId'] as int?;
    forumName = args['forumName'] as String?;
    mainPostId = args['mainPostId'] as int?;
    selectedCookieSlotId = args['cookieSlotId'] as String?;

    final initialContent = (args['initialContent'] as String? ?? '').trimRight();
    if (initialContent.isNotEmpty) {
      contentCtrl.text = '$initialContent\n';
    }

    titleCtrl.addListener(_onDraftRelevantChanged);
    contentCtrl.addListener(_onDraftRelevantChanged);

    Future.microtask(_restoreDraftIfAny);
  }

  @override
  void dispose() {
    titleCtrl.removeListener(_onDraftRelevantChanged);
    contentCtrl.removeListener(_onDraftRelevantChanged);
    titleCtrl.dispose();
    contentCtrl.dispose();
    focusNode.dispose();
    super.dispose();
  }

  void setImagePath(String? path) {
    imagePath = path;
    _scheduleSaveDraft();
    notifyListeners();
  }

  void setWatermark(bool value) {
    watermark = value;
    _scheduleSaveDraft();
    notifyListeners();
  }

  void setSelectedCookieSlotId(String? id) {
    selectedCookieSlotId = id;
    _scheduleSaveDraft();
    notifyListeners();
  }

  void setEmoticonExpanded(bool expanded) {
    emoticonExpanded = expanded;
    notifyListeners();
  }

  void _onDraftRelevantChanged() {
    if (_restoringDraft) return;
    _scheduleSaveDraft();
  }

  void _scheduleSaveDraft() {
    if (posting) return;
    if (_draftClearedOnSuccess) return;

    final ticket = ++_draftTicket;
    Future<void>.delayed(const Duration(milliseconds: 450)).then((_) async {
      if (ticket != _draftTicket) return;
      if (_restoringDraft) return;
      await saveDraftNow();
    });
  }

  Future<void> saveDraftNow() async {
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
    final initial = (contentCtrl.text).trimRight();
    if (draft == null && initial.isEmpty) return;

    _restoringDraft = true;
    try {
      if (_mode == _ComposerMode.newThread) {
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

    await saveDraftNow();
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

  void insertAroundSelection(String before, String after) {
    final v = contentCtrl.value;
    final start = v.selection.start;
    final end = v.selection.end;
    final selectionValid = start >= 0 && end >= 0;

    if (!selectionValid) {
      contentCtrl.text += before + after;
      contentCtrl.selection =
          TextSelection.collapsed(offset: contentCtrl.text.length - after.length);
      focusNode.requestFocus();
      return;
    }

    final selected = v.text.substring(start, end);
    final newText = v.text.replaceRange(start, end, before + selected + after);
    contentCtrl.value = v.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: end + before.length + after.length),
      composing: TextRange.empty,
    );
    focusNode.requestFocus();
  }

  void insertAtCursor(String text) {
    insertText(text);
    focusNode.requestFocus();
  }
}
