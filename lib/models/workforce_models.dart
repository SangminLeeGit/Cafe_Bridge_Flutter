import 'api_contracts.dart';

// Models for the workforce (인력 관리) feature.

class WorkforceDashboardWorkplace {
  final int id;
  final String name;
  final String payCycle;
  final String nextPayday;
  final int daysUntilPayday;
  final int grossPay;
  final int netPay;
  final double workedHours;

  const WorkforceDashboardWorkplace({
    required this.id,
    required this.name,
    required this.payCycle,
    required this.nextPayday,
    required this.daysUntilPayday,
    required this.grossPay,
    required this.netPay,
    required this.workedHours,
  });

  factory WorkforceDashboardWorkplace.fromJson(Map<String, dynamic> json) {
    return WorkforceDashboardWorkplace(
      id: asInt(json['id']),
      name: asString(json['name']),
      payCycle: asString(json['pay_cycle']),
      nextPayday: asString(json['next_payday']),
      daysUntilPayday: asInt(json['days_until_payday']),
      grossPay: asInt(json['gross_pay']),
      netPay: asInt(json['net_pay']),
      workedHours: asDouble(json['worked_hours']),
    );
  }
}

class WorkforceSummary {
  final int totalGrossPay;
  final int totalNetPay;
  final double totalWorkedHours;
  final int shiftCount;
  final int employeeCount;
  final int workplaceCount;
  final double workedHours;
  final int grossPay;
  final int taxDeduction;
  final int netPay;

  const WorkforceSummary({
    this.totalGrossPay = 0,
    this.totalNetPay = 0,
    this.totalWorkedHours = 0,
    this.shiftCount = 0,
    this.employeeCount = 0,
    this.workplaceCount = 0,
    this.workedHours = 0,
    this.grossPay = 0,
    this.taxDeduction = 0,
    this.netPay = 0,
  });

  factory WorkforceSummary.fromJson(Map<String, dynamic> json) {
    return WorkforceSummary(
      totalGrossPay: asInt(json['total_gross_pay']),
      totalNetPay: asInt(json['total_net_pay']),
      totalWorkedHours: asDouble(json['total_worked_hours']),
      shiftCount: asInt(json['shift_count']),
      employeeCount: asInt(json['employee_count']),
      workplaceCount: asInt(json['workplace_count']),
      workedHours: asDouble(json['worked_hours']),
      grossPay: asInt(json['gross_pay']),
      taxDeduction: asInt(json['tax_deduction']),
      netPay: asInt(json['net_pay']),
    );
  }
}

class WorkforceDashboardData {
  final Map<String, String> period;
  final WorkforceSummary summary;
  final List<WorkforceDashboardWorkplace> workplaces;
  final int minimumWage;

  const WorkforceDashboardData({
    required this.period,
    required this.summary,
    required this.workplaces,
    required this.minimumWage,
  });

  factory WorkforceDashboardData.fromJson(Map<String, dynamic> json) {
    final rawPeriod = json['period'];
    final period = <String, String>{};
    if (rawPeriod is Map) {
      rawPeriod.forEach((k, v) => period[k.toString()] = v?.toString() ?? '');
    }
    return WorkforceDashboardData(
      period: period,
      summary: WorkforceSummary.fromJson(asMap(json['summary'])),
      workplaces: asListOfMaps(json['workplaces'])
          .map(WorkforceDashboardWorkplace.fromJson)
          .toList(growable: false),
      minimumWage: asInt(json['minimum_wage']),
    );
  }
}

class CalendarDay {
  final String date;
  final int shiftCount;
  final int workedMinutes;
  final double workedHours;
  final int grossPay;

  const CalendarDay({
    required this.date,
    required this.shiftCount,
    required this.workedMinutes,
    required this.workedHours,
    required this.grossPay,
  });

