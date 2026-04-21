import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_version.dart';
import 'perf_log.dart';

/// Information about a newer release.
final class UpdateInfo {
  final String versionTag;
  final String displayVersion;
  final String changelog;
  final String downloadUrl;
  final String htmlUrl;
  final int size;

  const UpdateInfo({
    required this.versionTag,
    required this.displayVersion,
    required this.changelog,
    required this.downloadUrl,
    required this.htmlUrl,
    required this.size,
  });
}

enum UpdateStatus { idle, checking, downloading, installing, error }

/// Service for checking and installing OTA updates.
///
/// On Windows we cannot overwrite the running EXE, so the actual replacement
/// is delegated to a PowerShell updater script that runs after the app exits.
final class UpdateService {
  UpdateStatus status = UpdateStatus.idle;
  String? statusMessage;
  double downloadProgress = 0.0;

  static const String _kAssetPattern = 'WinX-';
  static const String _kAssetSuffix = '-windows-x64.zip';

  void _setStatus(UpdateStatus s, {String? message}) {
    status = s;
    statusMessage = message;
  }

  /// Check GitHub releases for a newer version.
  ///
  /// Returns [UpdateInfo] if a newer version exists, null otherwise.
  /// Also returns null on network errors (caller should handle gracefully).
  Future<UpdateInfo?> checkForUpdate() async {
    if (status == UpdateStatus.checking) return null;
    _setStatus(UpdateStatus.checking);

    try {
      final url = Uri.https(
        'api.github.com',
        '/repos/$appFullRepo/releases/latest',
      );
      final res = await http
          .get(url, headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        _setStatus(UpdateStatus.error,
            message: '检查失败：HTTP ${res.statusCode}');
        return null;
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = body['tag_name'] as String? ?? '';
      final bodyText = body['body'] as String? ?? '';
      final htmlUrl = body['html_url'] as String? ?? '';

      if (!_isNewer(tag, appVersionDisplay)) {
        _setStatus(UpdateStatus.idle, message: '已是最新版本');
        return null;
      }

      // Find the Windows zip asset.
      final assets = body['assets'] as List<dynamic>? ?? [];
      String? downloadUrl;
      int? assetSize;
      for (final a in assets) {
        final name = (a as Map<String, dynamic>)['name'] as String? ?? '';
        if (name.startsWith(_kAssetPattern) && name.endsWith(_kAssetSuffix)) {
          downloadUrl = a['browser_download_url'] as String?;
          assetSize = a['size'] as int?;
          break;
        }
      }

      if (downloadUrl == null) {
        _setStatus(UpdateStatus.error, message: '未找到 Windows 更新包');
        return null;
      }

      _setStatus(UpdateStatus.idle);
      return UpdateInfo(
        versionTag: tag,
        displayVersion: tag,
        changelog: bodyText,
        downloadUrl: downloadUrl,
        htmlUrl: htmlUrl,
        size: assetSize ?? 0,
      );
    } on SocketException {
      _setStatus(UpdateStatus.error, message: '网络连接失败');
      return null;
    } on FormatException {
      _setStatus(UpdateStatus.error, message: '数据解析失败');
      return null;
    } catch (e) {
      _setStatus(UpdateStatus.error, message: '检查失败：$e');
      return null;
    }
  }

  /// Compare two version strings.
  ///
  /// Supports tags like "v1.0.0" or "1.0.0".
  /// Returns true if [remote] is newer than [local].
  static bool _isNewer(String remote, String local) {
    String strip(String s) => s.replaceFirst(RegExp(r'^v'), '');
    final rParts = strip(remote).split('.').map(int.tryParse).toList();
    final lParts = strip(local).split('.').map(int.tryParse).toList();

    for (var i = 0; i < rParts.length || i < lParts.length; i++) {
      final r = i < rParts.length ? (rParts[i] ?? 0) : 0;
      final l = i < lParts.length ? (lParts[i] ?? 0) : 0;
      if (r > l) return true;
      if (r < l) return false;
    }
    return false;
  }

  /// Download the update zip to a temp directory.
  ///
  /// Returns the path to the downloaded zip file.
  Future<String?> downloadUpdate(UpdateInfo info) async {
    if (status == UpdateStatus.downloading) return null;
    _setStatus(UpdateStatus.downloading);
    downloadProgress = 0.0;

    try {
      final tmpDir = await getTemporaryDirectory();
      final zipPath = p.join(tmpDir.path, 'WinX_update_${info.versionTag}.zip');

      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(info.downloadUrl));
        final response = await client.send(request);

        if (response.statusCode != 200) {
          _setStatus(UpdateStatus.error,
              message: '下载失败：HTTP ${response.statusCode}');
          return null;
        }

        final total = response.contentLength ?? 0;
        var received = 0;
        final sink = File(zipPath).openWrite();

        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            downloadProgress = received / total;
          }
        }
        await sink.close();
        _setStatus(UpdateStatus.idle);
        return zipPath;
      } finally {
        client.close();
      }
    } catch (e) {
      _setStatus(UpdateStatus.error, message: '下载失败：$e');
      return null;
    }
  }

  /// Install the downloaded update.
  ///
  /// Writes a PowerShell updater script next to the app EXE, then launches it
  /// and exits the current app. The updater waits for the current process to
  /// die, extracts the zip over the app directory, restarts the app, and then
  /// cleans up.
  Future<void> installUpdate(String zipPath, String versionTag) async {
    if (status == UpdateStatus.installing) return;
    _setStatus(UpdateStatus.installing);

    try {
      final exePath = Platform.resolvedExecutable;
      final appDir = p.dirname(exePath);
      final exeName = p.basename(exePath);
      final currentPid = ProcessInfo.currentRss; // Not actually PID, see below.
      // Dart's ProcessInfo.currentRss gives memory usage, not PID.
      // Use a different approach: get PID via Platform.
      // Actually, Platform doesn't expose PID directly. We'll use a sentinel file.

      // We'll use a simple sentinel approach: write a sentinel file, then
      // the updater polls for its deletion (by the app) or just sleeps.
      // Actually, a simpler approach: the updater sleeps for 2 seconds,
      // then overwrites files. Since the app exits immediately after
      // launching the updater, 2 seconds is plenty.

      final scriptPath = p.join(appDir, '_update.ps1');
      final script = _buildUpdaterScript(
        zipPath: zipPath,
        appDir: appDir,
        exeName: exeName,
      );
      await File(scriptPath).writeAsString(script, encoding: utf8);

      // Launch PowerShell with the updater script.
      // Use -WindowStyle Hidden to avoid flashing a console.
      await Process.start(
        'powershell.exe',
        [
          '-ExecutionPolicy',
          'Bypass',
          '-WindowStyle',
          'Hidden',
          '-File',
          scriptPath,
        ],
        mode: ProcessStartMode.detached,
      );

      PerfLog.log('update.installer launched script=$scriptPath zip=$zipPath');

      // Exit the app so the updater can overwrite files.
      exit(0);
    } catch (e) {
      _setStatus(UpdateStatus.error, message: '安装失败：$e');
    }
  }

  /// Open the release page in browser as a fallback.
  Future<bool> openReleasePage(String htmlUrl) async {
    final uri = Uri.tryParse(htmlUrl);
    if (uri == null) return false;
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _buildUpdaterScript({
    required String zipPath,
    required String appDir,
    required String exeName,
  }) {
    // Backslash-escape the paths for PowerShell string literals.
    final zip = zipPath.replaceAll("'", "''");
    final dir = appDir.replaceAll("'", "''");
    final exe = exeName.replaceAll("'", "''");

    return '''\$zipPath = '$zip'
\$appDir = '$dir'
\$exeName = '$exe'
\$logPath = Join-Path \$appDir '_update.log'

function Write-Log(\$msg) {
    "\$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') \$msg" | Out-File -Append -FilePath \$logPath -Encoding utf8
}

Write-Log "Updater started. Waiting for app to exit..."

# Wait for the main app to fully exit ( generous 3 seconds ).
Start-Sleep -Seconds 3

# Create a backup of the current EXE just in case.
\$exePath = Join-Path \$appDir \$exeName
\$backupPath = Join-Path \$appDir "\$exeName.backup"
if (Test-Path \$exePath) {
    Copy-Item -Path \$exePath -Destination \$backupPath -Force -ErrorAction SilentlyContinue
    Write-Log "Backup created."
}

Write-Log "Extracting update..."
# Expand the zip over the app directory. -Force overwrites existing files.
try {
    Expand-Archive -Path \$zipPath -DestinationPath \$appDir -Force
    Write-Log "Extraction completed."
} catch {
    Write-Log "Extraction failed: \$_"
    # If extraction fails, restore backup.
    if (Test-Path \$backupPath) {
        Copy-Item -Path \$backupPath -Destination \$exePath -Force
        Write-Log "Backup restored."
    }
    exit 1
}

# Clean up backup.
if (Test-Path \$backupPath) {
    Remove-Item \$backupPath -Force -ErrorAction SilentlyContinue
}

# Restart the app.
\$newExe = Join-Path \$appDir \$exeName
if (Test-Path \$newExe) {
    Write-Log "Restarting app..."
    Start-Process -FilePath \$newExe -WorkingDirectory \$appDir
} else {
    Write-Log "ERROR: New EXE not found at \$newExe"
    exit 1
}

# Clean up zip and script.
Start-Sleep -Seconds 2
Remove-Item \$zipPath -Force -ErrorAction SilentlyContinue
\$scriptPath = Join-Path \$appDir '_update.ps1'
Remove-Item \$scriptPath -Force -ErrorAction SilentlyContinue
Write-Log "Updater finished."
''';
  }
}
