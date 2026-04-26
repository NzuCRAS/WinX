import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:smooth_list_view/smooth_list_view.dart';

import '../../../app/settings_controller.dart';

/// 将存储的快捷键字符串（如 `"Escape"`、`"Control+Enter"`）解析为 [SingleActivator]。
SingleActivator? parseShortcutActivator(String combo) {
  final parts = combo.split('+');
  var control = false;
  var shift = false;
  var alt = false;
  var meta = false;
  LogicalKeyboardKey? mainKey;

  for (final part in parts) {
    switch (part) {
      case 'Control':
        control = true;
      case 'Shift':
        shift = true;
      case 'Alt':
        alt = true;
      case 'Meta':
        meta = true;
      default:
        for (final key in LogicalKeyboardKey.knownLogicalKeys) {
          if (key.keyLabel == part) {
            mainKey = key;
            break;
          }
        }
    }
  }

  if (mainKey == null) return null;
  return SingleActivator(
    mainKey,
    control: control,
    shift: shift,
    alt: alt,
    meta: meta,
  );
}

final class ShortcutSettingsPage extends StatefulWidget {
  const ShortcutSettingsPage({super.key});

  @override
  State<ShortcutSettingsPage> createState() => _ShortcutSettingsPageState();
}

final class _ShortcutSettingsPageState extends State<ShortcutSettingsPage> {
  String? _recordingAction;

  static const _actions = [
    (
      id: 'back',
      label: '退出当前页面',
      defaultKey: 'Escape',
      description: '从串详情页、设置页等返回上一级',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final cs = Theme.of(context).colorScheme;

    return SmoothListView(
      duration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.all(16),
      children: [
        Text('快捷键',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        for (final action in _actions) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(action.label),
            subtitle: Text(action.description,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            trailing: _recordingAction == action.id
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '请按键…',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : OutlinedButton(
                    onPressed: () => _startRecording(action.id),
                    child: Text(
                      settings.shortcuts[action.id] ?? action.defaultKey,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
          ),
        ],
        const SizedBox(height: 32),
        Center(
          child: OutlinedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('恢复默认设置'),
                  content: const Text('确定将快捷键恢复为默认值吗？'),
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
                await settings.setShortcut('back', 'Escape');
              }
            },
            icon: const Icon(Icons.restore),
            label: const Text('恢复默认快捷键'),
          ),
        ),
      ],
    );
  }

  void _startRecording(String actionId) {
    setState(() => _recordingAction = actionId);
    // Listen for the next key down event.
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  bool _onKeyEvent(KeyEvent event) {
    if (_recordingAction == null) return false;
    if (event is! KeyDownEvent) return false;

    final parts = <String>[];
    if (HardwareKeyboard.instance.isControlPressed) parts.add('Control');
    if (HardwareKeyboard.instance.isShiftPressed) parts.add('Shift');
    if (HardwareKeyboard.instance.isAltPressed) parts.add('Alt');
    if (HardwareKeyboard.instance.isMetaPressed) parts.add('Meta');
    parts.add(event.logicalKey.keyLabel);

    final combo = parts.join('+');
    final settings = context.read<SettingsController>();
    settings.setShortcut(_recordingAction!, combo);

    setState(() => _recordingAction = null);
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    return true;
  }
}
