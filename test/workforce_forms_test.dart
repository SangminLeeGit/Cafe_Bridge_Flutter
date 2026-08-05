import 'package:cafe_bridge_flutter/models/workforce_models.dart';
import 'package:cafe_bridge_flutter/widgets/workforce_shift_forms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shift form displays mobile validation errors', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 1000));
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
