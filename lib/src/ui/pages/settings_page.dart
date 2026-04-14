import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';

final class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
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
            selected: {app.themeMode},
            onSelectionChanged: (s) => app.setThemeMode(s.first),
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
                  value: app.contentFontSize,
                  min: 10,
                  max: 24,
                  divisions: 14,
                  label: '${app.contentFontSize.round()}',
                  onChanged: (v) => app.setContentFontSize(v.roundToDouble()),
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
                fontSize: app.contentFontSize,
                height: app.contentLineHeight,
                fontFamily: app.fontFamily.isEmpty ? null : app.fontFamily,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Font family ──
          Text('字体', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: app.fontFamily,
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
              if (v != null) app.setFontFamily(v);
            },
          ),
          const SizedBox(height: 24),

          // ── Line height ──
          Text('行间距', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Slider(
            value: app.contentLineHeight,
            min: 1.0,
            max: 2.5,
            divisions: 15,
            label: app.contentLineHeight.toStringAsFixed(1),
            onChanged: (v) =>
                app.setContentLineHeight(double.parse(v.toStringAsFixed(1))),
          ),
          const SizedBox(height: 24),

          // ── Preview max lines ──
          Text('串列表预览行数', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Slider(
            value: app.previewMaxLines.toDouble(),
            min: 3,
            max: 20,
            divisions: 17,
            label: '${app.previewMaxLines}',
            onChanged: (v) => app.setPreviewMaxLines(v.round()),
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
            value: app.autoLoadOnScroll,
            onChanged: (v) => app.setAutoLoadOnScroll(v),
          ),

          SwitchListTile(
            title: const Text('串内显示图片'),
            subtitle: const Text('关闭后串内不自动加载缩略图'),
            value: app.showImageInThread,
            onChanged: (v) => app.setShowImageInThread(v),
          ),

          const SizedBox(height: 12),
          Text('预加载触发距离', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('近'),
              Expanded(
                child: Slider(
                  value: app.threadPreloadDistance,
                  min: 100,
                  max: 600,
                  divisions: 10,
                  label: '${app.threadPreloadDistance.round()}px',
                  onChanged: (v) =>
                      app.setThreadPreloadDistance(v.roundToDouble()),
                ),
              ),
              const Text('远'),
            ],
          ),
          Text(
            '距底部 ${app.threadPreloadDistance.round()}px 时触发加载',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
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
                  await app.resetSettings();
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
