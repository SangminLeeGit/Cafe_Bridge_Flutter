import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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

final _appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = AppState();
  await appState.loadLocal(notify: false);

  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: const CafeBridgeApp(),
    ),
  );
  unawaited(appState.loadRemote());
}

class CafeBridgeApp extends StatelessWidget {
  const CafeBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cafe Bridge Mobile',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      navigatorKey: _appNavigatorKey,
      home: AppRoot(navigatorKey: _appNavigatorKey),
    );
  }
}

class AppRoot extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const AppRoot({super.key, required this.navigatorKey});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  bool _wasAuthenticated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(context.read<AppState>().handleAppResumed());
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    if (appState.isInitializing || appState.isRestoringSession) {
      return const Scaffold(
        body: LoadingState(message: 'Cafe Bridge를 준비하는 중입니다.'),
      );
    }

    if (!appState.isAuthenticated) {
      if (_wasAuthenticated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          widget.navigatorKey.currentState?.popUntil((route) => route.isFirst);
        });
      }
      _wasAuthenticated = false;
      return const LoginScreen();
    }

    _wasAuthenticated = true;
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

  static const navigationItems = <_NavigationItem>[
    _NavigationItem(
      title: '홈',
      label: '홈',
      icon: Icons.space_dashboard_outlined,
      selectedIcon: Icons.space_dashboard,
      screen: DashboardScreen(),
    ),
    _NavigationItem(
      title: '인사이트',
      label: '분석',
      icon: Icons.analytics_outlined,
      selectedIcon: Icons.analytics,
      screen: AnalyticsScreen(),
    ),
    _NavigationItem(
      title: '업무',
      label: '업무',
      icon: Icons.handyman_outlined,
      selectedIcon: Icons.handyman,
      screen: OperationsScreen(),
    ),
    _NavigationItem(
      title: '인력',
      label: '인력',
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
      screen: WorkforceScreen(),
    ),
    _NavigationItem(
      title: '더보기',
      label: '더보기',
      icon: Icons.widgets_outlined,
      selectedIcon: Icons.widgets,
      screen: MoreScreen(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final userRole =
        context.select<AppState, UserRole>((state) => state.userRole);
    final offlineMode =
        context.select<AppState, bool>((state) => state.offlineMode);
    final hasRecommendedUpdate =
        context.select<AppState, bool>((state) => state.hasRecommendedUpdate);
    const navigationItems = _MainLayoutState.navigationItems;
    final currentIndex = _currentIndex.clamp(0, navigationItems.length - 1);

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 60,
        leading: Padding(
          padding: const EdgeInsets.only(left: 14, top: 8, bottom: 8),
          child: Image.asset(
            cafeBridgeLogoAsset,
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
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(
              userRole.label,
              style: const TextStyle(
                color: AppColors.primaryDark,
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
            color: AppColors.border,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (offlineMode)
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
                      color: AppColors.offlineForeground,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '오프라인 캐시 모드로 표시 중입니다.',
                        style: TextStyle(
                          color: AppColors.offlineForeground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (hasRecommendedUpdate) const AppUpdateBanner(dense: true),
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
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
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

  const _NavigationItem({
    required this.title,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.screen,
  });
}
