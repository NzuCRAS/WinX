import 'package:flutter/material.dart';

/// Global navigation handle used for debug dialogs and other cross-layer UI.
final class AppNavigator {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  const AppNavigator._();
}
