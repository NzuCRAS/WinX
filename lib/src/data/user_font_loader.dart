import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Manages user-uploaded font files.
///
/// Fonts selected by the user are copied into the application's documents
/// directory under `fonts/` so they survive even if the original file is
/// deleted. On app startup all user fonts are loaded into Flutter via
/// [FontLoader].
final class UserFontLoader {
  static const _fontsDirName = 'fonts';
  static const _appDirName = 'xdnmb_client';

  Directory? _fontsDir;

  /// Get (and create if necessary) the private fonts directory.
  Future<Directory> _getFontsDir() async {
    if (_fontsDir != null) return _fontsDir!;
    final docsDir = await getApplicationDocumentsDirectory();
    final appDir = Directory(p.join(docsDir.path, _appDirName));
    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }
    _fontsDir = Directory(p.join(appDir.path, _fontsDirName));
    if (!await _fontsDir!.exists()) {
      await _fontsDir!.create(recursive: true);
    }

    // Migrate from old location (Documents/fonts).
    final oldFontsDir = Directory(p.join(docsDir.path, _fontsDirName));
    if (await oldFontsDir.exists()) {
      await _migrateFonts(oldFontsDir, _fontsDir!);
    }

    return _fontsDir!;
  }

  /// Migrate font files from old directory to new directory.
  Future<void> _migrateFonts(Directory oldDir, Directory newDir) async {
    try {
      final files = await oldDir.list().toList();
      for (final entity in files) {
        if (entity is File) {
          final targetPath = p.join(newDir.path, p.basename(entity.path));
          final targetFile = File(targetPath);
          if (!await targetFile.exists()) {
            await entity.copy(targetPath);
          }
        }
      }
      await oldDir.delete(recursive: true);
    } catch (_) {
      // Ignore migration failures; app will still work with new directory.
    }
  }

  /// Pick a font file from disk, copy it to the app's private directory,
  /// and load it into Flutter.
  ///
  /// Returns the copied file path on success, or `null` if the user cancelled
  /// or an error occurred.
  Future<String?> pickAndLoadFont() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      allowedExtensions: const ['ttf', 'otf', 'ttc', 'woff', 'woff2'],
    );

    final originalPath = result?.files.single.path;
    if (originalPath == null || originalPath.trim().isEmpty) return null;

    try {
      final fontsDir = await _getFontsDir();
      final fileName = p.basename(originalPath);
      final targetPath = p.join(fontsDir.path, fileName);

      // Copy the file. If a file with the same name already exists,
      // overwrite it.
      final source = File(originalPath);
      await source.copy(targetPath);

      // Load into Flutter.
      await _loadFontFile(targetPath);

      return targetPath;
    } catch (e) {
      return null;
    }
  }

  /// Load all user font files from the private directory into Flutter.
  ///
  /// Call this once during app startup.
  Future<void> loadAll(List<String> paths) async {
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) {
        try {
          await _loadFontFile(path);
        } catch (_) {
          // Ignore individual font load failures.
        }
      }
    }
  }

  /// Delete a user font file from the private directory.
  Future<void> delete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore deletion failures.
    }
  }

  /// Load a single font file into Flutter's font system.
  ///
  /// The font family name is derived from the file name (without extension).
  /// Note: this is a best-effort guess. The actual family name declared
  /// inside the font file may differ, but Flutter will still register the
  /// font and match it when the family name is used in TextStyle.
  Future<void> _loadFontFile(String path) async {
    final bytes = await File(path).readAsBytes();
    final familyName = p.basenameWithoutExtension(path);
    final loader = FontLoader(familyName);
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
}
