import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:smooth_list_view/smooth_list_view.dart';

import '../../../app/settings_controller.dart';

final class DebugSettingsPage extends StatelessWidget {
  const DebugSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();

    return SmoothListView(
      duration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: const Text('启用调试输出'),
          subtitle:
              const Text('输出网络请求排队/耗时等诊断信息（建议仅排查问题时开启）'),
          value: settings.enableDebugLog,
          onChanged: (v) => settings.setEnableDebugLog(v),
        ),
        const SizedBox(height: 32),
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
    );
  }
}
