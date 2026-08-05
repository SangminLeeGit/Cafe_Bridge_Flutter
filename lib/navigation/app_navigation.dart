import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../widgets/access_gate.dart';

abstract final class AppNavigation {
  static MaterialPageRoute<T> guardedRoute<T>({
    required UserRole minimumRole,
    required Widget child,
    bool fullScreen = true,
  }) {
    return MaterialPageRoute<T>(
      builder: (_) => AccessGate(
        minimumRole: minimumRole,
        fullScreen: fullScreen,
        child: child,
      ),
    );
  }

  static Future<T?> pushGuarded<T>(
    BuildContext context, {
    required UserRole minimumRole,
    required Widget child,
    bool fullScreen = true,
  }) {
    return Navigator.of(context).push<T>(
      guardedRoute<T>(
        minimumRole: minimumRole,
        fullScreen: fullScreen,
        child: child,
      ),
    );
  }
}