  factory CalendarDay.fromJson(Map<String, dynamic> json) {
    return CalendarDay(
      date: asString(json['date']),
      shiftCount: asInt(json['shift_count']),
      workedMinutes: asInt(json['worked_minutes']),
      workedHours: asDouble(json['worked_hours']),
      grossPay: asInt(json['gross_pay']),
    );
  }
}

class WorkloadCalendarData {
  final int year;
  final int month;
  final String fromDate;
  final String toDate;
  final List<CalendarDay> days;
  final WorkforceSummary summary;

  const WorkloadCalendarData({
    required this.year,
    required this.month,
    required this.fromDate,
    required this.toDate,
    required this.days,
    required this.summary,
  });

  factory WorkloadCalendarData.fromJson(Map<String, dynamic> json) {
    return WorkloadCalendarData(
      year: asInt(json['year']),
      month: asInt(json['month']),
      fromDate: asString(json['from_date']),
      toDate: asString(json['to_date']),
      days: requireListOfMaps(json, 'days')
          .map(CalendarDay.fromJson)
          .toList(growable: false),
      summary: WorkforceSummary.fromJson(asMap(json['summary'])),
    );
  }
}

class WorkplacePayRule {
  final int? hourlyWage;
  final int? dailyWage;
  final int? monthlySalary;
  final int defaultBreakMinutes;
  final int overtimeDailyThresholdMinutes;
  final bool nightEnabled;
  final bool overtimeEnabled;
  final bool holidayEnabled;
  final bool weeklyHolidayEnabled;
  final int weeklyHolidayStartDow;
  final int weeklyHolidayMinMinutes;
  final int weeklyHolidayMinDays;
  final double nightMultiplier;
  final double overtimeMultiplier;
  final double holidayMultiplierUnder8;
  final double holidayMultiplierOver8;

  const WorkplacePayRule({
    required this.hourlyWage,
    required this.dailyWage,
    required this.monthlySalary,
    required this.defaultBreakMinutes,
    required this.overtimeDailyThresholdMinutes,
    required this.nightEnabled,
    required this.overtimeEnabled,
    required this.holidayEnabled,
    required this.weeklyHolidayEnabled,
    required this.weeklyHolidayStartDow,
    required this.weeklyHolidayMinMinutes,
    required this.weeklyHolidayMinDays,
    required this.nightMultiplier,
    required this.overtimeMultiplier,
    required this.holidayMultiplierUnder8,
    required this.holidayMultiplierOver8,
  });

  factory WorkplacePayRule.fromJson(Map<String, dynamic> json) {
    return WorkplacePayRule(
      hourlyWage: asNullableInt(json['hourly_wage']),
      dailyWage: asNullableInt(json['daily_wage']),
      monthlySalary: asNullableInt(json['monthly_salary']),
      defaultBreakMinutes: asInt(json['default_break_minutes']),
      overtimeDailyThresholdMinutes:
          asInt(json['overtime_daily_threshold_minutes']),
      nightEnabled: asBool(json['night_enabled'], defaultValue: true),
      overtimeEnabled: asBool(json['overtime_enabled'], defaultValue: true),
      holidayEnabled: asBool(json['holiday_enabled'], defaultValue: true),
      weeklyHolidayEnabled:
          asBool(json['weekly_holiday_enabled'], defaultValue: true),
      weeklyHolidayStartDow: asInt(json['weekly_holiday_start_dow']),
      weeklyHolidayMinMinutes: asInt(json['weekly_holiday_min_minutes']),
      weeklyHolidayMinDays: asInt(json['weekly_holiday_min_days']),
      nightMultiplier: asDouble(json['night_multiplier']),
      overtimeMultiplier: asDouble(json['overtime_multiplier']),
      holidayMultiplierUnder8: asDouble(json['holiday_multiplier_under8']),
      holidayMultiplierOver8: asDouble(json['holiday_multiplier_over8']),
    );
  }
}

class WorkplaceTaxRule {
  final String preset;
  final double customRate;
  final String applyUnit;

