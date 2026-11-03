import 'package:cafe_bridge_flutter/screens/payroll_runs.dart';
import 'package:cafe_bridge_flutter/services/cache_store.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _PayrollAppState extends AppState {
  final reads = <({String endpoint, Map<String, Object?>? params})>[];
  final writes =
      <({String endpoint, String method, Map<String, dynamic>? body})>[];
  String status = 'reviewed';

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
    reads.add((endpoint: endpoint, params: params));
    final json = switch (endpoint) {
      '/api/workforce/workplaces' => {
          'workplaces': [_workplaceJson]
        },
      '/api/workforce/payroll-runs' => {
          'runs': [_runJson(status: status, detail: false)]
        },
      '/api/workforce/payroll-runs/run-a' => _runJson(status: status),
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
    if (endpoint.endsWith('/review')) status = 'reviewed';
    if (endpoint.endsWith('/confirm')) status = 'confirmed';
    return _runJson(status: status);
  }
}

const _workplaceJson = {
  'id': 7,
  'name': '본점',
  'shop_no': '1',
  'pay_type': 'hourly',
  'pay_cycle': 'monthly',
  'payday': 10,
  'is_active': true,
};

Map<String, dynamic> _runJson(
        {String status = 'reviewed', bool detail = true}) =>
    {
      'run_id': 'run-a',
      'from_date': '2026-10-01',
      'to_date': '2026-10-31',
      'workplace_id': 7,
      'status': status,
      'version': 1,
      'source': 'manual',
      'created_at': '2026-11-01T00:00:00Z',
      'totals': {
        'worked_hours': 8.0,
        'gross_pay': 100000,
        'tax_deduction': 3300,
        'net_pay': 96700,
      },
      'issues': [
        {
          'code': 'unconfirmed_shifts_excluded',
          'severity': 'warning',
          'message': '미확정 근무 1건은 정산에서 제외했습니다.',
          'employee_id': 3,
          'employee_name': '홍길동',
          'date': '2026-10-12',
        },
      ],
      if (detail) ...{
        'statements': [
          {
            'statement_id': 11,
            'employee_id': 3,
            'employee_name': '홍길동',
            'totals': {
              'worked_hours': 8.0,
              'gross_pay': 100000,
              'tax_deduction': 3300,
              'net_pay': 96700,
            },
            'issues': [],
          },
        ],
        'llm_result': {
          'status': 'completed',
          'provider': 'fake-provider',
          'summary': '확인 의견입니다.',
          'checks': [],
          'error': '',
        },
      },
    };

void main() {
  testWidgets('creates a payroll draft with selected dates and workplace',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _PayrollAppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const MaterialApp(home: PayrollRunsScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<int?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('본점').last);
    await tester.pumpAndSettle();
    final createButton = find.widgetWithText(FilledButton, '정산 초안 만들기');
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    final createWrite = state.writes.single;
    expect(createWrite.endpoint, '/api/workforce/payroll-runs');
    expect(createWrite.method, 'POST');
    expect(createWrite.body?['from_date'], isA<String>());
    expect(createWrite.body?['to_date'], isA<String>());
    expect(createWrite.body?['workplace_id'], 7);
  });

  testWidgets(
      'loads payroll list and detail, then confirms with issue acknowledgement',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _PayrollAppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const MaterialApp(home: PayrollRunsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('검토 완료'), findsWidgets);
    final listRead = state.reads.firstWhere(
      (request) => request.endpoint == '/api/workforce/payroll-runs',
    );
    expect(listRead.params?['from_date'], isA<String>());
    expect(listRead.params?['to_date'], isA<String>());
    expect(listRead.params?.containsKey('workplace_id'), isFalse);

    await tester.tap(find.byKey(const ValueKey('payroll-run-run-a')));
    await tester.pumpAndSettle();
    expect(find.textContaining('미확정 근무 1건은 정산에서 제외했습니다.'), findsOneWidget);
    expect(find.text('홍길동'), findsOneWidget);
    expect(find.textContaining('확인 의견입니다.'), findsOneWidget);

    final acknowledgement = find.byKey(const Key('payroll-acknowledge-issues'));
    await tester.ensureVisible(acknowledgement);
    await tester.tap(acknowledgement);
    await tester.pumpAndSettle();
    final confirmButton = find.widgetWithText(FilledButton, '확정');
    await tester.ensureVisible(confirmButton);
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    final confirmWrite = state.writes.singleWhere(
      (write) => write.endpoint == '/api/workforce/payroll-runs/run-a/confirm',
    );
    expect(confirmWrite.method, 'POST');
    expect(confirmWrite.body, {'acknowledge_issues': true});
    expect(
        state.reads.any((request) =>
            request.endpoint == '/api/workforce/payroll-runs/run-a'),
        isTrue);
    expect(find.textContaining('확정'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
