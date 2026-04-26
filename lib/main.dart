import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/analytics.dart';
import 'screens/dashboard.dart';
import 'screens/login.dart';
import 'screens/operations.dart';
import 'screens/settings.dart';
import 'screens/workforce.dart';
import 'state/app_state.dart';
import 'widgets/app_update_banner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = AppState();
  await appState.load();

  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: const EasyPosApp(),
    ),
  );
}

class EasyPosApp extends StatelessWidget {
  const EasyPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EasyPOS Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D9488),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          elevation: 0,
        ),
      ),
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
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF0D9488)),
        ),
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
        title: '대시보드',
        label: '대시보드',
        icon: Icons.space_dashboard_outlined,
        selectedIcon: Icons.space_dashboard,
        screen: DashboardScreen(),
      ),
      const _NavigationItem(
        title: '분석 허브',
        label: '분석',
        icon: Icons.analytics_outlined,
        selectedIcon: Icons.analytics,
        screen: AnalyticsScreen(),
      ),
      const _NavigationItem(
        title: '운영',
        label: '운영',
        icon: Icons.handyman_outlined,
        selectedIcon: Icons.handyman,
        screen: OperationsScreen(),
      ),
      const _NavigationItem(
        title: '인력 관리',
        label: '인력',
        icon: Icons.people_outline,
        selectedIcon: Icons.people,
        screen: WorkforceScreen(),
        minimumRole: UserRole.operator,
      ),
      const _NavigationItem(
        title: '설정',
        label: '설정',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        screen: SettingsScreen(),
      ),
    ];

    return items
        .where(
          (item) => item.minimumRole == null ||
              appState.canAccess(item.minimumRole!),
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
        title: Text(
          navigationItems[currentIndex].title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(13, 148, 136, 0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              appState.userRole.label,
              style: const TextStyle(
                color: Color(0xFF0F766E),
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
            color: const Color(0xFFE2E8F0),
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
                color: const Color(0xFFECFEFF),
                child: const Row(
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 18,
                      color: Color(0xFF155E75),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '오프라인 캐시 모드로 표시 중입니다.',
                        style: TextStyle(
                          color: Color(0xFF155E75),
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
        backgroundColor: Colors.white,
        indicatorColor: const Color.fromRGBO(13, 148, 136, 0.12),
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
