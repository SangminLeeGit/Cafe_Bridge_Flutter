import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_screen.dart';
import '../widgets/panel.dart';
import 'menu_workspace.dart';
import 'settings.dart';
import 'touchkey.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return ListView(
      padding: const EdgeInsets.all(CafeBridgeSpacing.page),
      children: [
        const _MoreHeader(),
        const SizedBox(height: CafeBridgeSpacing.section),
        Panel(
          title: '바로가기',
          subtitle: '운영 도구와 읽기 전용 탐색',
          child: Column(
            children: [
              _MoreFeatureTile(
                icon: Icons.price_change_outlined,
                title: '상품 작업대',
                subtitle: '상품 선택 후 가격 변경·신규 메뉴',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const _MoreStandalonePage(
                      title: '상품 작업대',
                      child: MenuWorkspaceScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _MoreFeatureTile(
                icon: Icons.grid_view_outlined,
                title: '터치키',
                subtitle: 'POS 표와 배치 확인',
                badge: appState.hasOperatorAccess ? null : 'operator 필요',
                onTap: appState.hasOperatorAccess
                    ? () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const TouchkeyScreen(),
                          ),
                        )
                    : null,
              ),
              if (!appState.hasOperatorAccess) ...[
                const SizedBox(height: 12),
                const _AccessHint(),
              ],
            ],
          ),
        ),
        const SizedBox(height: CafeBridgeSpacing.control),
        Panel(
          title: '계정 및 설정',
          subtitle: '연결·보안·업데이트 상태',
          child: _MoreFeatureTile(
            icon: Icons.settings_outlined,
            title: '앱 설정',
            subtitle: '서버 주소 · 캐시 · 비밀번호 · 세션',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const _MoreStandalonePage(
                  title: '앱 설정',
                  child: SettingsScreen(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: CafeBridgeSpacing.control),
        Panel(
          title: '관리자 운영',
          subtitle: '배포·사용자·감사 로그',
          child: _MoreFeatureTile(
            icon: Icons.rocket_launch_outlined,
            title: '배포 관리',
            subtitle: appState.hasAdminAccess
                ? '배포 확인 · 승인 정보 · 실행 로그'
                : '관리자 권한에서만 접근할 수 있습니다.',
            badge: appState.hasAdminAccess ? null : 'admin 필요',
            onTap: appState.hasAdminAccess
                ? () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DeployManagementScreen(),
                      ),
                    )
                : null,
          ),
        ),
      ],
    );
  }
}

class _MoreStandalonePage extends StatelessWidget {
  final String title;
  final Widget child;

  const _MoreStandalonePage({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return AppScreen(title: title, body: child);
  }
}

class _MoreHeader extends StatelessWidget {
  const _MoreHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CafeBridgeColors.surface,
        borderRadius: BorderRadius.circular(CafeBridgeRadii.card),
        border: Border.all(color: CafeBridgeColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: CafeBridgeColors.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.widgets_outlined,
              color: CafeBridgeColors.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('더보기', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  '설정과 권한별 운영 도구를 한 곳에서 확인합니다.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreFeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback? onTap;

  const _MoreFeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: enabled
                ? CafeBridgeColors.accentSoft
                : CafeBridgeColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color:
                enabled ? CafeBridgeColors.accent : CafeBridgeColors.textFaint,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: CafeBridgeColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(CafeBridgeRadii.pill),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: CafeBridgeColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
        trailing: Icon(
          enabled ? Icons.chevron_right_outlined : Icons.lock_outline,
          color: CafeBridgeColors.textFaint,
        ),
      ),
    );
  }
}

class _AccessHint extends StatelessWidget {
  const _AccessHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CafeBridgeColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(CafeBridgeRadii.control),
        border: Border.all(color: CafeBridgeColors.border),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 18, color: CafeBridgeColors.textMuted),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'operator 이상에서 사용할 수 있습니다. 관리자 도구는 관리자 권한에서만 실행됩니다.',
              style: TextStyle(
                color: CafeBridgeColors.textSecondary,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
