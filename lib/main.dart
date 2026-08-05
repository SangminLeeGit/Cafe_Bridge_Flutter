import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/analytics.dart';
import 'screens/dashboard.dart';
import 'screens/login.dart';
import 'screens/more.dart';
import 'screens/operations.dart';
import 'screens/workforce.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'widgets/app_update_banner.dart';
import 'widgets/app_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = AppState();
  await appState.load();

  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: const CafeBridgeApp(),
    ),
  );
}

class CafeBridgeApp extends StatelessWidget {
  const CafeBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cafe Bridge Mobile',
      debugShowCheckedModeBanner: false,
      theme: CafeBridgeTheme.light(),
      home: const AppRoot(),
    );
  }
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    if (appState.isInitializing) {
      return const Scaffold(
        body: LoadingState(message: 'Cafe Bridge를 준비하는 중입니다.'),
      );
    }

    if (!appState.isAuthenticated) {
      return const LoginScreen();
    }

    return const MainLayout();
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;

  List<_NavigationItem> _buildNavigationItems(AppState appState) {
    final items = <_NavigationItem>[
      const _NavigationItem(
        title: '홈',
        label: '홈',
        icon: Icons.space_dashboard_outlined,
        selectedIcon: Icons.space_dashboard,
        screen: DashboardScreen(),
      ),
      const _NavigationItem(
        title: '인사이트',
        label: '분석',
        icon: Icons.analytics_outlined,
        selectedIcon: Icons.analytics,
        screen: AnalyticsScreen(),
      ),
      const _NavigationItem(
        title: '업무',
        label: '업무',
        icon: Icons.handyman_outlined,
        selectedIcon: Icons.handyman,
        screen: OperationsScreen(),
      ),
      const _NavigationItem(
        title: '인력',
        label: '인력',
        icon: Icons.people_outline,
        selectedIcon: Icons.people,
        screen: WorkforceScreen(),
        minimumRole: UserRole.operator,
      ),
      const _NavigationItem(
        title: '더보기',
        label: '더보기',
        icon: Icons.widgets_outlined,
        selectedIcon: Icons.widgets,
        screen: MoreScreen(),
      ),
    ];

    return items
        .where(
          (item) =>
              item.minimumRole == null || appState.canAccess(item.minimumRole!),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final navigationItems = _buildNavigationItems(appState);
    final currentIndex = _currentIndex.clamp(0, navigationItems.length - 1);

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 60,
        leading: Padding(
          padding: const EdgeInsets.only(left: 14, top: 8, bottom: 8),
          child: Image.asset(
            'assets/branding/cafe_bridge_logo.png',
            fit: BoxFit.contain,
          ),
        ),
        title: Text(
          navigationItems[currentIndex].title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: CafeBridgeColors.accentSoft,
              borderRadius: BorderRadius.circular(CafeBridgeRadii.pill),
            ),
            child: Text(
              appState.userRole.label,
              style: const TextStyle(
                color: CafeBridgeColors.accentStrong,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: CafeBridgeColors.border,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (appState.offlineMode)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: CafeBridgeColors.infoSoft,
                child: const Row(
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 18,
                      color: CafeBridgeColors.info,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '오프라인 캐시 모드로 표시 중입니다.',
                        style: TextStyle(
                          color: CafeBridgeColors.info,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (appState.hasRecommendedUpdate)
              const AppUpdateBanner(dense: true),
            Expanded(
              child: IndexedStack(
                index: currentIndex,
                children: navigationItems
                    .map((item) => item.screen)
                    .toList(growable: false),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        backgroundColor: CafeBridgeColors.surface,
        indicatorColor: CafeBridgeColors.accentSoft,
        destinations: navigationItems
            .map(
              (item) => NavigationDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.selectedIcon),
                label: item.label,
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _NavigationItem {
  final String title;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
  final UserRole? minimumRole;

  const _NavigationItem({
    required this.title,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.screen,
    this.minimumRole,
  });
}