  const WorkplaceTaxRule({
    required this.preset,
    required this.customRate,
    required this.applyUnit,
  });

  factory WorkplaceTaxRule.fromJson(Map<String, dynamic> json) {
    return WorkplaceTaxRule(
      preset: asString(json['preset']),
      customRate: asDouble(json['custom_rate']),
      applyUnit: asString(json['apply_unit']),
    );
  }
}

class Workplace {
  final int id;
  final String name;
  final String shopNo;
  final String payType;
  final String payCycle;
  final int payday;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final WorkplacePayRule? payRule;
  final WorkplaceTaxRule? taxRule;

  const Workplace({
    required this.id,
    required this.name,
    required this.shopNo,
    required this.payType,
    required this.payCycle,
    required this.payday,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.payRule,
    required this.taxRule,
  });

  factory Workplace.fromJson(Map<String, dynamic> json) {
    return Workplace(
      id: asInt(json['id']),
      name: asString(json['name']),
      shopNo: asString(json['shop_no']),
      payType: asString(json['pay_type']),
      payCycle: asString(json['pay_cycle']),
      payday: asInt(json['payday']),
      isActive: asBool(json['is_active']),
      createdAt: asDateTime(json['created_at']),
      updatedAt: asDateTime(json['updated_at']),
      payRule: json['pay_rule'] is Map
          ? WorkplacePayRule.fromJson(asMap(json['pay_rule']))
          : null,
      taxRule: json['tax_rule'] is Map
          ? WorkplaceTaxRule.fromJson(asMap(json['tax_rule']))
          : null,
    );
  }
}

class ShiftAdjustment {
  final int? id;
  final String kind;
  final String label;
  final int amount;

  const ShiftAdjustment({
    required this.id,
    required this.kind,
    required this.label,
    required this.amount,
  });

  factory ShiftAdjustment.fromJson(Map<String, dynamic> json) {
    return ShiftAdjustment(
      id: asNullableInt(json['id']),
      kind: asString(json['kind']),
      label: asString(json['label']),
      amount: asInt(json['amount']),
    );
  }
}

class ShiftRecord {
  final int id;
  final int workplaceId;
  final String workplaceName;
  final int? employeeId;
  final String? employeeName;
  final String shiftDate;
  final String startAt;
  final String endAt;
  final int breakMinutes;
  final String leaveType;
  final String holidayType;
  final String memo;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<ShiftAdjustment> adjustments;

  const ShiftRecord({
    required this.id,
    required this.workplaceId,
    required this.workplaceName,
    required this.employeeId,
    required this.employeeName,
    required this.shiftDate,
    required this.startAt,
    required this.endAt,
    required this.breakMinutes,
    required this.leaveType,
    required this.holidayType,
    required this.memo,
    required this.createdAt,
    required this.updatedAt,
    required this.adjustments,
  });

  factory ShiftRecord.fromJson(Map<String, dynamic> json) {
    return ShiftRecord(
      id: asInt(json['id']),
      workplaceId: asInt(json['workplace_id']),
      workplaceName: asString(json['workplace_name']),
      employeeId: asNullableInt(json['employee_id']),
      employeeName: asNullableString(json['employee_name']),
      shiftDate: asString(json['shift_date']),
      startAt: asString(json['start_at']),
      endAt: asString(json['end_at']),
      breakMinutes: asInt(json['break_minutes']),
      leaveType: asString(json['leave_type']),
      holidayType: asString(json['holiday_type']),
      memo: asString(json['memo']),
      createdAt: asDateTime(json['created_at']),
      updatedAt: asDateTime(json['updated_at']),
      adjustments: asListOfMaps(json['adjustments'])
          .map(ShiftAdjustment.fromJson)
          .toList(growable: false),
    );
  }
}

