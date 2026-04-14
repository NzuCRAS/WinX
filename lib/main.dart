import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'dart:io' show Platform;

import 'src/app/app_state.dart';
import 'src/ui/pages/home_page.dart';
import 'src/data/local_prefs.dart';
import 'src/ui/app_navigator.dart';

void main() {
  // Desktop (Windows/Linux): sqflite needs an explicit ffi factory.
  // Without this, calling `openDatabase()` will throw:
  // "Bad state: databaseFactory not initialized".
  if (Platform.isWindows || Platform.isLinux) {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  }
  runApp(const XdnmbClientApp());
}

final class XdnmbClientApp extends StatelessWidget {
  const XdnmbClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: Consumer<AppState>(
        builder: (context, app, _) => MaterialApp(
          title: 'xdnmb client',
          navigatorKey: AppNavigator.navigatorKey,
          themeMode: app.themeMode,
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
          home: const _Bootstrapper(),
        ),
      ),
    );
  }
}

final class _Bootstrapper extends StatelessWidget {
  const _Bootstrapper();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Provider<LocalPrefs>(
      create: (_) => LocalPrefs(),
      child: const HomePage(),
    );
  }
}
