import 'package:flutter/material.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../app/settings_controller.dart';
import '../widgets/cdn_fallback_image.dart';

/// Start page shown when app launches.
///
/// Matches the user's screenshot style:
/// - top: island badge gif
/// - middle: banner gif
///
/// Assets live in /assets.
final class StartPage extends StatelessWidget {
  final Uri? randomCoverUrl;
  final bool randomCoverLoading;
  final String? randomCoverError;
  final int randomCoverNonce;

  const StartPage({
    super.key,
    this.randomCoverUrl,
    this.randomCoverLoading = false,
    this.randomCoverError,
    this.randomCoverNonce = 0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surface,
      child: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/岛徽.gif',
                  width: 120,
                  height: 120,
                  filterQuality: FilterQuality.high,
                ),
                const SizedBox(height: 16),
                Text(
                  'X岛揭示板',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: cs.onSurface),
                ),
                const SizedBox(height: 16),
                _buildRandomCover(context, cs),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Text(
                    '“人，是会思考的芦苇。”——帕斯卡，《思想录》\n'
                    '“开放包容 理性客观 有事说事 就事论事 顺便者自觉被害亡”',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
                  ),
                ),
                const SizedBox(height: 18),
                Image.asset(
                  'assets/横幅.gif',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
                const SizedBox(height: 20),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '以下是一些系统设定：',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      _bullet(context, '【PO】指代楼主，发文可以用 >> 或者文字进行引用，点击 No. 编号也可以。'),
                      _bullet(context, '部分版块需要饼干才可进入，饼干可在“用户”页导入与切换。'),
                      _bullet(context, '如遇无法访问/加载失败，可尝试在侧栏切换版块或下拉刷新。'),
                      _bullet(context, '本客户端为第三方阅读器，仅做浏览与发言辅助，不提供账号系统。'),
                      const SizedBox(height: 14),
                      Text(
                        '从左侧选择版块开始浏览。',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        '免责声明：本站无法保证用户张贴内容的可靠性，投资有风险，健康问题请遵医嘱。',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRandomCover(BuildContext context, ColorScheme cs) {
    if (randomCoverUrl == null) {
      return Container(
        alignment: Alignment.center,
        height: 300,
        width: double.infinity,
        child: Text(
          randomCoverLoading
              ? '随机封面图加载中…'
              : (randomCoverError != null
                  ? '随机封面图加载失败'
                  : '随机封面图加载中…'),
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    return InkWell(
      onTap: () => _openFullScreenPreview(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(
          minHeight: 250,
          maxHeight: 400,
        ),
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: CdnFallbackCachedNetworkImage(
              // Random cover changes on refresh; but avoid forcing cache-bypass for
              // every rebuild. We only bump nonce when the cover URL changes.
              imageUrl: '${randomCoverUrl.toString()}${randomCoverUrl.toString().contains('?') ? '&' : '?'}_=$randomCoverNonce',
              fit: BoxFit.contain,
              placeholder: (context, url) => Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.broken_image_outlined),
                    const SizedBox(height: 8),
                    Text('图片加载失败', style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _downloadRandomCover(BuildContext context) async {
    if (randomCoverUrl == null) return;
    final settings = context.read<SettingsController>();
    final defaultDir = settings.downloadDirectory;
    final dir = (defaultDir != null && defaultDir.trim().isNotEmpty)
        ? defaultDir.trim()
        : (Platform.environment['USERPROFILE'] ??
            Platform.environment['HOME'] ??
            '.');
    final fileName = 'xdnmb_cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final targetPath = p.join(dir, fileName);
    await File(targetPath).parent.create(recursive: true);

    try {
      final request = await http.Client().send(
        http.Request('GET', Uri.parse(randomCoverUrl.toString())),
      );
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

  void _openFullScreenPreview(BuildContext context) {
    if (randomCoverUrl == null) return;
    var nonce = 0;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final url = nonce > 0
              ? '${randomCoverUrl.toString()}${randomCoverUrl.toString().contains('?') ? '&' : '?'}_=$nonce'
              : randomCoverUrl.toString();
          return Dialog(
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Text(
                            '由于岛的api设计，看到的图和下载的图都是随机的( ﾟ∀。)7',
                            style: Theme.of(ctx).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '刷新',
                        onPressed: () => setState(() => nonce++),
                        icon: const Icon(Icons.refresh),
                      ),
                      IconButton(
                        tooltip: '下载原图',
                        onPressed: () => _downloadRandomCover(ctx),
                        icon: const Icon(Icons.download_outlined),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Flexible(
                    child: InteractiveViewer(
                      minScale: 0.2,
                      maxScale: 8,
                      child: CdnFallbackCachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(),
                        ),
                        errorWidget: (context, url, error) => Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('图片加载失败：$error'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

Widget _bullet(BuildContext context, String text) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            Icons.circle,
            size: 8,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurface),
          ),
        ),
      ],
    ),
  );
}

