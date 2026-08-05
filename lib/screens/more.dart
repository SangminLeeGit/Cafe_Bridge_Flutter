import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../navigation/app_navigation.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_screen.dart';
import '../widgets/panel.dart';
import 'daily_report_monitor.dart';
import 'menu_workspace.dart';
import 'product_lookup.dart';
import 'settings.dart';
import 'touchkey.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final canAdmin = appState.hasAdminAccess;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        const _MoreHeader(),
        const SizedBox(height: AppSpacing.section),
        Panel(
          title: '운영 도구',
          subtitle: '조회와 운영 화면으로 이동합니다.',
          child: Column(
            children: [
              _MoreFeatureTile(
                icon: Icons.inventory_2_outlined,
                title: '상품 조회',
                subtitle: '상품 검색 · 상세 조회',
                onTap: () => AppNavigation.pushGuarded(
                  context,
                  minimumRole: UserRole.viewer,
                  child: const _MoreStandalonePage(
                    title: '상품 조회',
                    child: ProductLookupScreen(),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.compact),
              _MoreFeatureTile(
                icon: Icons.grid_view_outlined,
                title: '터치키',
                subtitle: 'POS 표와 배치 확인',
                badge: 'viewer',
                onTap: () => AppNavigation.pushGuarded(
                  context,
                  minimumRole: UserRole.viewer,
                  child: const TouchkeyScreen(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.control),
        Panel(
          title: '계정 및 설정',
          subtitle: '연결·보안·업데이트 상태',
          child: _MoreFeatureTile(
            icon: Icons.settings_outlined,
            title: '앱 설정',
            subtitle: '서버 주소 · 캐시 · 비밀번호 · 세션',
            onTap: () => AppNavigation.pushGuarded(
              context,
              minimumRole: UserRole.viewer,
              child: const _MoreStandalonePage(
                title: '앱 설정',
                child: SettingsScreen(),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.control),
        Panel(
          title: '관리자 운영',
          subtitle: '메뉴·배포·일일보고서 읽기 전용 모니터',
          child: Column(
            children: [
              _MoreFeatureTile(
                icon: Icons.menu_book_outlined,
                title: '메뉴 작업대',
                subtitle:
                    canAdmin ? '관리자 작업 조회 · 실행 이력' : '관리자 권한에서만 접근할 수 있습니다.',
                badge: canAdmin ? null : 'admin 필요',
                onTap: canAdmin
                    ? () => AppNavigation.pushGuarded(
                          context,
                          minimumRole: UserRole.admin,
                          child: const _MoreStandalonePage(
                            title: '메뉴 작업대',
                            child: MenuWorkspaceScreen(),
                          ),
                        )
                    : null,
              ),
              const SizedBox(height: AppSpacing.compact),
              _MoreFeatureTile(
                icon: Icons.rocket_launch_outlined,
                title: '배포 관리',
                subtitle: canAdmin
                    ? '배포 상태 · 승인 정보 · 실행 로그'
                    : '관리자 권한에서만 접근할 수 있습니다.',
                badge: canAdmin ? null : 'admin 필요',
                onTap: canAdmin
                    ? () => AppNavigation.pushGuarded(
                          context,
                          minimumRole: UserRole.admin,
                          child: const DeployManagementScreen(),
                        )
                    : null,
              ),
              const SizedBox(height: AppSpacing.compact),
              _MoreFeatureTile(
                icon: Icons.summarize_outlined,
                title: '일일보고서',
                subtitle:
                    canAdmin ? '설정 · 실행 · 감사 상태 조회' : '관리자 권한에서만 접근할 수 있습니다.',
                badge: canAdmin ? null : 'admin 필요',
                onTap: canAdmin
                    ? () => AppNavigation.pushGuarded(
                          context,
                          minimumRole: UserRole.admin,
                          child: const DailyReportMonitorScreen(),
                        )
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MoreStandalonePage extends StatelessWidget {
  final String title;
  final Widget child;

  const _MoreStandalonePage({
    required this.title,
    required this.child,
  });

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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            child: const Icon(
              Icons.widgets_outlined,
              color: AppColors.primary,
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
                ? AppColors.primary.withValues(alpha: 0.1)
                : AppColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          child: Icon(
            icon,
            color: enabled ? AppColors.primary : AppColors.subtle,
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
                  color: AppColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.muted,
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
          color: AppColors.subtle,
        ),
      ),
    );
  }
}
