import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/settings_controller.dart';
import '../../data/app_version.dart';
import '../../data/update_service.dart';
import 'package:smooth_list_view/smooth_list_view.dart';
import 'font_settings_page.dart';

final class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

final class _SettingsPageState extends State<SettingsPage> {
  final _updateService = UpdateService();
  UpdateInfo? _pendingUpdate;
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('全局设置')),
      body: SmoothListView(
        duration: const Duration(milliseconds: 350),
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          // ── Theme ──
          Text('主题', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                  value: ThemeMode.system, label: Text('跟随系统')),
              ButtonSegment(value: ThemeMode.light, label: Text('亮色')),
              ButtonSegment(value: ThemeMode.dark, label: Text('暗色')),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (s) => settings.setThemeMode(s.first),
          ),
          const SizedBox(height: 24),

          // ── Font size ──
          Text('正文字体大小', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('A', style: TextStyle(fontSize: 10)),
              Expanded(
                child: Slider(
                  value: settings.contentFontSize,
                  min: 10,
                  max: 24,
                  divisions: 14,
                  label: '${settings.contentFontSize.round()}',
                  onChanged: (v) => settings.setContentFontSize(v.roundToDouble()),
                ),
              ),
              const Text('A', style: TextStyle(fontSize: 24)),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '预览文字：X岛匿名版是一个匿名讨论社区。',
              style: TextStyle(
                fontSize: settings.contentFontSize,
                height: settings.contentLineHeight,
                fontWeight: settings.contentFontWeight,
                fontFamily: settings.contentFontFamily,
                fontFamilyFallback: settings.fontFamilyFallback,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Font family ──
          Text('字体', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const FontSettingsPage(),
                ),
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      settings.contentFont.fallbackOrder.isEmpty
                          ? '系统默认'
                          : settings.contentFont.fallbackOrder.join(' > '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: settings.contentFontFamily,
                        fontFamilyFallback: settings.contentFontFallback,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Line height ──
          Text('行间距', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Slider(
            value: settings.contentLineHeight,
            min: 1.0,
            max: 2.5,
            divisions: 15,
            label: settings.contentLineHeight.toStringAsFixed(1),
            onChanged: (v) =>
                settings.setContentLineHeight(double.parse(v.toStringAsFixed(1))),
          ),
          const SizedBox(height: 24),

          // ── Preview max lines ──
          Text('串列表预览行数', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Slider(
            value: settings.previewMaxLines.toDouble(),
            min: 3,
            max: 20,
            divisions: 17,
            label: '${settings.previewMaxLines}',
            onChanged: (v) => settings.setPreviewMaxLines(v.round()),
          ),
          const SizedBox(height: 32),

          // ── Behavior section ──
          Text('浏览行为',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),

          SwitchListTile(
            title: const Text('自动滚动加载'),
            subtitle: const Text('关闭后仅通过点击按钮加载更多'),
            value: settings.autoLoadOnScroll,
            onChanged: (v) => settings.setAutoLoadOnScroll(v),
          ),

          SwitchListTile(
            title: const Text('串内显示图片'),
            subtitle: const Text('关闭后串内不自动加载缩略图'),
            value: settings.showImageInThread,
            onChanged: (v) => settings.setShowImageInThread(v),
          ),

          SwitchListTile(
            title: const Text('显示换行标记'),
            subtitle: const Text('在内容中的主动换行处显示 ↩ 符号'),
            value: settings.showLineBreakIndicator,
            onChanged: (v) => settings.setShowLineBreakIndicator(v),
          ),

          const SizedBox(height: 12),
          Text('预加载触发距离', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('近'),
              Expanded(
                child: Slider(
                  value: settings.threadPreloadDistance,
                  min: 100,
                  max: 600,
                  divisions: 10,
                  label: '${settings.threadPreloadDistance.round()}px',
                  onChanged: (v) =>
                      settings.setThreadPreloadDistance(v.roundToDouble()),
                ),
              ),
              const Text('远'),
            ],
          ),
          Text(
            '距底部 ${settings.threadPreloadDistance.round()}px 时触发加载',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),

          const SizedBox(height: 24),
          Text('串缓存保留时间', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('1分'),
              Expanded(
                child: Slider(
                  value: settings.threadCacheTtlMinutes.toDouble(),
                  min: 1,
                  max: 30,
                  divisions: 29,
                  label: '${settings.threadCacheTtlMinutes}分钟',
                  onChanged: (v) =>
                      settings.setThreadCacheTtlMinutes(v.round()),
                ),
              ),
              const Text('30分'),
            ],
          ),
          Text(
            '退出串后 ${settings.threadCacheTtlMinutes} 分钟移除缓存',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),

          const SizedBox(height: 24),

          // ── Debug ──
          Text('调试', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('启用调试输出'),
            subtitle: const Text('输出网络请求排队/耗时等诊断信息（建议仅排查问题时开启）'),
            value: settings.enableDebugLog,
            onChanged: (v) => settings.setEnableDebugLog(v),
          ),

          const SizedBox(height: 32),

          // ── Storage ──
          Text('存储',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),

          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('数据库存储目录'),
            subtitle: Text(
              settings.databaseDirectory ?? '默认（应用文档目录）',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (settings.databaseDirectory != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => settings.setDatabaseDirectory(null),
                  ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () async {
              final result = await FilePicker.platform.getDirectoryPath(
                dialogTitle: '选择数据库存储目录',
                initialDirectory: settings.databaseDirectory,
              );
              if (result != null) {
                await settings.setDatabaseDirectory(result);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('数据库路径已更改，重启应用后生效')),
                  );
                }
              }
            },
          ),

          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('默认图片下载目录'),
            subtitle: Text(
              settings.downloadDirectory ?? '每次手动选择',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (settings.downloadDirectory != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => settings.setDownloadDirectory(null),
                  ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () async {
              final result = await FilePicker.platform.getDirectoryPath(
                dialogTitle: '选择默认图片下载目录',
                initialDirectory: settings.downloadDirectory,
              );
              if (result != null) {
                await settings.setDownloadDirectory(result);
              }
            },
          ),

          const SizedBox(height: 32),

          // ── Reset ──
          Center(
            child: OutlinedButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('恢复默认设置'),
                    content: const Text('确定将所有设置恢复为默认值吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await settings.reset();
                }
              },
              icon: const Icon(Icons.restore),
              label: const Text('恢复默认'),
            ),
          ),

          const SizedBox(height: 32),

          // ── About / Update ──
          Text('关于与更新',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),

          if (Platform.isWindows) ...[
            SwitchListTile(
              title: const Text('启动时自动检查更新'),
              subtitle: const Text('每天最多检查一次'),
              value: settings.autoCheckUpdate,
              onChanged: (v) => settings.setAutoCheckUpdate(v),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.system_update_outlined),
              title: const Text('检查更新'),
              subtitle: Text(
                _updateSubtitle(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: _updateTrailing(),
              onTap: () => _handleCheckUpdate(context),
            ),
          ],

          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('当前版本'),
            subtitle: Text(appVersionDisplay),
          ),
        ],
      ),
    );
  }

  String _updateSubtitle() {
    final s = _updateService.status;
    final msg = _updateService.statusMessage;
    switch (s) {
      case UpdateStatus.checking:
        return '检查中…';
      case UpdateStatus.downloading:
        return '下载中 ${(_updateService.downloadProgress * 100).toStringAsFixed(0)}%';
      case UpdateStatus.installing:
        return '正在安装…';
      case UpdateStatus.error:
        return msg ?? '检查失败';
      case UpdateStatus.idle:
        if (_pendingUpdate != null) {
          return '新版本 ${_pendingUpdate!.displayVersion} 可用';
        }
        return '已是最新版本';
    }
  }

  Widget? _updateTrailing() {
    final s = _updateService.status;
    if (s == UpdateStatus.checking ||
        s == UpdateStatus.downloading ||
        s == UpdateStatus.installing) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_pendingUpdate != null) {
      return FilledButton(
        onPressed: () => _handleInstallUpdate(context),
        child: const Text('更新'),
      );
    }
    return null;
  }

  Future<void> _handleCheckUpdate(BuildContext context) async {
    setState(() => _pendingUpdate = null);
    final info = await _updateService.checkForUpdate();
    if (!mounted) return;
    setState(() {
      _pendingUpdate = info;
    });

    if (info != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('发现新版本 ${info.displayVersion}'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('更新内容：',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(info.changelog.isEmpty ? '（无更新说明）' : info.changelog),
                  const SizedBox(height: 16),
                  Text(
                    '大小：${(info.size / 1024 / 1024).toStringAsFixed(1)} MB',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('稍后'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('立即更新'),
            ),
          ],
        ),
      );
      if (ok == true && mounted) {
        await _handleInstallUpdate(context);
      }
    } else if (_updateService.status == UpdateStatus.idle) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已是最新版本')),
      );
    }
  }

  Future<void> _handleInstallUpdate(BuildContext context) async {
    final info = _pendingUpdate;
    if (info == null) return;

    final zipPath = await _updateService.downloadUpdate(info);
    if (zipPath == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败：${_updateService.statusMessage}')),
      );
      return;
    }

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('准备安装'),
        content: const Text(
          '应用将关闭以完成更新。\n更新不会删除您的本地数据、浏览历史、设置和饼干。\n\n确定继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _updateService.installUpdate(zipPath, info.versionTag);
    }
  }
}
