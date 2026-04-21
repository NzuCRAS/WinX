import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:http/io_client.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:xdnmb_api/xdnmb_api.dart';

import '../../app/app_state.dart';
import '../../app/cookie_controller.dart';
import '../../app/settings_controller.dart';
import '../../data/cookie_store.dart';
import '../../data/local_prefs.dart';
import '../../data/xdnmb_repository.dart';
import 'composer_window_controller.dart';
import 'composer_window_page.dart';

/// Sub-window app for the composer.
///
/// Runs as a standalone window with its own Flutter engine.
/// Receives configuration via [arguments] JSON and reads/writes draft to
/// SharedPreferences so the data is shared with the main window's panel.
final class ComposerWindowApp extends StatefulWidget {
  final String windowId;
  final String arguments;

  const ComposerWindowApp({
    super.key,
    required this.windowId,
    required this.arguments,
  });

  @override
  State<ComposerWindowApp> createState() => _ComposerWindowAppState();
}

final class _ComposerWindowAppState extends State<ComposerWindowApp>
    with WindowListener {
  late final SettingsController _settings;
  late final CookieController _cookie;
  late final AppState _appState;
  late final WindowComposerController _composer;
  late final Map<String, dynamic> _args;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _args = jsonDecode(widget.arguments) as Map<String, dynamic>;
    _settings = SettingsController(prefs: LocalPrefs());
    _composer = WindowComposerController();
    _composer.init(_args);
    windowManager.addListener(this);
    _initAsync();
  }

  Future<void> _initAsync() async {
    await _settings.init();
    await _initAppState();
    _setupMethodHandler();
    if (mounted) {
      setState(() => _initialized = true);
    }
    await _setupWindow();
  }

  void _setupMethodHandler() async {
    final window = await WindowController.fromCurrentEngine();
    await window.setWindowMethodHandler((call) async {
      if (call.method == 'insertQuote') {
        final text = call.arguments as String;
        _composer.insertAtCursor(text);
      } else if (call.method == 'imageEdited') {
        final args = call.arguments as Map<String, dynamic>?;
        final newPath = args?['newPath'] as String?;
        if (newPath != null && newPath.isNotEmpty) {
          _composer.setImagePath(newPath);
        }
      } else if (call.method == 'ping') {
        return 'pong';
      }
      return null;
    });
  }

  Future<void> _initAppState() async {
    final cookieStore = CookieStore();
    final prefs = LocalPrefs();
    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 90);

    final slots = await cookieStore.readSlots();
    final activeId = await cookieStore.readActiveSlotId();
    final defaultPost = await cookieStore.readDefaultPostSlot();
    final defaultAuth = await cookieStore.readDefaultAuthSlot();

    final browsingSlot = defaultAuth ?? await cookieStore.readActiveSlot();

    XdnmbUrlsSharedHttpClient.set(IOClient(httpClient));
    final api = XdnmbApi(userHash: browsingSlot?.userHash, client: httpClient);
    if (browsingSlot != null) {
      api.xdnmbCookie = XdnmbCookie(browsingSlot.userHash, name: browsingSlot.name);
    }
    final repo = XdnmbRepository(api);

    _cookie = CookieController(store: cookieStore, api: api, repo: repo);
    _cookie
      ..slots = slots
      ..activeSlotId = activeId
      ..defaultPostSlotId = defaultPost?.id
      ..defaultAuthSlotId = defaultAuth?.id
      ..cookieName = browsingSlot?.name;

    _appState = AppState(cookieStore: cookieStore, prefs: prefs);
    _appState.api = api;
    _appState.repo = repo;
    _appState.cookie = _cookie;
    _appState.settings = _settings;
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _composer.dispose();
    _settings.dispose();
    _cookie.dispose();
    _appState.dispose();
    super.dispose();
  }

  Future<void> _setupWindow() async {
    await windowManager.setTitle(_args['title'] as String? ?? 'WinX 编辑器');
    await windowManager.setSize(const Size(720, 640));
    await windowManager.setMinimumSize(const Size(480, 400));
    await windowManager.center();
  }

  @override
  void onWindowClose() async {
    // Save draft synchronously before the engine is torn down.
    await _composer.saveDraftNow();
    // Notify the main window that this sub-window is closing.
    try {
      final mainWindow = WindowController.fromWindowId('0');
      await mainWindow.invokeMethod('windowClosed');
    } catch (_) {
      // ignore: best-effort only
    }
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text('加载中...', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsController>.value(value: _settings),
        ChangeNotifierProvider<CookieController>.value(value: _cookie),
        ChangeNotifierProvider<AppState>.value(value: _appState),
        ChangeNotifierProvider<WindowComposerController>.value(value: _composer),
      ],
      child: ListenableBuilder(
        listenable: _settings,
        builder: (context, _) {
          return MaterialApp(
            title: 'WinX 编辑器',
            debugShowCheckedModeBanner: false,
            themeMode: _settings.themeMode,
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
            home: const ComposerWindowPage(),
          );
        },
      ),
    );
  }
}
