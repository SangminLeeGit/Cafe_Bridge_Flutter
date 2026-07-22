import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
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
      padding: const EdgeInsets.all(16),
      children: [
        const _MoreHeader(),
        const SizedBox(height: 16),
        Panel(
          title: '바로가기',
          child: appState.hasOperatorAccess
              ? Column(
                  children: [
                    _MoreFeatureTile(
                      icon: Icons.price_change_outlined,
                      title: '가격',
                      subtitle: '상품 선택 후 변경',
                      badge: 'operator',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const _MoreStandalonePage(
                            title: '상품',
                            child: MenuWorkspaceScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _MoreFeatureTile(
                      icon: Icons.grid_view_outlined,
                      title: '터치키',
                      subtitle: '표와 배치 확인',
                      badge: 'operator',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TouchkeyScreen(),
                        ),
                      ),
                    ),
                  ],
                )
              : const _AccessHint(),
        ),
        if (appState.hasAdminAccess) ...[
          const SizedBox(height: 16),
          Panel(
            title: '관리',
            child: Column(
              children: [
                _MoreFeatureTile(
                  icon: Icons.rocket_launch_outlined,
                  title: '배포 관리',
                  subtitle: '배포 상태 확인',
                  badge: 'admin',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DeployManagementScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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

class _MoreHeader extends StatelessWidget {
  const _MoreHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Text(
        '도구',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: Color(0xFF0F172A),
        ),
      ),
    );
  }
}

class _MoreFeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  const _MoreFeatureTile({
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
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
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
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
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

class _AccessHint extends StatelessWidget {
  const _AccessHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 18, color: Color(0xFF64748B)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'operator 이상에서 사용할 수 있습니다.',
              style: TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
