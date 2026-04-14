# WinX

WinX 是一个面向 Windows 桌面的 X 岛客户端（Flutter）。

## 特性

- 串列表/订阅/浏览历史/发言历史
- 串内阅读进度记忆与精准跳转
- 文本解析：引用 `>>No.xxx`、绿字（行首 `>`）、剧透 `[h]...[/h]`
- 本地存储：SQLite（Windows 使用 `sqflite_common_ffi`）

## 目录结构

- `lib/`：Flutter 客户端代码
- `packages/xdnmb_api/`：内置的论坛 API package（作为独立 package 维护）

## 开发环境

- Flutter stable
- Dart SDK 与 `pubspec.yaml` 中的 `environment` 保持一致

## 开始使用

```powershell
flutter pub get
flutter test
flutter run -d windows
```

构建 release：

```powershell
flutter build windows
```

## License

MIT
# xdnmb_client

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