class ShiftPreset {
  final int id;
  final int workplaceId;
  final String workplaceName;
  final String name;
  final String startTime;
  final String endTime;
  final int breakMinutes;
  final String leaveType;
  final String holidayType;
  final String memo;
  final int extraAmount;
  final int deductionAmount;
  final bool isFavorite;

  const ShiftPreset({
    required this.id,
    required this.workplaceId,
    required this.workplaceName,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.breakMinutes,
    required this.leaveType,
    required this.holidayType,
    required this.memo,
    required this.extraAmount,
    required this.deductionAmount,
    required this.isFavorite,
  });

  factory ShiftPreset.fromJson(Map<String, dynamic> json) {
    return ShiftPreset(
      id: asInt(json['id']),
      workplaceId: asInt(json['workplace_id']),
      workplaceName: asString(json['workplace_name']),
      name: asString(json['name']),
      startTime: asString(json['start_time']),
      endTime: asString(json['end_time']),
      breakMinutes: asInt(json['break_minutes']),
      leaveType: asString(json['leave_type']),
      holidayType: asString(json['holiday_type']),
      memo: asString(json['memo']),
      extraAmount: asInt(json['extra_amount']),
      deductionAmount: asInt(json['deduction_amount']),
      isFavorite: asBool(json['is_favorite']),
    );
  }
}

class Employee {
  final int id;
  final int workplaceId;
  final String workplaceName;
  final String name;
  final String employeeNo;
  final String role;
  final String employmentType;
  final String joinedOn;
  final String resignedOn;
  final String phone;
  final int? hourlyWage;
  final int? monthlySalary;
  final String monthlySalaryCalculationMode;
  final String taxPreset;
  final double taxCustomRate;
  final String memo;
  final int? linkedAuthUserId;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Employee({
    required this.id,
    required this.workplaceId,
    required this.workplaceName,
    required this.name,
    required this.employeeNo,
    required this.role,
    required this.employmentType,
    required this.joinedOn,
    required this.resignedOn,
    required this.phone,
    required this.hourlyWage,
    required this.monthlySalary,
    required this.monthlySalaryCalculationMode,
    required this.taxPreset,
    required this.taxCustomRate,
    required this.memo,
    required this.linkedAuthUserId,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: asInt(json['id']),
      workplaceId: asInt(json['workplace_id']),
      workplaceName: asString(json['workplace_name']),
      name: asString(json['name']),
      employeeNo: asString(json['employee_no']),
      role: asString(json['role']),
      employmentType: asString(json['employment_type']),
      joinedOn: asString(json['joined_on']),
      resignedOn: asString(json['resigned_on']),
      phone: asString(json['phone']),
      hourlyWage: asNullableInt(json['hourly_wage']),
      monthlySalary: asNullableInt(json['monthly_salary']),
      monthlySalaryCalculationMode:
          asString(json['monthly_salary_calculation_mode']),
      taxPreset: asString(json['tax_preset']),
      taxCustomRate: asDouble(json['tax_custom_rate']),
      memo: asString(json['memo']),
      linkedAuthUserId: asNullableInt(json['linked_auth_user_id']),
      isActive: asBool(json['is_active']),
      createdAt: asDateTime(json['created_at']),
      updatedAt: asDateTime(json['updated_at']),
    );
  }

  Map<String, dynamic> toPatchPayload({bool? active}) => {
        'workplace_id': workplaceId,
        'name': name,
        'employee_no': employeeNo,
        'role': role,
        'employment_type': employmentType,
        'joined_on': joinedOn,
        'resigned_on': resignedOn,
        'phone': phone,
        'hourly_wage': hourlyWage,
        'monthly_salary': monthlySalary,
        'monthly_salary_calculation_mode': monthlySalaryCalculationMode.isEmpty
            ? 'prorated_hours'
            : monthlySalaryCalculationMode,
        'tax_preset': taxPreset,
        'tax_custom_rate': taxCustomRate,
        'memo': memo,
        'linked_auth_user_id': linkedAuthUserId,
        'is_active': active ?? isActive,
      };
}

