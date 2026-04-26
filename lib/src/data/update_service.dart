import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
///
/// Extends [ChangeNotifier] so the UI can react to status / progress changes.
final class UpdateService extends ChangeNotifier {
  UpdateStatus _status = UpdateStatus.idle;
  String? _statusMessage;
  double _downloadProgress = 0.0;

  UpdateStatus get status => _status;
  String? get statusMessage => _statusMessage;
  double get downloadProgress => _downloadProgress;

  /// Asset filename pattern. Accepts:
  ///   - 2- or 3-segment versions (`1.3`, `1.3.0`)
  ///   - optional `v` prefix on the version
  ///   - optional pre-release suffix (`-rc.1`, `-beta`)
  /// Excludes symbols/debug variants via [assetBlacklistRegex].
  @visibleForTesting
  static final RegExp assetRegex = RegExp(
    r'^WinX-v?\d+\.\d+(?:\.\d+)?(?:-[\w.]+)?-windows-x64\.zip$',
  );

  /// Keywords that disqualify a release asset even if it matches [assetRegex].
  /// `WinX-1.0.0-symbols-windows-x64.zip` would otherwise be mis-read as a
  /// `-symbols` pre-release.
  @visibleForTesting
  static final RegExp assetBlacklistRegex = RegExp(
    r'-(?:symbols|symbol|debug|dbg|pdb)\b',
    caseSensitive: false,
  );

  /// Returns true iff [name] looks like the release zip we want.
  @visibleForTesting
  static bool isReleaseAsset(String name) =>
      assetRegex.hasMatch(name) && !assetBlacklistRegex.hasMatch(name);

  void _setStatus(UpdateStatus s, {String? message}) {
    _status = s;
    _statusMessage = message;
    notifyListeners();
  }

