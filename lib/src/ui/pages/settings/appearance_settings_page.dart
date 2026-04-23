import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:smooth_list_view/smooth_list_view.dart';

import '../../../app/settings_controller.dart';
import '../../../data/font_config.dart';
import '../font_settings_page.dart';

final class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final cs = Theme.of(context).colorScheme;

    return SmoothListView(
      duration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.all(16),
      children: [
        // ── Theme ──
        Text('主题', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
            ButtonSegment(value: ThemeMode.light, label: Text('亮色')),
            ButtonSegment(value: ThemeMode.dark, label: Text('暗色')),
          ],
          selected: {settings.themeMode},
          onSelectionChanged: (s) => settings.setThemeMode(s.first),
        ),
        const SizedBox(height: 24),

        // ── Content font size ──
        Text('内容字体大小', style: Theme.of(context).textTheme.titleSmall),
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
        const SizedBox(height: 24),

        // ── Content line height ──
        Text('内容行间距', style: Theme.of(context).textTheme.titleSmall),
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
        const SizedBox(height: 24),

        // ── Font management entry ──
        Text('字体管理', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FontSettingsPage()),
            );
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '内容: ${settings.contentFont.fallbackOrder.isEmpty ? '系统默认' : settings.contentFont.fallbackOrder.join(' > ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: settings.contentFontFamily,
                          fontFamilyFallback: settings.contentFontFallback,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '界面: ${settings.uiFont.fallbackOrder.isEmpty ? '系统默认' : settings.uiFont.fallbackOrder.join(' > ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: settings.uiFontFamily,
                          fontFamilyFallback: settings.uiFontFallback,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
        Center(
          child: OutlinedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('恢复默认设置'),
                  content: const Text('确定将外观设置恢复为默认值吗？'),
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
                await settings.setThemeMode(ThemeMode.system);
                await settings.setPreviewMaxLines(10);
                await settings.setContentFont(FontConfig());
                await settings.setUiFont(FontConfig());
              }
            },
            icon: const Icon(Icons.restore),
            label: const Text('恢复默认外观设置'),
          ),
        ),
      ],
    );
  }
}
