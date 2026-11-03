import 'package:cafe_bridge_flutter/models/payroll_models.dart';
import 'package:cafe_bridge_flutter/models/workforce_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses payroll run totals, issues, statements and explanation', () {
    final run = PayrollRun.fromJson({
      'run_id': 'run-a',
      'from_date': '2026-10-01',
      'to_date': '2026-10-31',
      'workplace_id': 7,
      'status': 'reviewed',
      'version': 2,
      'source': 'manual',
      'totals': {
        'worked_hours': 12.5,
        'gross_pay': 150000,
        'tax_deduction': 4950,
        'net_pay': 145050,
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
      'statements': [
        {
          'statement_id': 10,
          'employee_id': 3,
          'employee_name': '홍길동',
          'totals': {
            'worked_hours': 12.5,
            'gross_pay': 150000,
            'tax_deduction': 4950,
            'net_pay': 145050,
          },
          'issues': [],
        },
      ],
      'llm_result': {
        'status': 'completed',
        'provider': 'test-provider',
        'summary': '근무와 급여 기준을 확인했습니다.',
        'checks': [
          {'item': '근무 확인', 'reason': '미확정 근무 제외', 'severity': 'warning'},
        ],
        'error': '',
      },
    });

    expect(run.status, 'reviewed');
    expect(run.totals.grossPay, 150000);
    expect(run.issueCount, 1);
    expect(run.issues.single.employeeName, '홍길동');
    expect(run.statements.single.employeeName, '홍길동');
    expect(run.explanation.provider, 'test-provider');
    expect(run.explanation.checks.single.item, '근무 확인');
    expect(payrollRunStatusLabel('draft'), '초안');
    expect(payrollRunStatusLabel('reviewed'), '검토 완료');
    expect(payrollRunStatusLabel('confirmed'), '확정');
    expect(payrollRunStatusLabel('superseded'), '대체됨');
  });

  test('parses shift confirmation timestamp', () {
    final shift = ShiftRecord.fromJson({
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
      'confirmed_at': '2026-10-13T01:02:03Z',
      'adjustments': [],
    });

    expect(shift.confirmedAt, DateTime.parse('2026-10-13T01:02:03Z'));
    expect(
        ShiftRecord.fromJson({
          'id': 32,
          'confirmed_at': null,
        }).confirmedAt,
        isNull);
  });

  test('workplace rule parsing uses backend defaults for missing values', () {
    final workplace = Workplace.fromJson({
      'id': 7,
      'name': '본점',
      'pay_rule': {
        'overtime_daily_threshold_minutes': null,
        'weekly_holiday_min_minutes': null,
        'weekly_holiday_min_days': null,
        'night_multiplier': null,
        'overtime_multiplier': null,
        'holiday_multiplier_under8': null,
        'holiday_multiplier_over8': null,
      },
      'tax_rule': {},
    });

    expect(workplace.payRule?.defaultBreakMinutes, 0);
    expect(workplace.payRule?.overtimeDailyThresholdMinutes, 480);
    expect(workplace.payRule?.weeklyHolidayMinMinutes, 900);
    expect(workplace.payRule?.weeklyHolidayMinDays, 1);
    expect(workplace.payRule?.nightMultiplier, 0.5);
    expect(workplace.payRule?.holidayMultiplierOver8, 1.0);
    expect(workplace.taxRule?.preset, 'none');
    expect(workplace.taxRule?.applyUnit, 'monthly');
  });
}
