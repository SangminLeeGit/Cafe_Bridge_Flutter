import 'dart:async';

import 'package:cafe_bridge_flutter/models/workforce_models.dart';
import 'package:cafe_bridge_flutter/screens/workforce_mobile.dart';
import 'package:cafe_bridge_flutter/services/cache_store.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:cafe_bridge_flutter/widgets/workforce_shift_forms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _WorkforceFormAppState extends AppState {
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
      '/api/workforce/dashboard' => _dashboardJson,
      '/api/workforce/workplaces' => {
          'workplaces': [_formWorkplaceJson]
        },
      '/api/workforce/employees' => {'employees': []},
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
    return const {};
  }
}

const _formWorkplaceJson = {
  'id': 1,
  'name': '본점',
  'shop_no': '1',
  'pay_type': 'hourly',
  'pay_cycle': 'monthly',
  'payday': 10,
  'is_active': true,
};

const _dashboardJson = {
  'period': {'from_date': '2026-10-01', 'to_date': '2026-10-31'},
  'summary': {
    'total_gross_pay': 0,
    'total_net_pay': 0,
    'total_worked_hours': 0,
    'shift_count': 0,
    'employee_count': 0,
    'workplace_count': 1,
  },
  'workplaces': [],
  'minimum_wage': 10320,
};

void main() {
  testWidgets('workplace creation submits full pay and tax rules',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _WorkforceFormAppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const MaterialApp(home: Scaffold(body: WorkforceScreen())),
    ));
    await tester.pumpAndSettle();

    final addWorkplace = find.text('근무지 추가');
    await tester.ensureVisible(addWorkplace);
    await tester.tap(addWorkplace);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '새 근무지');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    final write = state.writes.single;
    expect(write.endpoint, '/api/workforce/workplaces');
    expect(write.body?['pay_rule'], containsPair('hourly_wage', null));
    expect(write.body?['pay_rule'], containsPair('daily_wage', null));
    expect(write.body?['pay_rule'], containsPair('monthly_salary', null));
    expect(write.body?['pay_rule'], containsPair('night_enabled', true));
    expect(
        write.body?['pay_rule'], containsPair('weekly_holiday_start_dow', 0));
    expect(write.body?['pay_rule'], contains('holiday_multiplier_over8'));
    expect(write.body?['tax_rule'], {
      'preset': 'none',
      'custom_rate': 0.0,
      'apply_unit': 'monthly',
    });
  });

  testWidgets('employee creation submits monthly salary and calculation mode',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _WorkforceFormAppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const MaterialApp(home: Scaffold(body: WorkforceScreen())),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('직원').last);
    await tester.pumpAndSettle();
    final addEmployee = find.text('직원 추가');
    await tester.ensureVisible(addEmployee);
    await tester.tap(addEmployee);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '정산 직원');
    await tester.enterText(find.byType(TextFormField).at(5), '3200000');
    final dropdowns = find.byType(DropdownButtonFormField<String>);
    await tester.tap(dropdowns.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('고정 기간급').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    final write = state.writes.single;
    expect(write.endpoint, '/api/workforce/employees');
    expect(write.body?['monthly_salary'], 3200000);
    expect(write.body?['monthly_salary_calculation_mode'], 'fixed_period');
  });

  testWidgets('shift form displays mobile validation errors', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WorkforceShiftFormDialog(
          workplaces: [_workplace()],
          employees: [_employee()],
          initialValue: const WorkforceShiftDraft(
            workplaceId: 1,
            employeeId: 2,
            date: '2026-07-24',
            startTime: '09:00',
            endTime: '18:00',
            breakMinutes: 60,
          ),
          editing: false,
          onPreview: (_) async => throw UnimplementedError(),
        ),
      ),
    ));

    await tester.enterText(find.byKey(const Key('shift-end')), '08:00');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pump();

    expect(find.byKey(const Key('shift-form-error')), findsOneWidget);
    expect(find.textContaining('시작 시간'), findsOneWidget);
  });

  test('employee validator accepts an omitted salary and rejects negatives',
      () {
    expect(
      validateEmployeeForm(
        workplaceId: 1,
        name: '홍길동',
        joinedOn: '',
        resignedOn: '',
        hourlyWage: '',
        taxRate: '0',
      ),
      isNull,
    );
    expect(
      validateEmployeeForm(
        workplaceId: 1,
        name: '홍길동',
        joinedOn: '',
        resignedOn: '',
        hourlyWage: '',
        taxRate: '0',
        monthlySalary: '-1',
      ),
      contains('월급'),
    );
  });

  testWidgets('preset form requires a name', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WorkforcePresetFormDialog(
          workplaces: [_workplace()],
          initialValue: const WorkforcePresetDraft(
            workplaceId: 1,
            name: '',
            startTime: '09:00',
            endTime: '18:00',
            breakMinutes: 60,
          ),
          editing: false,
        ),
      ),
    ));

    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pump();

    expect(find.byKey(const Key('preset-form-error')), findsOneWidget);
    expect(find.textContaining('프리셋 이름'), findsOneWidget);
  });

  testWidgets('shift preview is invalidated when inputs change',
      (tester) async {
    final preview = Completer<EmployeePayPreview>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WorkforceShiftFormDialog(
          workplaces: [_workplace()],
          employees: [_employee()],
          initialValue: const WorkforceShiftDraft(
            workplaceId: 1,
            employeeId: 2,
            date: '2026-07-24',
            startTime: '09:00',
            endTime: '18:00',
            breakMinutes: 60,
          ),
          editing: false,
          onPreview: (_) => preview.future,
        ),
      ),
    ));

    await tester.tap(find.widgetWithText(OutlinedButton, '급여 미리보기'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('shift-end')), '17:00');
    await tester.pump();
    expect(find.widgetWithText(OutlinedButton, '급여 미리보기'), findsOneWidget);
    preview.complete(_preview());
    await tester.pump();

    expect(find.byKey(const Key('shift-preview-result')), findsNothing);
  });

  testWidgets(
      'employee pay preview ignores an outstanding response after close',
      (tester) async {
    final preview = Completer<EmployeePayPreviewData>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => EmployeePayPreviewDialog(
                employee: _employee(),
                date: DateTime(2026, 10, 3),
                onPreview: (_) {
                  calls++;
                  return preview.future;
                },
              ),
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('계산'));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('계산 중...'), findsOneWidget);
    final busyButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '계산 중...'),
    );
    expect(busyButton.onPressed, isNull);

    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    preview.complete(_previewData());
    await tester.pump();

    expect(find.text('홍길동 급여 미리보기'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('employee pay preview result clears when its inputs change',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EmployeePayPreviewDialog(
          employee: _employee(),
          date: DateTime(2026, 10, 3),
          onPreview: (_) async => _previewData(),
        ),
      ),
    ));

    await tester.tap(find.text('계산'));
    await tester.pumpAndSettle();
    expect(find.text('96000원'), findsOneWidget);
    final startField = find.byType(TextFormField).first;
    await tester.enterText(startField, '10:00');
    await tester.pump();

    expect(find.text('96000원'), findsNothing);
  });
}

