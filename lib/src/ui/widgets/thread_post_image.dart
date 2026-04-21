import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:xdnmb_api/xdnmb_api.dart' as api;

import '../../app/settings_controller.dart';
import 'cdn_fallback_image.dart';

/// Thread post thumbnail image with full-size preview and download.
final class ThreadPostImage extends StatelessWidget {
  final api.PostBase post;

  const ThreadPostImage({super.key, required this.post});

  Future<void> _download(BuildContext context, String url) async {
    final settings = context.read<SettingsController>();
    final defaultDir = settings.downloadDirectory?.trim();
    String? targetPath;

    if (defaultDir != null && defaultDir.isNotEmpty) {
      // Ensure the directory exists before writing.
      final dir = Directory(defaultDir);
      if (!await dir.exists()) {
        try {
          await dir.create(recursive: true);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('无法创建下载目录：$e')),
            );
          }
          return;
        }
      }
      final fileName = post.imageFile ?? 'image';
      targetPath = p.join(defaultDir, fileName);
      await File(targetPath).parent.create(recursive: true);
    } else {
      targetPath = await FilePicker.platform.saveFile(
        dialogTitle: '保存原图',
        fileName: post.imageFile ?? 'image',
      );
    }

    if (targetPath == null || targetPath.isEmpty) return;

    try {
      final request = await http.Client().send(http.Request('GET', Uri.parse(url)));
      if (request.statusCode != 200) {
        throw Exception('HTTP ${request.statusCode}');
      }
      await request.stream.pipe(File(targetPath).openWrite());
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已保存至: $targetPath')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!post.hasImage) return const SizedBox.shrink();
    final showImage = context.select(
      (SettingsController s) => s.showImageInThread,
    );
    if (!showImage) {
      return const SizedBox.shrink();
    }

    final thumb = post.thumbImageUrl;
    final full = post.imageUrl;
    if (thumb == null || full == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          showDialog(
            context: context,
            builder: (context) => Dialog(
              child: _FullImageViewer(
                url: full,
                onDownload: () => _download(context, full),
              ),
            ),
          );
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CdnFallbackCachedNetworkImage(
              imageUrl: thumb,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (context, url, error) => Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('缩略图加载失败：$error'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _FullImageViewer extends StatefulWidget {
  final String url;
  final VoidCallback onDownload;

  const _FullImageViewer({required this.url, required this.onDownload});

  @override
  State<_FullImageViewer> createState() => _FullImageViewerState();
}

final class _FullImageViewerState extends State<_FullImageViewer> {
  var _nonce = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              tooltip: '刷新',
              onPressed: () => setState(() => _nonce++),
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '下载原图',
              onPressed: widget.onDownload,
              icon: const Icon(Icons.download_outlined),
            ),
            IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        Flexible(
          child: InteractiveViewer(
            minScale: 0.2,
            maxScale: 8,
            child: CdnFallbackCachedNetworkImage(
              imageUrl: '${widget.url}${widget.url.contains('?') ? '&' : '?'}_=$_nonce',
              fit: BoxFit.contain,
              placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
              errorWidget: (context, url, error) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('大图加载失败：$error'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
