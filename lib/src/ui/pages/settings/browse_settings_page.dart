import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:smooth_list_view/smooth_list_view.dart';

import '../../../app/settings_controller.dart';

final class BrowseSettingsPage extends StatelessWidget {
  const BrowseSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();

    return SmoothListView(
      duration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.all(16),
      children: [
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
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                onChanged: (v) => settings.setThreadCacheTtlMinutes(v.round()),
              ),
            ),
            const Text('30分'),
          ],
        ),
        const SizedBox(height: 32),
        Center(
          child: OutlinedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('恢复默认设置'),
                  content: const Text('确定将浏览行为设置恢复为默认值吗？'),
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
                await settings.setAutoLoadOnScroll(true);
                await settings.setShowImageInThread(true);
                await settings.setShowLineBreakIndicator(true);
                await settings.setThreadPreloadDistance(240.0);
                await settings.setThreadCacheTtlMinutes(5);
              }
            },
            icon: const Icon(Icons.restore),
            label: const Text('恢复默认浏览设置'),
          ),
        ),
      ],
    );
  }
}
