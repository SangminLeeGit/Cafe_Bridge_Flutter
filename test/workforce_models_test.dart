import 'package:cafe_bridge_flutter/models/workforce_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkforceShiftDraft', () {
    test('validates required fields, times, break and amounts', () {
      const valid = WorkforceShiftDraft(
        workplaceId: 1,
        employeeId: 2,
        date: '2026-07-24',
        startTime: '09:00',
        endTime: '18:00',
        breakMinutes: 60,
      );

      expect(valid.validate(), isNull);
      expect(
        const WorkforceShiftDraft(
          workplaceId: 1,
          employeeId: 2,
          date: '2026-02-30',
          startTime: '09:00',
          endTime: '18:00',
          breakMinutes: 0,
        ).validate(),
        contains('유효한 날짜'),
      );
      expect(
        const WorkforceShiftDraft(
          workplaceId: 1,
          employeeId: 2,
          date: '2026-07-24',
          startTime: '18:00',
          endTime: '09:00',
          breakMinutes: 0,
        ).validate(),
        contains('시작 시간'),
      );
      expect(
        const WorkforceShiftDraft(
          workplaceId: 1,
          employeeId: 2,
          date: '2026-07-24',
          startTime: '09:00',
          endTime: '10:00',
          breakMinutes: 61,
        ).validate(),
        contains('총 근무시간'),
      );
    });

    test('creates the single-shift API payload with adjustments', () {
      const draft = WorkforceShiftDraft(
        workplaceId: 1,
        employeeId: 2,
        date: '2026-07-24',
        startTime: '9:00',
        endTime: '18:00',
        breakMinutes: 60,
        extraAmount: 1000,
        deductionAmount: 500,
      );

      final payload = draft.toPayload();
      expect(payload['start_at'], '2026-07-24T09:00');
      expect(payload['employee_id'], 2);
      expect(payload['adjustments'], hasLength(2));
      expect(payload, isNot(contains('dates')));
    });
  });

  test('preset validation rejects negative amounts', () {
    const draft = WorkforcePresetDraft(
      workplaceId: 1,
      name: '오픈',
      startTime: '08:00',
      endTime: '12:00',
      breakMinutes: 0,
      extraAmount: -1,
    );
    expect(draft.validate(), contains('금액'));
  });

  test('short and malformed datetime text never causes RangeError', () {
    expect(workforceTimePart('2026-07-24T9'), '2026-07-24T9');
    expect(workforceTimePart('9'), '9');
    expect(workforceTimePart('2026-07-24T09:30:00'), '09:30');
  });

  test('employee PATCH payload includes every nullable model field', () {
    final employee = Employee.fromJson({
      'id': 2,
      'workplace_id': 1,
      'workplace_name': '본점',
      'name': '홍길동',
      'employee_no': 'E002',
      'role': '바리스타',
      'employment_type': 'part_time',
      'joined_on': '2026-01-01',
      'resigned_on': null,
      'phone': '',
      'hourly_wage': 12000,
      'monthly_salary': null,
      'monthly_salary_calculation_mode': 'prorated_hours',
      'tax_preset': 'inherit',
      'tax_custom_rate': 0,
      'memo': '',
      'linked_auth_user_id': null,
      'is_active': true,
    });

    final payload = employee.toPatchPayload(active: false);
    expect(payload['is_active'], isFalse);
    expect(payload, containsPair('monthly_salary', null));
    expect(payload, containsPair('linked_auth_user_id', null));
    expect(payload['name'], '홍길동');
  });
}