class EmployeeAuditLog {
  final int id;
  final String action;
  final DateTime? createdAt;
  final int? actorAuthUserId;
  final Map<String, dynamic> beforeJson;
  final Map<String, dynamic> afterJson;

  const EmployeeAuditLog({
    required this.id,
    required this.action,
    required this.createdAt,
    required this.actorAuthUserId,
    required this.beforeJson,
    required this.afterJson,
  });

  factory EmployeeAuditLog.fromJson(Map<String, dynamic> json) {
    return EmployeeAuditLog(
      id: asInt(json['id']),
      action: asString(json['action']),
      createdAt: asDateTime(json['created_at']),
      actorAuthUserId: asNullableInt(json['actor_auth_user_id']),
      beforeJson: asMap(json['before_json']),
      afterJson: asMap(json['after_json']),
    );
  }
}

class PayslipLineItem {
  final String kind;
  final String date;
  final String label;
  final int amount;

  const PayslipLineItem({
    required this.kind,
    required this.date,
    required this.label,
    required this.amount,
  });

  factory PayslipLineItem.fromJson(Map<String, dynamic> json) {
    return PayslipLineItem(
      kind: asString(json['kind']),
      date: asString(json['date']),
      label: asString(json['label']),
      amount: asInt(json['amount']),
    );
  }
}

class PayslipWorkplaceTotals {
  final double workedHours;
  final int regularPay;
  final int nightPremium;
  final int overtimePremium;
  final int holidayPremium;
  final int weeklyHolidayPay;
  final int extraPay;
  final int manualDeduction;
  final int grossPay;
  final int taxDeduction;
  final int netPay;

  const PayslipWorkplaceTotals({
    required this.workedHours,
    required this.regularPay,
    required this.nightPremium,
    required this.overtimePremium,
    required this.holidayPremium,
    required this.weeklyHolidayPay,
    required this.extraPay,
    required this.manualDeduction,
    required this.grossPay,
    required this.taxDeduction,
    required this.netPay,
  });

  factory PayslipWorkplaceTotals.fromJson(Map<String, dynamic> json) {
    return PayslipWorkplaceTotals(
      workedHours: asDouble(json['worked_hours']),
      regularPay: asInt(json['regular_pay']),
      nightPremium: asInt(json['night_premium']),
      overtimePremium: asInt(json['overtime_premium']),
      holidayPremium: asInt(json['holiday_premium']),
      weeklyHolidayPay: asInt(json['weekly_holiday_pay']),
      extraPay: asInt(json['extra_pay']),
      manualDeduction: asInt(json['manual_deduction']),
      grossPay: asInt(json['gross_pay']),
      taxDeduction: asInt(json['tax_deduction']),
      netPay: asInt(json['net_pay']),
    );
  }
}

class PayslipWorkplace {
  final Workplace workplace;
  final PayslipWorkplaceTotals totals;
  final List<PayslipLineItem> lineItems;

  const PayslipWorkplace({
    required this.workplace,
    required this.totals,
    required this.lineItems,
  });

  factory PayslipWorkplace.fromJson(Map<String, dynamic> json) {
    return PayslipWorkplace(
      workplace: Workplace.fromJson(asMap(json['workplace'])),
      totals: PayslipWorkplaceTotals.fromJson(asMap(json['totals'])),
      lineItems: asListOfMaps(json['line_items'])
          .map(PayslipLineItem.fromJson)
          .toList(growable: false),
    );
  }
}

class EmployeeDetailData {
  final Employee employee;
  final List<ShiftRecord> recentShifts;

  const EmployeeDetailData({
    required this.employee,
    required this.recentShifts,
  });

  factory EmployeeDetailData.fromJson(Map<String, dynamic> json) {
    return EmployeeDetailData(
      employee: Employee.fromJson(asMap(json['employee'])),
      recentShifts: asListOfMaps(json['recent_shifts'])
          .map(ShiftRecord.fromJson)
          .toList(growable: false),
    );
  }
}

