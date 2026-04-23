import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_settings.dart';

/// Reads and writes the full application settings from a JSON file.
///
/// The file lives in `Documents/xdnmb_client/settings.json` so users can edit
/// it directly with an external editor.
final class SettingsFileStore {
  static const _fileName = 'settings.json';
  static const _appDirName = 'xdnmb_client';

  /// Returns the app data directory, creating it if necessary.
  Future<Directory> _getAppDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final appDir = Directory(p.join(dir.path, _appDirName));
    if (!await appDir.exists()) {
      await appDir.create();
    }
    return appDir;
  }

  Future<File> _getFile() async {
    final appDir = await _getAppDir();
    final newFile = File(p.join(appDir.path, _fileName));

    // Migrate from old location (Documents root).
    final oldFile = File(p.join(
        (await getApplicationDocumentsDirectory()).path, _fileName));
    if (await oldFile.exists() && !await newFile.exists()) {
      await oldFile.copy(newFile.path);
      await oldFile.delete();
    }

    return newFile;
  }

  /// Read settings from disk. Returns `null` if the file does not exist or
  /// cannot be parsed.
  Future<AppSettings?> read() async {
    final file = await _getFile();
    if (!await file.exists()) return null;
    try {
      final text = await file.readAsString();
      return AppSettings.fromJsonString(text);
    } catch (_) {
      return null;
    }
  }

  /// Write settings to disk with pretty-printed JSON.
  Future<void> write(AppSettings settings) async {
    final file = await _getFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
    );
  }
}
