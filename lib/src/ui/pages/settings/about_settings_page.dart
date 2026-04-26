import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:smooth_list_view/smooth_list_view.dart';

import '../../../app/settings_controller.dart';
import '../../../data/app_version.dart';
import '../../../data/update_service.dart';

final class AboutSettingsPage extends StatefulWidget {
  const AboutSettingsPage({super.key});

  @override
  State<AboutSettingsPage> createState() => _AboutSettingsPageState();
}

final class _AboutSettingsPageState extends State<AboutSettingsPage> {
  final _updateService = UpdateService();
  UpdateInfo? _pendingUpdate;

  @override
  void initState() {
    super.initState();
    _updateService.addListener(_onUpdateChanged);
  }

  @override
  void dispose() {
    _updateService.removeListener(_onUpdateChanged);
    _updateService.dispose();
    super.dispose();
  }

  void _onUpdateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();

    return SmoothListView(
      duration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.all(16),
      children: [
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
        const SizedBox(height: 32),
        Center(
          child: OutlinedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('恢复默认设置'),
                  content: const Text('确定将更新设置恢复为默认值吗？'),
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
                await settings.setAutoCheckUpdate(true);
              }
            },
            icon: const Icon(Icons.restore),
            label: const Text('恢复默认更新设置'),
          ),
        ),
      ],
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
    setState(() => _pendingUpdate = info);

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
      if (ok == true && mounted) await _handleInstallUpdate(context);
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