class EmployeePayslipData {
  final Employee employee;
  final String fromDate;
  final String toDate;
  final WorkforceSummary summary;
  final List<PayslipWorkplace> workplaces;

  const EmployeePayslipData({
    required this.employee,
    required this.fromDate,
    required this.toDate,
    required this.summary,
    required this.workplaces,
  });

  factory EmployeePayslipData.fromJson(Map<String, dynamic> json) {
    return EmployeePayslipData(
      employee: Employee.fromJson(asMap(json['employee'])),
      fromDate: asString(json['from_date']),
      toDate: asString(json['to_date']),
      summary: WorkforceSummary.fromJson(asMap(json['summary'])),
      workplaces: asListOfMaps(json['workplaces'])
          .map(PayslipWorkplace.fromJson)
          .toList(growable: false),
    );
  }
}

class WorkforcePeriodData {
  final String fromDate;
  final String toDate;
  final WorkforceSummary summary;
  final List<PayslipWorkplace> workplaces;

  const WorkforcePeriodData({
    required this.fromDate,
    required this.toDate,
    required this.summary,
    required this.workplaces,
  });

  factory WorkforcePeriodData.fromJson(Map<String, dynamic> json) {
    return WorkforcePeriodData(
      fromDate: asString(json['from_date']),
      toDate: asString(json['to_date']),
      summary: WorkforceSummary.fromJson(asMap(json['summary'])),
      workplaces: asListOfMaps(json['workplaces'])
          .map(PayslipWorkplace.fromJson)
          .toList(growable: false),
    );
  }
}

class EmployeePayPreviewData {
  final Employee employee;
  final Workplace workplace;
  final EmployeePayPreview preview;

  const EmployeePayPreviewData({
    required this.employee,
    required this.workplace,
    required this.preview,
  });

  factory EmployeePayPreviewData.fromJson(Map<String, dynamic> json) {
    return EmployeePayPreviewData(
      employee: Employee.fromJson(asMap(json['employee'])),
      workplace: Workplace.fromJson(asMap(json['workplace'])),
      preview: EmployeePayPreview.fromJson(asMap(json['preview'])),
    );
  }
}

class EmployeePayPreview {
  final int workedMinutes;
  final int hourlyWage;
  final int regularPay;
  final int nightPremium;
  final int overtimePremium;
  final int holidayPremium;
  final int extraAmount;
  final int deductionAmount;
  final int grossPay;
  final int taxEstimate;
  final int netEstimate;

  const EmployeePayPreview({
    required this.workedMinutes,
    required this.hourlyWage,
    required this.regularPay,
    required this.nightPremium,
    required this.overtimePremium,
    required this.holidayPremium,
    required this.extraAmount,
    required this.deductionAmount,
    required this.grossPay,
    required this.taxEstimate,
    required this.netEstimate,
  });

  factory EmployeePayPreview.fromJson(Map<String, dynamic> json) {
    return EmployeePayPreview(
      workedMinutes: asInt(json['worked_minutes']),
      hourlyWage: asInt(json['hourly_wage']),
      regularPay: asInt(json['regular_pay']),
      nightPremium: asInt(json['night_premium']),
      overtimePremium: asInt(json['overtime_premium']),
      holidayPremium: asInt(json['holiday_premium']),
      extraAmount: asInt(json['extra_amount']),
      deductionAmount: asInt(json['deduction_amount']),
      grossPay: asInt(json['gross_pay']),
      taxEstimate: asInt(json['tax_estimate']),
      netEstimate: asInt(json['net_estimate']),
    );
  }
}

class WorkforceShiftDraft {
  final int? workplaceId;
  final int? employeeId;
  final String date;
  final String startTime;
  final String endTime;
  final int breakMinutes;
  final String leaveType;
  final String holidayType;
  final String memo;
  final int extraAmount;
  final int deductionAmount;

