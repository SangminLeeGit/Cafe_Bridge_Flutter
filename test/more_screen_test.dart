import 'package:cafe_bridge_flutter/screens/more.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _MoreAppState extends AppState {
  _MoreAppState(this.admin);

  final bool admin;

  @override
  bool get hasAdminAccess => admin;
}

Widget _app(_MoreAppState state) {
  return ChangeNotifierProvider<AppState>.value(
    value: state,
    child: const MaterialApp(home: MoreScreen()),
  );
}

void main() {
  testWidgets('shows the new admin screens in More for administrators',
      (tester) async {
    final state = _MoreAppState(true);
    addTearDown(state.dispose);

    await tester.pumpWidget(_app(state));

    for (final title in ['일일보고서', '사용자 관리', '런타임 설정']) {
      final tile = find.text(title);
      await tester.scrollUntilVisible(
        tile,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tile, findsOneWidget);
    }
    expect(find.text('계정 생성 · 권한 · 상태 · 보안 감사'), findsOneWidget);
    expect(find.text('검증 · 테스트 · 적용 · 롤백'), findsOneWidget);
    expect(find.text('운영 설정 · 연결 테스트 · 수동 실행 · 전송 관리'),
        findsOneWidget);
    expect(find.text('admin 필요'), findsNothing);
  });

  testWidgets('keeps admin tools visible but locked for non-admin users',
      (tester) async {
    final state = _MoreAppState(false);
    addTearDown(state.dispose);

    await tester.pumpWidget(_app(state));

    final tile = find.text('런타임 설정');
    await tester.scrollUntilVisible(
      tile,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tile, findsOneWidget);
    expect(find.text('관리자 권한에서만 접근할 수 있습니다.').first, findsOneWidget);
    expect(find.text('admin 필요'), findsWidgets);
  });
}
