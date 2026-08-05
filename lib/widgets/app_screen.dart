import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 전체 화면으로 진입하는 운영 도구 화면의 공통 shell.
class AppScreen extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget>? actions;

  const AppScreen({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title),
            if (subtitle != null)
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: CafeBridgeColors.textMuted,
                    ),
              ),
          ],
        ),
        actions: actions,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: SafeArea(child: body),
    );
  }
}

class PermissionState extends StatelessWidget {
  final String requiredRole;
  final String message;
  final VoidCallback? onBack;

  const PermissionState({
    super.key,
    this.requiredRole = 'operator',
    this.message = '이 기능은 권한이 있는 계정에서 사용할 수 있습니다.',
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CafeBridgeSpacing.section),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline,
              size: 42,
              color: CafeBridgeColors.textFaint,
            ),
            const SizedBox(height: 12),
            Text(
              '권한이 필요합니다',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              '$message\n필요 권한: $requiredRole',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (onBack != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onBack, child: const Text('돌아가기')),
            ],
          ],
        ),
      ),
    );
  }
}

class NetworkState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const NetworkState({
    super.key,
    this.message = '네트워크 연결을 확인한 뒤 다시 시도해 주세요.',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CafeBridgeSpacing.section),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 42,
              color: CafeBridgeColors.info,
            ),
            const SizedBox(height: 12),
            Text(
              '연결할 수 없습니다',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('다시 시도')),
            ],
          ],
        ),
      ),
    );
  }
}

class LoadingState extends StatelessWidget {
  final String message;

  const LoadingState({
    super.key,
    this.message = '데이터를 불러오는 중입니다.',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: CafeBridgeColors.accent),
          const SizedBox(height: 12),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