  /// Check GitHub releases for a newer version.
  ///
  /// Returns [UpdateInfo] if a newer version exists, null otherwise.
  /// Also returns null on network errors (caller should handle gracefully).
  Future<UpdateInfo?> checkForUpdate() async {
    if (_status == UpdateStatus.checking) return null;
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
      final isPrerelease = body['prerelease'] as bool? ?? false;

      if (isPrerelease) {
        _setStatus(UpdateStatus.idle, message: '已是最新版本');
        return null;
      }

      if (!isNewerVersion(tag, appVersionDisplay)) {
        _setStatus(UpdateStatus.idle, message: '已是最新版本');
        return null;
      }

      // Find the Windows zip asset. Prefer exact-version filename; fall back
      // to a regex match that excludes symbol/debug variants.
      // Some releases keep the `v` prefix in the asset name (e.g.
      // `WinX-v1.3-windows-x64.zip`), some don't. Try both.
      final assets = body['assets'] as List<dynamic>? ?? [];
      final tagNoV = tag.startsWith('v') ? tag.substring(1) : tag;
      final preferredNames = <String>{
        'WinX-$tag-windows-x64.zip',
        'WinX-$tagNoV-windows-x64.zip',
      };
      String? downloadUrl;
      int? assetSize;

      for (final a in assets) {
        final name = (a as Map<String, dynamic>)['name'] as String? ?? '';
        if (preferredNames.contains(name)) {
          downloadUrl = a['browser_download_url'] as String?;
          assetSize = a['size'] as int?;
          break;
        }
      }
      if (downloadUrl == null) {
        for (final a in assets) {
          final name = (a as Map<String, dynamic>)['name'] as String? ?? '';
          if (isReleaseAsset(name)) {
            downloadUrl = a['browser_download_url'] as String?;
            assetSize = a['size'] as int?;
            break;
          }
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
  /// Supports tags like "v1.0.0" or "1.0.0". Pre-release suffixes (e.g.
  /// "-rc.1") are stripped before comparison.
  /// Returns true if [remote] is newer than [local].
  @visibleForTesting
  static bool isNewerVersion(String remote, String local) {
    String strip(String s) {
      final stripped = s.replaceFirst(RegExp(r'^v'), '');
      final dash = stripped.indexOf('-');
      return dash >= 0 ? stripped.substring(0, dash) : stripped;
    }
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
    if (_status == UpdateStatus.downloading) return null;
    _downloadProgress = 0.0;
    _setStatus(UpdateStatus.downloading);

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
        var lastNotified = 0.0;
        final sink = File(zipPath).openWrite();

        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            _downloadProgress = received / total;
            // Throttle UI notifications to ~every 0.5% to avoid burning frames.
            if (_downloadProgress - lastNotified >= 0.005 ||
                _downloadProgress >= 1.0) {
              lastNotified = _downloadProgress;
              notifyListeners();
            }
          }
        }
        await sink.close();

        // Sanity check: verify the downloaded size matches what GitHub
        // advertised. Mismatches indicate a truncated download.
        if (info.size > 0) {
          final actual = await File(zipPath).length();
          if (actual != info.size) {
            _setStatus(UpdateStatus.error,
                message: '下载文件大小异常 (期望 ${info.size}，实际 $actual)');
            try {
              await File(zipPath).delete();
            } catch (_) {}
            return null;
          }
        }

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
  /// Writes a PowerShell updater script under `%LOCALAPPDATA%\WinX\update\`,
  /// then launches it and exits the current app. The updater waits for the
  /// current process to exit, extracts the zip, applies it over the app
  /// directory with a full backup, restarts the app, and cleans up. On any
  /// extraction or copy failure the backup is restored.
  Future<void> installUpdate(String zipPath, String versionTag) async {
    if (_status == UpdateStatus.installing) return;
    _setStatus(UpdateStatus.installing);

    try {
      final exePath = Platform.resolvedExecutable;
      final appDir = p.dirname(exePath);
      final exeName = p.basename(exePath);

      // Workspace under LOCALAPPDATA so we never need to write inside an
      // installation directory like Program Files.
      final localAppData = Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['USERPROFILE'] ??
          appDir;
      final updateRoot = p.join(localAppData, 'WinX', 'update');
      await Directory(updateRoot).create(recursive: true);

      final scriptPath = p.join(updateRoot, '_update.ps1');
      final batPath = p.join(updateRoot, '_run_updater.bat');
      final logPath = p.join(updateRoot, '_update.log');
      final expectedSize = await File(zipPath).length();
      final script = _buildUpdaterScript(
        zipPath: zipPath,
        appDir: appDir,
        exeName: exeName,
        updateRoot: updateRoot,
        expectedSize: expectedSize,
      );
      await File(scriptPath).writeAsString(script, encoding: utf8);

      // Trampoline batch: cmd's `start /b` does a real BREAKAWAY_FROM_JOB so
      // the PS process keeps running after Dart exits, even if the Dart
      // parent was inside a Job Object (which Dart's detached mode does not
      // by itself escape from).
      await File(batPath).writeAsString(
        '@echo off\r\n'
        'echo %DATE% %TIME% [bat] launching ps>> "$logPath"\r\n'
        'start "" /b powershell.exe -NoProfile -ExecutionPolicy Bypass '
        '-WindowStyle Hidden -File "$scriptPath"\r\n',
        encoding: utf8,
      );

      // Diagnostic breadcrumb so we can tell whether the PS script ever ran:
      // - only [dart] line   → cmd never ran the bat
      // - [dart] + [bat]     → bat ran but PS process didn't survive
      // - [dart] + [bat] + [ps] script entry  → PS started, look for FATAL
      final stamp = DateTime.now().toIso8601String();
      await File(logPath).writeAsString(
        '$stamp [dart] installer prepared. '
        'script=$scriptPath zip=$zipPath appDir=$appDir size=$expectedSize\n',
        mode: FileMode.append,
        encoding: utf8,
      );

      await Process.start(
        'cmd.exe',
        ['/c', batPath],
        mode: ProcessStartMode.detached,
      );

      PerfLog.log('update.installer launched script=$scriptPath zip=$zipPath');

      // Give the OS a moment to spawn cmd → bat → start → powershell. Without
      // this delay we sometimes exit before `start` has detached the PS child.
      await Future<void>.delayed(const Duration(milliseconds: 800));

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
    required String updateRoot,
    required int expectedSize,
  }) {
    String esc(String s) => s.replaceAll("'", "''");

    return '''\$zipPath      = '${esc(zipPath)}'
\$appDir       = '${esc(appDir)}'
\$exeName      = '${esc(exeName)}'
\$updateRoot   = '${esc(updateRoot)}'
\$expectedSize = $expectedSize

\$logPath    = Join-Path \$updateRoot '_update.log'
\$extractDir = Join-Path \$updateRoot 'extracted'
\$backupDir  = Join-Path \$updateRoot 'backup'

function Write-Log(\$msg) {
    try {
        if (-not (Test-Path \$updateRoot)) {
            New-Item -ItemType Directory -Path \$updateRoot -Force | Out-Null
        }
        "\$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [ps] \$msg" | Out-File -Append -FilePath \$logPath -Encoding utf8
    } catch {
        \$emergency = Join-Path \$env:TEMP 'winx_updater_emergency.log'
        "\$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [ps-fallback] \$msg | logwrite-fail: \$_" | Out-File -Append -FilePath \$emergency -Encoding utf8
    }
}

function Restore-Backup() {
    if (-not (Test-Path \$backupDir)) { return }
    Write-Log "Restoring from backup..."
    Get-ChildItem -Path \$backupDir -Force | ForEach-Object {
        try {
            Copy-Item -Path \$_.FullName -Destination \$appDir -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Log "WARN: Failed to restore \$(\$_.Name): \$_"
        }
    }
}

# Trap any uncaught error — make sure something is recorded.
trap {
    Write-Log "FATAL: \$(\$_.Exception.Message)"
    Write-Log "STACK: \$(\$_.ScriptStackTrace)"
    exit 99
}

# Earliest possible breadcrumb. If the log shows [dart] but no [ps] line,
# PowerShell never started; if it shows this line but nothing after,
# something blew up between here and the next Write-Log.
Write-Log "script entry pid=\$PID host=\$(\$Host.Name) psver=\$(\$PSVersionTable.PSVersion)"

# Ensure workspace and reset transient dirs.
New-Item -ItemType Directory -Path \$updateRoot -Force | Out-Null
if (Test-Path \$extractDir) { Remove-Item -Path \$extractDir -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path \$backupDir)  { Remove-Item -Path \$backupDir  -Recurse -Force -ErrorAction SilentlyContinue }

Write-Log "Updater started. zip=\$zipPath appDir=\$appDir"

# 1) Wait for the app process to exit (by base name, max 30s).
\$baseExe = [System.IO.Path]::GetFileNameWithoutExtension(\$exeName)
\$maxWait = 30.0
\$elapsed = 0.0
while (\$elapsed -lt \$maxWait) {
    \$procs = Get-Process -Name \$baseExe -ErrorAction SilentlyContinue
    if (-not \$procs) { break }
    Start-Sleep -Milliseconds 500
    \$elapsed += 0.5
}
if (\$elapsed -ge \$maxWait) {
    Write-Log "WARN: process '\$baseExe' did not exit within \$maxWait s, proceeding anyway"
}

# 2) Verify zip size.
if (\$expectedSize -gt 0) {
    if (-not (Test-Path \$zipPath)) { Write-Log "ERROR: zip missing: \$zipPath"; exit 1 }
    \$actualSize = (Get-Item \$zipPath).Length
    if (\$actualSize -ne \$expectedSize) {
        Write-Log "ERROR: zip size mismatch (expected=\$expectedSize actual=\$actualSize)"
        exit 1
    }
}

# 3) Extract to staging dir.
Write-Log "Extracting to \$extractDir"
try {
    Expand-Archive -Path \$zipPath -DestinationPath \$extractDir -Force
} catch {
    Write-Log "ERROR: extract failed: \$_"
    exit 1
}

# 4) Flatten single top-level directory if present.
\$topItems = @(Get-ChildItem -Path \$extractDir -Force)
if (\$topItems.Count -eq 1 -and \$topItems[0].PSIsContainer) {
    \$sub = \$topItems[0].FullName
    Write-Log "Flattening single top-level directory: \$(\$topItems[0].Name)"
    Get-ChildItem -Path \$sub -Force | ForEach-Object {
        Move-Item -Path \$_.FullName -Destination \$extractDir -Force
    }
    Remove-Item -Path \$sub -Recurse -Force -ErrorAction SilentlyContinue
}

# 5) Verify EXE present in extracted payload.
\$newExeStaging = Join-Path \$extractDir \$exeName
if (-not (Test-Path \$newExeStaging)) {
    Write-Log "ERROR: new EXE not found in payload: \$exeName"
    exit 1
}

# 6) Back up current install (excluding the updater workspace itself).
Write-Log "Backing up current install..."
New-Item -ItemType Directory -Path \$backupDir -Force | Out-Null
try {
    Get-ChildItem -Path \$appDir -Force | ForEach-Object {
        if (\$_.Name -ne '_update.ps1' -and \$_.Name -ne '_update.log') {
            Copy-Item -Path \$_.FullName -Destination \$backupDir -Recurse -Force -ErrorAction Stop
        }
    }
} catch {
    Write-Log "ERROR: backup failed: \$_"
    exit 1
}

# 7) Apply update: overlay extracted payload onto appDir.
Write-Log "Applying update..."
try {
    Get-ChildItem -Path \$extractDir -Force | ForEach-Object {
        Copy-Item -Path \$_.FullName -Destination \$appDir -Recurse -Force -ErrorAction Stop
    }
    Write-Log "Apply done."
} catch {
    Write-Log "ERROR: apply failed: \$_"
    Restore-Backup
    Write-Log "Restored, aborting."
    exit 1
}

# 8) Verify final EXE in place.
\$finalExe = Join-Path \$appDir \$exeName
if (-not (Test-Path \$finalExe)) {
    Write-Log "ERROR: final EXE missing after apply"
    Restore-Backup
    exit 1
}

# 9) Restart the app.
Write-Log "Restarting app..."
try {
    Start-Process -FilePath \$finalExe -WorkingDirectory \$appDir
} catch {
    Write-Log "WARN: failed to restart app: \$_"
}

# 10) Cleanup workspace (keep log for diagnosis).
Start-Sleep -Seconds 2
Remove-Item -Path \$zipPath    -Force -ErrorAction SilentlyContinue
Remove-Item -Path \$extractDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path \$backupDir  -Recurse -Force -ErrorAction SilentlyContinue

# Schedule self-deletion of script + trampoline bat (we can't delete the
# file we are running ourselves).
\$selfPath = \$MyInvocation.MyCommand.Path
\$batPath  = Join-Path \$updateRoot '_run_updater.bat'
if (\$selfPath) {
    Start-Process -FilePath 'cmd.exe' -ArgumentList "/c timeout /t 3 >nul && del ""\$selfPath"" && del ""\$batPath""" -WindowStyle Hidden
}

Write-Log "Updater finished."
''';
  }
}
