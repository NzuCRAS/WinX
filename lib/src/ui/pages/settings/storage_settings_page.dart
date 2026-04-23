import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'package:smooth_list_view/smooth_list_view.dart';

import '../../../app/settings_controller.dart';

final class StorageSettingsPage extends StatelessWidget {
  const StorageSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();

    return SmoothListView(
      duration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const Icon(Icons.storage_outlined),
          title: const Text('数据库存储目录'),
          subtitle: Text(
            settings.databaseDirectory ?? '默认（应用数据目录）',
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
        if (Platform.isWindows) ...[
          const SizedBox(height: 32),
          Center(
            child: OutlinedButton.icon(
              onPressed: () async {
                final dir = await getApplicationDocumentsDirectory();
                final filePath =
                    '${dir.path}${Platform.pathSeparator}xdnmb_client${Platform.pathSeparator}settings.json';
                await Process.run('explorer', ['/select,', filePath]);
              },
              icon: const Icon(Icons.edit_note),
              label: const Text('打开设置文件位置'),
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
              if (ok == true) await settings.reset();
            },
            icon: const Icon(Icons.restore),
            label: const Text('恢复默认'),
          ),
        ),
      ],
    );
  }
}
