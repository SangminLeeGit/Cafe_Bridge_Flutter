import 'package:cafe_bridge_flutter/main.dart';
import 'package:cafe_bridge_flutter/screens/analytics.dart';
import 'package:cafe_bridge_flutter/screens/dashboard.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  test('CafeBridgeApp can be instantiated', () {
    expect(const CafeBridgeApp(), isNotNull);
  });

  testWidgets('main layout lazily creates root destinations', (tester) async {
    final appState = AppState();
    addTearDown(appState.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MaterialApp(home: MainLayout()),
      ),
    );

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.byType(AnalyticsScreen), findsNothing);

    await tester.tap(find.text('분석'));
    await tester.pump();

    expect(find.byType(AnalyticsScreen), findsOneWidget);
  });
}
