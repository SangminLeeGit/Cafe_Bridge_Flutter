import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'costing.dart';
import 'menu_workspace.dart';
import 'signage.dart';
import 'sync.dart';

/// 운영 허브 — 원가관리, 메뉴 작업대, 동기화로 이동하는 허브 화면.
class OperationsScreen extends StatelessWidget {
  const OperationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionHeader(
          title: '운영',
          subtitle: '필요한 작업을 선택하세요.',
        ),
        const SizedBox(height: 16),
        _OperationTile(
          icon: Icons.calculate_outlined,
          title: '원가',
          subtitle: '재료 단가 · 레시피',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => const _FullScreenPage(
                      title: '원가',
                      child: CostingScreen(),
                    )),
          ),
        ),
        const SizedBox(height: 8),
        _OperationTile(
          icon: Icons.menu_book_outlined,
          title: '상품',
          subtitle: '가격 변경 · 신규 메뉴',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => const _FullScreenPage(
                      title: '상품',
                      child: MenuWorkspaceScreen(),
                    )),
          ),
        ),
        if (appState.hasOperatorAccess) ...[
          const SizedBox(height: 8),
          _OperationTile(
            icon: Icons.tv_outlined,
            title: '메뉴판',
            subtitle: '조회 · 편집 · 반영',
            badge: 'operator',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const _FullScreenPage(
                        title: '메뉴판',
                        child: SignageScreen(),
                      )),
            ),
          ),
          const SizedBox(height: 8),
          _OperationTile(
            icon: Icons.sync_outlined,
            title: '동기화',
            subtitle: '매출 수집 · 적재',
            badge: 'operator',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const _FullScreenPage(
                        title: '동기화',
                        child: SyncScreen(),
                      )),
            ),
          ),
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
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
        ),
      ],
    );
  }
}

class _OperationTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
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
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color.fromRGBO(13, 148, 136, 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFF0D9488)),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badge!,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ),
          ],
        ),
        subtitle: Text(subtitle),
        trailing:
            const Icon(Icons.chevron_right_outlined, color: Color(0xFF94A3B8)),
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
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE2E8F0)),
        ),
      ),
      body: SafeArea(child: child),
    );
  }
}
