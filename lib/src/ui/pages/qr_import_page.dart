import 'package:clipboard/clipboard.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import '../../app/cookie_controller.dart';
import '../../data/qr_cookie.dart';
import '../../data/qr_image_decoder.dart';
import 'package:smooth_list_view/smooth_list_view.dart';

final class QrImportPage extends StatefulWidget {
  const QrImportPage({super.key});

  @override
  State<QrImportPage> createState() => _QrImportPageState();
}

final class _QrImportPageState extends State<QrImportPage> {
  bool _importing = false;
  String? _last;
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _importRaw(String raw) async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _last = raw;
    });

    try {
      final payload = QrCookiePayload.fromJsonString(raw);
      final cookie = payload.toXdnmbCookie();
      await context.read<CookieController>().importCookie(cookie: cookie);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('饼干导入成功')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  Future<void> _importFromClipboard() async {
    final text = await FlutterClipboard.paste();
    if (text.trim().isEmpty) return;
    await _importRaw(text.trim());
  }

  Future<void> _importFromQrImage() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      withData: true,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
    );
    final file = res?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;

    // Desktop note:
    // We avoid asking for camera permissions; instead decode QR from image.
    // Here we accept either:
    // - raw QR content text (JSON) if user picks a .txt from clipboard
    // - QR image bytes (we'll try to decode)
    try {
  final raw = await decodeQrFromImageBytes(bytes);
      if (raw == null || raw.trim().isEmpty) {
        throw Exception('未能识别二维码内容');
      }
      await _importRaw(raw.trim());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('识别失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入饼干（二维码图片）'),
        actions: [
          IconButton(
            tooltip: '从剪贴板导入',
            onPressed: _importing ? null : _importFromClipboard,
            icon: const Icon(Icons.content_paste_go_outlined),
          ),
        ],
      ),
      body: Stack(
        children: [
          SmoothListView(
            duration: const Duration(milliseconds: 350),
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            children: [
              const Text('Windows 桌面端不走摄像头扫码，改为选取本地二维码图片导入。'),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _importing ? null : _importFromQrImage,
                icon: const Icon(Icons.image_search_outlined),
                label: const Text('选择二维码图片并导入'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _importing ? null : _importFromClipboard,
                icon: const Icon(Icons.content_paste_go_outlined),
                label: const Text('从剪贴板导入（兜底）'),
              ),
              const SizedBox(height: 10),
              if (_last != null)
                Text(
                  '最近识别：${_last!.trim()} ',
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
          if (_importing)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x99000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

/// Decode QR payload from image bytes.
///
/// Returns the raw payload string if decoded, otherwise null.
///
// QR 图片解码实现见：lib/src/data/qr_image_decoder.dart