Workplace _workplace() => Workplace.fromJson({
      'id': 1,
      'name': '본점',
      'shop_no': '1',
      'pay_type': 'hourly',
      'pay_cycle': 'monthly',
      'payday': 10,
      'is_active': true,
    });

Employee _employee() => Employee.fromJson({
      'id': 2,
      'workplace_id': 1,
      'workplace_name': '본점',
      'name': '홍길동',
      'employee_no': 'E002',
      'role': '바리스타',
      'employment_type': 'part_time',
      'joined_on': '2026-01-01',
      'phone': '',
      'hourly_wage': 12000,
      'monthly_salary_calculation_mode': 'prorated_hours',
      'tax_preset': 'inherit',
      'tax_custom_rate': 0,
      'memo': '',
      'is_active': true,
    });

EmployeePayPreview _preview() => const EmployeePayPreview(
      workedMinutes: 480,
      hourlyWage: 12000,
      regularPay: 96000,
      nightPremium: 0,
      overtimePremium: 0,
      holidayPremium: 0,
      extraAmount: 0,
      deductionAmount: 0,
      grossPay: 96000,
      taxEstimate: 1000,
      netEstimate: 95000,
    );

EmployeePayPreviewData _previewData() => EmployeePayPreviewData(
      employee: _employee(),
      workplace: _workplace(),
      preview: _preview(),
    );