  const WorkforceShiftDraft({
    required this.workplaceId,
    required this.employeeId,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.breakMinutes,
    this.leaveType = 'none',
    this.holidayType = 'none',
    this.memo = '',
    this.extraAmount = 0,
    this.deductionAmount = 0,
  });

  factory WorkforceShiftDraft.fromShift(ShiftRecord shift) =>
      WorkforceShiftDraft(
        workplaceId: shift.workplaceId,
        employeeId: shift.employeeId,
        date: shift.shiftDate,
        startTime: workforceTimePart(shift.startAt),
        endTime: workforceTimePart(shift.endAt),
        breakMinutes: shift.breakMinutes,
        leaveType: shift.leaveType,
        holidayType: shift.holidayType,
        memo: shift.memo,
        extraAmount: shift.adjustments
            .where((item) => item.kind == 'extra')
            .fold(0, (sum, item) => sum + item.amount),
        deductionAmount: shift.adjustments
            .where((item) => item.kind == 'deduction')
            .fold(0, (sum, item) => sum + item.amount),
      );

  factory WorkforceShiftDraft.fromPreset(ShiftPreset preset, String date,
          {int? employeeId}) =>
      WorkforceShiftDraft(
        workplaceId: preset.workplaceId,
        employeeId: employeeId,
        date: date,
        startTime: preset.startTime,
        endTime: preset.endTime,
        breakMinutes: preset.breakMinutes,
        leaveType: preset.leaveType,
        holidayType: preset.holidayType,
        memo: preset.memo,
        extraAmount: preset.extraAmount,
        deductionAmount: preset.deductionAmount,
      );

  String? validate() {
    if (workplaceId == null) return '근무지를 선택하세요.';
    if (employeeId == null) return '직원을 선택하세요.';
    if (parseWorkforceDate(date) == null) {
      return '유효한 날짜를 YYYY-MM-DD 형식으로 입력하세요.';
    }
    final start = parseWorkforceTime(startTime);
    final end = parseWorkforceTime(endTime);
    if (start == null || end == null) return '시간을 HH:mm 형식으로 입력하세요.';
    if (start >= end) return '시작 시간은 종료 시간보다 빨라야 합니다.';
    if (breakMinutes < 0) return '휴게시간은 0분 이상이어야 합니다.';
    if (breakMinutes > end - start) return '휴게시간은 총 근무시간 이하여야 합니다.';
    if (extraAmount < 0 || deductionAmount < 0) return '금액은 0원 이상이어야 합니다.';
    return null;
  }

  Map<String, dynamic> toPayload() => {
        'workplace_id': workplaceId,
        'employee_id': employeeId,
        'start_at': '${date.trim()}T${normalizeWorkforceTime(startTime)}',
        'end_at': '${date.trim()}T${normalizeWorkforceTime(endTime)}',
        'break_minutes': breakMinutes,
        'leave_type': leaveType,
        'holiday_type': holidayType,
        'memo': memo.trim(),
        'adjustments': [
          if (extraAmount > 0)
            {'kind': 'extra', 'label': '추가 지급', 'amount': extraAmount},
          if (deductionAmount > 0)
            {'kind': 'deduction', 'label': '추가 차감', 'amount': deductionAmount},
        ],
      };
}

class WorkforcePresetDraft {
  final int? workplaceId;
  final String name;
  final String startTime;
  final String endTime;
  final int breakMinutes;
  final String leaveType;
  final String holidayType;
  final String memo;
  final int extraAmount;
  final int deductionAmount;
  final bool isFavorite;

  const WorkforcePresetDraft({
    required this.workplaceId,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.breakMinutes,
    this.leaveType = 'none',
    this.holidayType = 'none',
    this.memo = '',
    this.extraAmount = 0,
    this.deductionAmount = 0,
    this.isFavorite = false,
  });

