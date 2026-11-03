import 'package:cafe_bridge_flutter/screens/workforce_mobile.dart';
import 'package:cafe_bridge_flutter/services/cache_store.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _WorkforceAppState extends AppState {
  final writes =
      <({String endpoint, String method, Map<String, dynamic>? body})>[];

  @override
  bool get hasOperatorAccess => true;

  @override
  Future<CachedDataResult<T>> fetchMapParsed<T>(
    String endpoint, {
    Map<String, Object?>? params,
    required T Function(Map<String, dynamic> json) parser,
    Duration cacheTtl = const Duration(minutes: 30),
    bool allowStaleOnError = true,
    ApiCachePolicy? cachePolicy,
  }) async {
    final Map<String, dynamic> json = switch (endpoint) {
      '/api/workforce/dashboard' => _dashboard,
      '/api/workforce/workplaces' => {
          'workplaces': [_workplace]
        },
      '/api/workforce/employees' => {
          'employees': [_employee]
        },
      '/api/workforce/shifts' => {
          'shifts': [_shift]
        },
      '/api/workforce/presets' => {'presets': []},
      _ => throw StateError('unexpected GET $endpoint'),
    };
    return CachedDataResult<T>(
      data: parser(json),
      fromCache: false,
      cachedAt: DateTime.utc(2026, 10, 1),
    );
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String endpoint, {
    Map<String, dynamic>? body,
    String method = 'POST',
  }) async {
    writes.add((endpoint: endpoint, method: method, body: body));
    if (endpoint == '/api/workforce/shifts/confirm') {
      return {'updated_count': 1, 'confirmed': body?['confirmed']};
    }
    throw StateError('unexpected write $endpoint');
  }
}

const _workplace = {
  'id': 7,
  'name': '본점',
  'shop_no': '1',
  'pay_type': 'hourly',
  'pay_cycle': 'monthly',
  'payday': 10,
  'is_active': true,
};

const _employee = {
  'id': 3,
  'workplace_id': 7,
  'workplace_name': '본점',
  'name': '홍길동',
  'role': '바리스타',
  'employment_type': 'part_time',
  'joined_on': '2026-01-01',
  'hourly_wage': 12000,
  'monthly_salary_calculation_mode': 'prorated_hours',
  'tax_preset': 'inherit',
  'is_active': true,
};

const _shift = {
  'id': 31,
  'workplace_id': 7,
  'workplace_name': '본점',
  'employee_id': 3,
  'employee_name': '홍길동',
  'shift_date': '2026-10-12',
  'start_at': '2026-10-12T09:00:00',
  'end_at': '2026-10-12T18:00:00',
  'break_minutes': 60,
  'leave_type': 'none',
  'holiday_type': 'none',
  'memo': '',
  'confirmed_at': null,
  'adjustments': [],
};

const _dashboard = {
  'period': {'from_date': '2026-10-01', 'to_date': '2026-10-31'},
  'summary': {
    'total_gross_pay': 0,
    'total_net_pay': 0,
    'total_worked_hours': 0,
    'shift_count': 0,
    'employee_count': 1,
    'workplace_count': 1,
  },
  'workplaces': [],
  'minimum_wage': 10320,
};

void main() {
  testWidgets(
      'confirms the currently filtered shift period with backend payload',
      (tester) async {
    final state = _WorkforceAppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const MaterialApp(home: Scaffold(body: WorkforceScreen())),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('근무').last);
    await tester.pumpAndSettle();
    expect(find.text('미확정'), findsOneWidget);
    expect(find.text('확정 근무'), findsOneWidget);

    final confirmPeriod = find.text('필터 기간 근무 확정');
    await tester.ensureVisible(confirmPeriod);
    await tester.tap(confirmPeriod);
    await tester.pumpAndSettle();
    expect(find.textContaining('현재 필터 근무를 확정합니다.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '확정'));
    await tester.pumpAndSettle();

    final write = state.writes.single;
    expect(write.endpoint, '/api/workforce/shifts/confirm');
    expect(write.method, 'POST');
    expect(write.body?['from_date'], isA<String>());
    expect(write.body?['to_date'], isA<String>());
    expect(write.body?['confirmed'], isTrue);
    expect(write.body, isNot(contains('shift_ids')));
    expect(find.text('1건의 근무를 확정했습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
