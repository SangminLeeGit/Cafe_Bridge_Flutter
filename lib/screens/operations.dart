import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../navigation/app_navigation.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_screen.dart';
import 'costing.dart';
import 'menu_workspace.dart';
import 'product_lookup.dart';
import 'signage.dart';
import 'sync.dart';

/// 업무 허브 — 조회와 고위험 실행을 권한별로 분리해 진입한다.
class OperationsScreen extends StatelessWidget {
  const OperationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final canOperate = appState.hasOperatorAccess;
    final canAdmin = appState.hasAdminAccess;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        const _SectionHeader(
          title: '업무',
          subtitle: '조회는 바로, 변경은 검증과 실행 단계를 거칩니다.',
        ),
        const SizedBox(height: AppSpacing.section),
        _OperationTile(
          icon: Icons.inventory_2_outlined,
          title: '상품 조회',
          subtitle: '상품 검색 · 상세 조회 · 가격 변경 진입',
          badge: null,
          onTap: () => AppNavigation.pushGuarded(
            context,
            minimumRole: UserRole.viewer,
            child: const _FullScreenPage(
              title: '상품 조회',
              child: ProductLookupScreen(),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.compact),
        _OperationTile(
          icon: Icons.calculate_outlined,
          title: '원가',
          subtitle: '재료 단가 · 레시피 · 원가율 경고',
          badge: canOperate ? null : 'operator 필요',
          onTap: canOperate
              ? () => AppNavigation.pushGuarded(
                    context,
                    minimumRole: UserRole.operator,
                    child: const _FullScreenPage(
                      title: '원가',
                      child: CostingScreen(),
                    ),
                  )
              : null,
        ),
        const SizedBox(height: AppSpacing.compact),
        _OperationTile(
          icon: Icons.price_change_outlined,
          title: '가격 반영',
          subtitle: '상품 선택 후 검증 · 영향 확인 · 실행',
          badge: canOperate ? null : 'operator 필요',
          onTap: canOperate
              ? () => AppNavigation.pushGuarded(
                    context,
                    minimumRole: UserRole.operator,
                    child: const _FullScreenPage(
                      title: '상품 조회 · 가격 반영',
                      child: ProductLookupScreen(),
                    ),
                  )
              : null,
        ),
        const SizedBox(height: AppSpacing.compact),
        _OperationTile(
          icon: Icons.tv_outlined,
          title: '메뉴판',
          subtitle: '초안 편집 · 변경 비교 · 메뉴판 반영',
          badge: canOperate ? null : 'operator 필요',
          onTap: canOperate
              ? () => AppNavigation.pushGuarded(
                    context,
                    minimumRole: UserRole.operator,
                    child: const _FullScreenPage(
                      title: '메뉴판',
                      child: SignageScreen(),
                    ),
                  )
              : null,
        ),
        const SizedBox(height: AppSpacing.compact),
        _OperationTile(
          icon: Icons.sync_outlined,
          title: '동기화',
          subtitle: '대상일 확인 · 중복 방지 · 진행 추적',
          badge: canOperate ? null : 'operator 필요',
          onTap: canOperate
              ? () => AppNavigation.pushGuarded(
                    context,
                    minimumRole: UserRole.operator,
                    child: const _FullScreenPage(
                      title: '동기화',
                      child: SyncScreen(),
                    ),
                  )
              : null,
        ),
        const SizedBox(height: AppSpacing.compact),
        _OperationTile(
          icon: Icons.menu_book_outlined,
          title: '메뉴 작업대',
          subtitle: '작업 조회 · 신규 메뉴 · 관리자 작업 이력',
          badge: canAdmin ? null : 'admin 필요',
          onTap: canAdmin
              ? () => AppNavigation.pushGuarded(
                    context,
                    minimumRole: UserRole.admin,
                    child: const _FullScreenPage(
                      title: '메뉴 작업대',
                      child: MenuWorkspaceScreen(),
                    ),
                  )
              : null,
        ),
        if (!canOperate || !canAdmin) ...[
          const SizedBox(height: AppSpacing.control),
          const _AccessHint(),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _OperationTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final String? badge;

  const _OperationTile({
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
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
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

class _AccessHint extends StatelessWidget {
  const _AccessHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: AppColors.muted),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '가격 반영·메뉴판 반영·동기화는 operator, 메뉴 작업대는 admin 권한에서 실행할 수 있습니다. 조회 기능은 계속 사용할 수 있습니다.',
              style: TextStyle(
                color: AppColors.textSecondary,
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

class _FullScreenPage extends StatelessWidget {
  final String title;
  final Widget child;

  const _FullScreenPage({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return AppScreen(title: title, body: child);
  }
}
