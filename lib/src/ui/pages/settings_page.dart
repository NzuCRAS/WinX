import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/settings_controller.dart';

final class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('全局设置')),
      body: ListView(
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
                fontFamily: settings.fontFamily.isEmpty ? null : settings.fontFamily,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Font family ──
          Text('字体', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: settings.fontFamily,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: const [
              DropdownMenuItem(value: '', child: Text('系统默认')),
              DropdownMenuItem(
                  value: 'Noto Sans SC', child: Text('Noto Sans SC')),
              DropdownMenuItem(
                  value: 'Noto Serif SC', child: Text('Noto Serif SC')),
              DropdownMenuItem(value: 'Microsoft YaHei', child: Text('微软雅黑')),
              DropdownMenuItem(value: 'SimSun', child: Text('宋体')),
              DropdownMenuItem(value: 'KaiTi', child: Text('楷体')),
              DropdownMenuItem(value: 'FangSong', child: Text('仿宋')),
              DropdownMenuItem(value: 'SimHei', child: Text('黑体')),
            ],
            onChanged: (v) {
              if (v != null) settings.setFontFamily(v);
            },
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
        ],
      ),
    );
  }
}
