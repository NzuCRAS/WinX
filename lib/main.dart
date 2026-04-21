import 'dart:convert';
import 'dart:io' show Platform;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app/app_state.dart';
import 'src/app/cookie_controller.dart';
import 'src/app/settings_controller.dart';
import 'src/data/local_prefs.dart';
import 'src/ui/app_navigator.dart';
import 'src/ui/pages/home_page.dart';
import 'src/ui/windows/composer_window_app.dart';
import 'src/ui/windows/image_viewer_window_page.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await windowManager.ensureInitialized();

  // Sub-window entry: args = ['multi_window', windowId, jsonArguments]
  if (args.isNotEmpty && args.first == 'multi_window') {
    final arguments = args.length > 2 ? args[2] : '{}';
    final decoded = jsonDecode(arguments) as Map<String, dynamic>?;
    final windowType = decoded?['windowType'] as String? ?? 'composer';

    if (windowType == 'imageViewer') {
      final imagePath = decoded?['imagePath'] as String? ?? '';
      final title = decoded?['title'] as String?;
      runApp(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ImageViewerWindowPage(imagePath: imagePath, title: title),
      ));
    } else {
      final windowId = args.length > 1 ? args[1] : '0';
      runApp(ComposerWindowApp(
        windowId: windowId,
        arguments: arguments,
      ));
    }
    return;
  }

  // Main window entry: set up handler for sub-window notifications.
  final window = await WindowController.fromCurrentEngine();
  await window.setWindowMethodHandler((call) async {
    if (call.method == 'refresh') {
      final context = AppNavigator.navigatorKey.currentContext;
      if (context != null && context.mounted) {
        try {
          final app = Provider.of<AppState>(context, listen: false);
          app.composer.notifyRefreshFromSubWindow();
        } catch (_) {}
      }
    } else if (call.method == 'windowClosed') {
      final context = AppNavigator.navigatorKey.currentContext;
      if (context != null && context.mounted) {
        try {
          final app = Provider.of<AppState>(context, listen: false);
          app.composer.clearWindowId();
        } catch (_) {}
      }
    } else if (call.method == 'imageEdited') {
      final args = call.arguments as Map<String, dynamic>?;
      final newPath = args?['newPath'] as String?;
      if (newPath != null && newPath.isNotEmpty) {
        final context = AppNavigator.navigatorKey.currentContext;
        if (context != null && context.mounted) {
          try {
            final app = Provider.of<AppState>(context, listen: false);
            app.composer.setImagePath(newPath);
            app.composer.onImageChanged();
          } catch (_) {}
        }
      }
    }
    return null;
  });

  runApp(const XdnmbClientApp());
}

final class XdnmbClientApp extends StatelessWidget {
  const XdnmbClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: Consumer<AppState>(
        builder: (context, app, _) {
          if (!app.initialized) {
            return MaterialApp(
              title: 'WinX',
              home: const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          return MultiProvider(
            providers: [
              ChangeNotifierProvider<CookieController>.value(
                value: app.cookie,
              ),
              ChangeNotifierProvider<SettingsController>.value(
                value: app.settings,
              ),
              ChangeNotifierProvider.value(
                value: app.composer,
              ),
              Provider<LocalPrefs>.value(value: app.prefs),
            ],
            child: const _App(),
          );
        },
      ),
    );
  }
}

final class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    return MaterialApp(
      title: 'WinX',
      navigatorKey: AppNavigator.navigatorKey,
      themeMode: settings.themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
        fontFamilyFallback: const [
          'Segoe UI',
          'Microsoft YaHei UI',
          'Microsoft YaHei',
          'Noto Sans CJK SC',
          'Noto Sans',
        ],
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: Colors.black87,
              displayColor: Colors.black87,
            ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
        fontFamilyFallback: const [
          'Segoe UI',
          'Microsoft YaHei UI',
          'Microsoft YaHei',
          'Noto Sans CJK SC',
          'Noto Sans',
        ],
      ),
      home: const HomePage(),
    );
  }
}
