import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:smooth_list_view/smooth_list_view.dart';

import '../../app/settings_controller.dart';
import 'font_settings_page.dart';
import 'settings/appearance_settings_page.dart';
import 'settings/browse_settings_page.dart';
import 'settings/shortcut_settings_page.dart';
import 'settings/storage_settings_page.dart';
import 'settings/debug_settings_page.dart';
import 'settings/about_settings_page.dart';

final class BackIntent extends Intent {
  const BackIntent();
}

final class SettingsShellPage extends StatefulWidget {
  const SettingsShellPage({super.key});

  @override
  State<SettingsShellPage> createState() => _SettingsShellPageState();
}

final class _SettingsShellPageState extends State<SettingsShellPage> {
  int _selectedIndex = 0;

  static const _destinations = [
    (label: '外观', icon: Icons.palette_outlined),
    (label: '浏览', icon: Icons.travel_explore_outlined),
    (label: '字体', icon: Icons.font_download_outlined),
    (label: '快捷键', icon: Icons.keyboard_outlined),
    (label: '存储', icon: Icons.storage_outlined),
    (label: '调试', icon: Icons.bug_report_outlined),
    (label: '关于', icon: Icons.info_outline),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = const [
      AppearanceSettingsPage(),
      BrowseSettingsPage(),
      FontSettingsPage(),
      ShortcutSettingsPage(),
      StorageSettingsPage(),
      DebugSettingsPage(),
      AboutSettingsPage(),
    ];

    final settings = context.watch<SettingsController>();
    final backShortcut = parseShortcutActivator(
      settings.shortcuts['back'] ?? 'Escape',
    );

    return Shortcuts(
      shortcuts: {
        if (backShortcut != null)
          backShortcut: const BackIntent(),
      },
      child: Actions(
        actions: {
          BackIntent: CallbackAction<BackIntent>(
            onInvoke: (_) {
              Navigator.of(context).pop();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(title: const Text('全局设置')),
            body: Row(
              children: [
                // Sidebar navigation
                Container(
                  width: 160,
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: SmoothListView.builder(
                    duration: const Duration(milliseconds: 350),
                    itemCount: _destinations.length,
                    itemBuilder: (context, index) {
                      final d = _destinations[index];
                      final selected = _selectedIndex == index;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          d.icon,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        title: Text(
                          d.label,
                          style: TextStyle(
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            fontWeight: selected ? FontWeight.w600 : null,
                          ),
                        ),
                        selected: selected,
                        onTap: () => setState(() => _selectedIndex = index),
                      );
                    },
                  ),
                ),
                // Content area
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: pages,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
