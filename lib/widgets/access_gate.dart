import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'app_screen.dart';

class AccessGate extends StatelessWidget {
  final UserRole minimumRole;
  final Widget child;
  final bool fullScreen;

  const AccessGate({
    super.key,
    required this.minimumRole,
    required this.child,
    this.fullScreen = false,
  });

  static bool roleAllows(UserRole actual, UserRole required) =>
      actual.allows(required);

  @override
  Widget build(BuildContext context) {
    final allowed = context.select<AppState, bool>(
      (appState) => appState.canAccess(minimumRole),
    );
    if (allowed) {
      return child;
    }

    final message = '${minimumRole.label} 이상 권한이 필요한 화면입니다.';
    final denied = PermissionState(
      requiredRole: minimumRole.label,
      message: message,
    );

    if (!fullScreen) return denied;
    return Scaffold(
      appBar: AppBar(title: const Text('접근 제한')),
      body: SafeArea(child: denied),
    );
  }
}
