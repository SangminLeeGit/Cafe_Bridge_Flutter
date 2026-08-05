import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cafe_bridge_flutter/screens/more.dart';
import 'package:cafe_bridge_flutter/screens/operations.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:cafe_bridge_flutter/theme/app_theme.dart';
import 'package:cafe_bridge_flutter/widgets/app_screen.dart';

Widget _testApp(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: child,
  );
}

void main() {
  testWidgets('common screen shell renders title and content', (tester) async {
    await tester.pumpWidget(
      _testApp(
        const AppScreen(
          title: '업무',
          subtitle: '운영 도구',
          body: Center(child: Text('화면 내용')),
        ),
      ),
    );

    expect(find.text('업무'), findsOneWidget);
    expect(find.text('운영 도구'), findsOneWidget);
    expect(find.text('화면 내용'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets('viewer sees locked operator and admin work entries',
      (tester) async {
    final appState = AppState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: _testApp(const OperationsScreen()),
      ),
    );

    expect(find.text('상품 조회'), findsOneWidget);
    expect(find.text('operator 필요'), findsNWidgets(4));
    expect(find.text('admin 필요'), findsOneWidget);
  });

  testWidgets('more screen keeps admin tools visible but locked',
      (tester) async {
    final appState = AppState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: _testApp(const MoreScreen()),
      ),
    );

    expect(find.text('운영 도구'), findsOneWidget);
    expect(find.text('앱 설정'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('일일보고서'),
      500,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('admin 필요'), findsNWidgets(3));
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(3));
  });
}
