import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'image_editor/editor_toolbar.dart';
import 'image_editor/image_edit_state.dart';
import 'image_editor/image_editor_exporter.dart';

/// Standalone image viewer/editor window.
/// Supports zoom, rotate, and flip.
final class ImageViewerWindowPage extends StatefulWidget {
  final String imagePath;
  final String? title;

  const ImageViewerWindowPage({super.key, required this.imagePath, this.title});

  @override
  State<ImageViewerWindowPage> createState() => _ImageViewerWindowPageState();
}

final class _ImageViewerWindowPageState extends State<ImageViewerWindowPage> {
  final _transformationController = TransformationController();

  ImageEditState _editState = const ImageEditState();
  bool _isExporting = false;

  // Cached image bytes to avoid re-reading from disk on every rebuild.
  Uint8List? _imageBytes;

  @override
  void initState() {
    super.initState();
    _loadImage();
    _setWindowTitle();
  }

  Future<void> _setWindowTitle() async {
    final title = widget.title;
    if (title != null && title.isNotEmpty) {
      await windowManager.setTitle(title);
    }
  }

  Future<void> _loadImage() async {
    try {
      final file = File(widget.imagePath);
      final bytes = await file.readAsBytes();
      if (mounted) {
        setState(() => _imageBytes = bytes);
      }
    } catch (_) {
      // ignore
    }
  }

  double get _rotationAngle => _editState.rotation * math.pi / 2;

  Matrix4 get _flipMatrix {
    final m = Matrix4.identity();
    if (_editState.flippedH) m.scale(-1.0, 1.0, 1.0);
    if (_editState.flippedV) m.scale(1.0, -1.0, 1.0);
    return m;
  }

  void _reset() {
    _transformationController.value = Matrix4.identity();
    setState(() => _editState = const ImageEditState());
  }

  void _rotateLeft() => setState(() => _editState = _editState.copyWith(
        rotation: (_editState.rotation - 1) % 4,
      ));
  void _rotateRight() => setState(() => _editState = _editState.copyWith(
        rotation: (_editState.rotation + 1) % 4,
      ));
  void _flipHorizontal() => setState(() => _editState = _editState.copyWith(
        flippedH: !_editState.flippedH,
      ));
  void _flipVertical() => setState(() => _editState = _editState.copyWith(
        flippedV: !_editState.flippedV,
      ));

  Future<void> _applyAndSave() async {
    // Even if no edits, still notify with the original path so the caller
    // knows we're done.
    if (!_editState.hasEdits) {
      try {
        final mainWindow = WindowController.fromWindowId('0');
        await mainWindow.invokeMethod('imageEdited', {
          'originalPath': widget.imagePath,
          'newPath': widget.imagePath,
        });
      } catch (_) {}
      return;
    }

    setState(() => _isExporting = true);

    try {
      final newPath = await exportEditedImage(
        sourcePath: widget.imagePath,
        state: _editState,
      );

      // Notify the parent window
      try {
        final mainWindow = WindowController.fromWindowId('0');
        await mainWindow.invokeMethod('imageEdited', {
          'originalPath': widget.imagePath,
          'newPath': newPath,
        });
      } catch (_) {
        // Best-effort only
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已应用编辑')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Base image with rotation/flip and zoom
          Positioned.fill(
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 0.1,
              maxScale: 10,
              child: Center(
                child: Transform(
                  alignment: Alignment.center,
                  transform: _flipMatrix,
                  child: Transform.rotate(
                    angle: _rotationAngle,
                    child: SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: _imageBytes != null
                          ? Image.memory(
                              _imageBytes!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Text(
                                  '无法加载图片',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ),
                            )
                          : const Center(
                              child: CircularProgressIndicator(),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom toolbar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: EditorToolbar(
              activeTool: EditorTool.none,
              hasEdits: _editState.hasEdits,
              isExporting: _isExporting,
              onToolChanged: (_) {},
              onReset: _reset,
              onRotateLeft: _rotateLeft,
              onRotateRight: _rotateRight,
              onFlipH: _flipHorizontal,
              onFlipV: _flipVertical,
              onApply: _applyAndSave,
            ),
          ),
        ],
      ),
    );
  }
}
