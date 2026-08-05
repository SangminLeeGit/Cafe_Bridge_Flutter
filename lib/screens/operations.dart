import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_screen.dart';
import 'costing.dart';
import 'menu_workspace.dart';
import 'price_apply.dart';
import 'signage.dart';
import 'sync.dart';

/// 운영 허브 — 조회와 고위험 실행을 한 흐름으로 구분해 진입한다.
class OperationsScreen extends StatelessWidget {
  const OperationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final canOperate = appState.hasOperatorAccess;

    return ListView(
      padding: const EdgeInsets.all(CafeBridgeSpacing.page),
      children: [
        const _SectionHeader(
          title: '업무',
          subtitle: '조회는 바로, 변경은 검증과 실행 단계를 거칩니다.',
        ),
        const SizedBox(height: CafeBridgeSpacing.section),
        _OperationTile(
          icon: Icons.calculate_outlined,
          title: '원가',
          subtitle: '재료 단가 · 레시피 · 원가율 경고',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const _FullScreenPage(
                title: '원가',
                child: CostingScreen(),
              ),
            ),
          ),
        ),
        const SizedBox(height: CafeBridgeSpacing.compact),
        _OperationTile(
          icon: Icons.menu_book_outlined,
          title: '상품 작업대',
          subtitle: '상품 선택 · 가격 초안 · 신규 메뉴',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const _FullScreenPage(
                title: '상품 작업대',
                child: MenuWorkspaceScreen(),
              ),
            ),
          ),
        ),
        const SizedBox(height: CafeBridgeSpacing.compact),
        _OperationTile(
          icon: Icons.price_change_outlined,
          title: '가격 반영',
          subtitle: '상품을 고른 뒤 검증 · 영향 확인 · 실행',
          badge: canOperate ? null : 'operator 필요',
          onTap: canOperate
              ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PriceApplyScreen(),
                    ),
                  )
              : null,
        ),
        const SizedBox(height: CafeBridgeSpacing.compact),
        _OperationTile(
          icon: Icons.tv_outlined,
          title: '메뉴판',
          subtitle: '초안 편집 · 변경 비교 · 메뉴판 반영',
          badge: canOperate ? null : 'operator 필요',
          onTap: canOperate
              ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const _FullScreenPage(
                        title: '메뉴판',
                        child: SignageScreen(),
                      ),
                    ),
                  )
              : null,
        ),
        const SizedBox(height: CafeBridgeSpacing.compact),
        _OperationTile(
          icon: Icons.sync_outlined,
          title: '동기화',
          subtitle: '대상일 확인 · 중복 방지 · 진행 추적',
          badge: canOperate ? null : 'operator 필요',
          onTap: canOperate
              ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const _FullScreenPage(
                        title: '동기화',
                        child: SyncScreen(),
                      ),
                    ),
                  )
              : null,
        ),
        if (!canOperate) ...[
          const SizedBox(height: 12),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CafeBridgeColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(CafeBridgeRadii.control),
        border: Border.all(color: CafeBridgeColors.border),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: CafeBridgeColors.textMuted),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '가격 반영·메뉴판 반영·동기화는 operator 이상 권한에서 실행할 수 있습니다. 메뉴와 원가 조회는 계속 사용할 수 있습니다.',
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

class _FullScreenPage extends StatelessWidget {
  final String title;
  final Widget child;

  const _FullScreenPage({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return AppScreen(title: title, body: child);
  }
}
