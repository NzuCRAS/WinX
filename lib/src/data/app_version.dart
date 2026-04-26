import 'package:package_info_plus/package_info_plus.dart';

/// App version, loaded at startup from `pubspec.yaml` via `package_info_plus`.
///
/// Single source of truth is `pubspec.yaml#version`. Call [initAppVersion] once
/// in `main()` before any UI or [UpdateService] usage; before that the
/// fallbacks below apply.
String appVersion = '0.0.0';
String appVersionDisplay = 'v0.0.0';

const String appRepoOwner = 'NzuCRAS';
const String appRepoName = 'WinX';
const String appFullRepo = '$appRepoOwner/$appRepoName';

bool _initialized = false;

Future<void> initAppVersion() async {
  if (_initialized) return;
  final info = await PackageInfo.fromPlatform();
  appVersion = info.version;
  appVersionDisplay = 'v${info.version}';
  _initialized = true;
}