  factory WorkforcePresetDraft.fromPreset(ShiftPreset preset) =>
      WorkforcePresetDraft(
        workplaceId: preset.workplaceId,
        name: preset.name,
        startTime: preset.startTime,
        endTime: preset.endTime,
        breakMinutes: preset.breakMinutes,
        leaveType: preset.leaveType,
        holidayType: preset.holidayType,
        memo: preset.memo,
        extraAmount: preset.extraAmount,
        deductionAmount: preset.deductionAmount,
        isFavorite: preset.isFavorite,
      );

  String? validate() {
    if (workplaceId == null) return '근무지를 선택하세요.';
    if (name.trim().isEmpty) return '프리셋 이름을 입력하세요.';
    final start = parseWorkforceTime(startTime);
    final end = parseWorkforceTime(endTime);
    if (start == null || end == null) return '시간을 HH:mm 형식으로 입력하세요.';
    if (start >= end) return '시작 시간은 종료 시간보다 빨라야 합니다.';
    if (breakMinutes < 0) return '휴게시간은 0분 이상이어야 합니다.';
    if (breakMinutes > end - start) return '휴게시간은 총 근무시간 이하여야 합니다.';
    if (extraAmount < 0 || deductionAmount < 0) return '금액은 0원 이상이어야 합니다.';
    return null;
  }

  Map<String, dynamic> toPayload() => {
        'workplace_id': workplaceId,
        'name': name.trim(),
        'start_time': normalizeWorkforceTime(startTime),
        'end_time': normalizeWorkforceTime(endTime),
        'break_minutes': breakMinutes,
        'leave_type': leaveType,
        'holiday_type': holidayType,
        'memo': memo.trim(),
        'extra_amount': extraAmount,
        'deduction_amount': deductionAmount,
        'is_favorite': isFavorite,
      };
}

DateTime? parseWorkforceDate(String value) {
  final text = value.trim();
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  final normalized =
      '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  return normalized == text ? parsed : null;
}

int? parseWorkforceTime(String value) {
  final match =
      RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch(value.trim());
  if (match == null) return null;
  final hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2)!);
  if (hour == null || minute == null || hour > 23 || minute > 59) return null;
  return hour * 60 + minute;
}

String normalizeWorkforceTime(String value) {
  final minutes = parseWorkforceTime(value);
  if (minutes == null) return value.trim();
  return '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
}

String workforceTimePart(String value) {
  final text = value.trim();
  final time = text.contains('T') ? text.split('T').last : text;
  return RegExp(r'^(\d{1,2}:\d{2})').firstMatch(time)?.group(1) ?? text;
}

String? validateEmployeeForm({
  required int? workplaceId,
  required String name,
  required String joinedOn,
  required String resignedOn,
  required String hourlyWage,
  required String taxRate,
}) {
  if (workplaceId == null) return '근무지를 선택하세요.';
  if (name.trim().isEmpty) return '직원 이름을 입력하세요.';
  final joined = joinedOn.trim().isEmpty ? null : parseWorkforceDate(joinedOn);
  final resigned =
      resignedOn.trim().isEmpty ? null : parseWorkforceDate(resignedOn);
  if (joinedOn.trim().isNotEmpty && joined == null) return '유효한 입사일을 입력하세요.';
  if (resignedOn.trim().isNotEmpty && resigned == null) {
    return '유효한 퇴사일을 입력하세요.';
  }
  if (joined != null && resigned != null && resigned.isBefore(joined)) {
    return '퇴사일은 입사일보다 빠를 수 없습니다.';
  }
  final wage =
      hourlyWage.trim().isEmpty ? null : int.tryParse(hourlyWage.trim());
  if (hourlyWage.trim().isNotEmpty && (wage == null || wage < 0)) {
    return '시급은 0원 이상이어야 합니다.';
  }
  final rate = double.tryParse(taxRate.trim());
  if (rate == null || rate < 0) return '세율은 0 이상이어야 합니다.';
  return null;
}
