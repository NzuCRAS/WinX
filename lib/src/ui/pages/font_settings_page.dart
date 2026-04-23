import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/settings_controller.dart';
import '../../data/font_config.dart';
import '../../data/system_font_scanner.dart';
import '../../data/user_font_loader.dart';
import 'package:smooth_list_view/smooth_list_view.dart';

final class FontSettingsPage extends StatefulWidget {
  const FontSettingsPage({super.key});

  @override
  State<FontSettingsPage> createState() => _FontSettingsPageState();
}

final class _FontSettingsPageState extends State<FontSettingsPage> {
  final _scanner = SystemFontScanner();
  final _userFontLoader = UserFontLoader();

  List<FontFamily>? _systemFonts;
  bool _scanning = false;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
  }

  Future<void> _scanSystemFonts() async {
    if (_scanning || _systemFonts != null) return;
    setState(() => _scanning = true);
    try {
      final fonts = await _scanner.scan();
      if (mounted) setState(() => _systemFonts = fonts);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _pickUserFont(SettingsController settings) async {
    final path = await _userFontLoader.pickAndLoadFont();
    if (path == null) return;
    final familyName = path.split(Platform.pathSeparator).last
        .replaceAll(RegExp(r'\.(ttf|otf|ttc|woff|woff2)$', caseSensitive: false), '');
    await settings.addAvailableFont(familyName);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已添加字体: $familyName')),
      );
    }
  }

  List<FontFamily> get _filteredFonts {
    final fonts = _systemFonts;
    if (fonts == null || _searchQuery.isEmpty) return fonts ?? const [];
    return fonts
        .where((f) => f.familyName.toLowerCase().contains(_searchQuery))
        .toList(growable: false);
  }

  static const _weightLabels = [
    ('normal', '常规'),
    ('bold', '粗体'),
    ('w300', '细体'),
    ('w400', '常规'),
    ('w500', '中等'),
    ('w600', '半粗'),
    ('w700', '粗体'),
  ];

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('字体管理')),
      body: SmoothListView(
        duration: const Duration(milliseconds: 350),
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          // ── Content font block ──
          _buildFontBlockCard(
            title: '内容字体',
            subtitle: '串内正文、列表预览等 API 内容',
            config: settings.contentFont,
            onConfigChanged: (v) => settings.setContentFont(v),
            fallbackAdd: settings.addContentFallbackFont,
            fallbackRemove: settings.removeContentFallbackFont,
            reorder: settings.reorderContentFallbackFonts,
            cs: cs,
            previewStyle: TextStyle(
              fontSize: settings.contentFont.fontSize,
              height: settings.contentFont.lineHeight,
              fontWeight: settings.contentFont.resolvedWeight,
              fontFamily: settings.contentFontFamily,
              fontFamilyFallback: settings.contentFontFallback,
            ),
          ),
          const SizedBox(height: 24),

          // ── UI font block ──
          _buildFontBlockCard(
            title: '界面字体',
            subtitle: '按钮、标签、侧边栏等 UI 文本',
            config: settings.uiFont,
            onConfigChanged: (v) => settings.setUiFont(v),
            fallbackAdd: settings.addUiFallbackFont,
            fallbackRemove: settings.removeUiFallbackFont,
            reorder: settings.reorderUiFallbackFonts,
            cs: cs,
            previewStyle: TextStyle(
              fontSize: settings.uiFont.fontSize,
              height: settings.uiFont.lineHeight,
              fontWeight: settings.uiFont.resolvedWeight,
              fontFamily: settings.uiFontFamily,
              fontFamilyFallback: settings.uiFontFallback,
            ),
          ),
          const SizedBox(height: 24),

          // ── Font pool (available fonts) ──
          Text('字体库',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (settings.contentFont.availableFonts.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '暂无已保存字体，请从系统字体添加或上传字体文件',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            )
          else
            _buildFontPool(settings, cs),
          const SizedBox(height: 12),

          // Add from system
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 12),
            title: const Row(
              children: [
                Icon(Icons.font_download_outlined, size: 20),
                SizedBox(width: 8),
                Text('从系统字体添加'),
              ],
            ),
            onExpansionChanged: (expanded) {
              if (expanded) _scanSystemFonts();
            },
            children: [
              TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  hintText: '搜索字体…',
                  prefixIcon: Icon(Icons.search, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 8),
              if (_scanning)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                _buildSystemFontList(settings, cs),
            ],
          ),

          // Upload
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.upload_file_outlined, size: 20),
            title: const Text('上传字体文件'),
            subtitle: const Text('支持 ttf / otf / ttc'),
            trailing: OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('选择'),
              onPressed: () => _pickUserFont(settings),
            ),
          ),

          const SizedBox(height: 24),

          const SizedBox(height: 24),

          // ── Reset ──
          Center(
            child: OutlinedButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('恢复默认设置'),
                    content: const Text('确定将字体设置恢复为默认值吗？'),
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
                  await settings.setContentFont(FontConfig());
                  await settings.setUiFont(FontConfig());
                }
              },
              icon: const Icon(Icons.restore),
              label: const Text('恢复默认字体设置'),
            ),
          ),

        ],
      ),
    );
  }

  Widget _buildFontBlockCard({
    required String title,
    required String subtitle,
    required FontConfig config,
    required ValueChanged<FontConfig> onConfigChanged,
    required Future<void> Function(String) fallbackAdd,
    required Future<void> Function(int) fallbackRemove,
    required Future<void> Function(int, int)? reorder,
    required ColorScheme cs,
    required TextStyle previewStyle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(subtitle,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),

          // Size
          Row(
            children: [
              Text('字号', style: TextStyle(color: cs.onSurfaceVariant)),
              Expanded(
                child: Slider(
                  value: config.fontSize,
                  min: 10,
                  max: 24,
                  divisions: 14,
                  label: config.fontSize.round().toString(),
                  onChanged: (v) => onConfigChanged(
                    config.copyWith(fontSize: v.roundToDouble()),
                  ),
                ),
              ),
              Text('${config.fontSize.round()}', style: const TextStyle(fontSize: 12)),
            ],
          ),

          // Weight
          Row(
            children: [
              Text('粗细', style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  isDense: true,
                  value: config.fontWeight,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: [
                    for (final (value, label) in _weightLabels)
                      DropdownMenuItem(value: value, child: Text(label)),
                  ],
                  onChanged: (v) {
                    if (v != null) onConfigChanged(config.copyWith(fontWeight: v));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Fallback list
          Text('Fallback 优先级',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          if (config.fallbackOrder.isEmpty)
            Text('使用系统默认',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))
          else
            Column(
              children: [
                for (int i = 0; i < config.fallbackOrder.length; i++) ...[
                  ListTile(
                    dense: true,
                    leading: Text('${i + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                        )),
                    title: Text(
                      config.fallbackOrder[i],
                      style: TextStyle(
                        fontFamilyFallback: [config.fallbackOrder[i]],
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (reorder != null && i > 0)
                          IconButton(
                            icon: const Icon(Icons.arrow_upward, size: 18),
                            onPressed: () => reorder(i, i - 1),
                          ),
                        if (reorder != null && i < config.fallbackOrder.length - 1)
                          IconButton(
                            icon: const Icon(Icons.arrow_downward, size: 18),
                            onPressed: () => reorder(i, i + 2),
                          ),
                        IconButton(
                          icon: Icon(Icons.close, size: 18, color: cs.error),
                          onPressed: () => fallbackRemove(i),
                        ),
                      ],
                    ),
                  ),
                  if (i < config.fallbackOrder.length - 1)
                    Divider(height: 1, color: cs.outlineVariant),
                ],
              ],
            ),
          const SizedBox(height: 12),

          // Preview
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '不要忘记超原子当量     ADNMB     ( ﾟ∀。)',
              style: previewStyle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFontPool(SettingsController settings, ColorScheme cs) {
    final pool = settings.contentFont.availableFonts;
    return Column(
      children: [
        for (final family in pool) ...[
          ListTile(
            dense: true,
            title: Text(
              family,
              style: TextStyle(fontFamilyFallback: [family]),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => settings.addContentFallbackFont(family),
                  child: const Text('内容'),
                ),
                TextButton(
                  onPressed: () => settings.addUiFallbackFont(family),
                  child: const Text('界面'),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: cs.error),
                  tooltip: '从字体库移除',
                  onPressed: () => settings.removeAvailableFont(family),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSystemFontList(SettingsController settings, ColorScheme cs) {
    final fonts = _filteredFonts;
    if (fonts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            _systemFonts == null ? '点击展开以加载系统字体' : '未找到匹配的字体',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: fonts.length,
      itemBuilder: (context, index) {
        final family = fonts[index];
        final inPool =
            settings.contentFont.availableFonts.contains(family.familyName);

        return ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
          title: Text(
            family.familyName,
            style: TextStyle(fontFamilyFallback: [family.familyName]),
          ),
          trailing: inPool
              ? Text('已保存', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))
              : TextButton(
                  onPressed: () => settings.addAvailableFont(family.familyName),
                  child: const Text('保存'),
                ),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final variant in family.variants)
                  Chip(
                    label: Text(variant, style: const TextStyle(fontSize: 11)),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
