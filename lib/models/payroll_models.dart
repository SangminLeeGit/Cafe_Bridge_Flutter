import 'api_contracts.dart';

const Map<String, String> payrollRunStatusLabels = {
  'draft': '초안',
  'reviewed': '검토 완료',
  'confirmed': '확정',
  'superseded': '대체됨',
};

String payrollRunStatusLabel(String status) =>
    payrollRunStatusLabels[status] ?? status;

class PayrollRunTotals {
  final double workedHours;
  final int grossPay;
  final int taxDeduction;
  final int netPay;

  const PayrollRunTotals({
    required this.workedHours,
    required this.grossPay,
    required this.taxDeduction,
    required this.netPay,
  });

  factory PayrollRunTotals.fromJson(Map<String, dynamic> json) =>
      PayrollRunTotals(
        workedHours: asDouble(json['worked_hours']),
        grossPay: asInt(json['gross_pay']),
        taxDeduction: asInt(json['tax_deduction']),
        netPay: asInt(json['net_pay']),
      );
}

class PayrollRunIssue {
  final String code;
  final String severity;
  final String message;
  final int? shiftId;
  final int? employeeId;
  final String? employeeName;
  final String? date;

  const PayrollRunIssue({
    required this.code,
    required this.severity,
    required this.message,
    required this.shiftId,
    required this.employeeId,
    required this.employeeName,
    required this.date,
  });

  factory PayrollRunIssue.fromJson(Map<String, dynamic> json) =>
      PayrollRunIssue(
        code: asString(json['code']),
        severity: asString(json['severity']),
        message: asString(json['message']),
        shiftId: asNullableInt(json['shift_id']),
        employeeId: asNullableInt(json['employee_id']),
        employeeName: asNullableString(json['employee_name']),
        date: asNullableString(json['date']),
      );

  String get severityLabel => switch (severity) {
        'blocking' => '차단',
        'warning' => '주의',
        _ => severity.isEmpty ? '정보' : severity,
      };
}

class PayrollRunStatement {
  final int statementId;
  final int? workplaceId;
  final int? employeeId;
  final String employeeName;
  final PayrollRunTotals totals;
  final List<PayrollRunIssue> issues;

  const PayrollRunStatement({
    required this.statementId,
    required this.workplaceId,
    required this.employeeId,
    required this.employeeName,
    required this.totals,
    required this.issues,
  });

  factory PayrollRunStatement.fromJson(Map<String, dynamic> json) =>
      PayrollRunStatement(
        statementId: asInt(json['statement_id']),
        workplaceId: asNullableInt(json['workplace_id']),
        employeeId: asNullableInt(json['employee_id']),
        employeeName: asString(json['employee_name']),
        totals: PayrollRunTotals.fromJson(asMap(json['totals'])),
        issues: asListOfMaps(json['issues'])
            .map(PayrollRunIssue.fromJson)
            .toList(growable: false),
      );
}

class PayrollExplainCheck {
  final String item;
  final String reason;
  final String severity;

  const PayrollExplainCheck({
    required this.item,
    required this.reason,
    required this.severity,
  });

  factory PayrollExplainCheck.fromJson(Map<String, dynamic> json) =>
      PayrollExplainCheck(
        item: asString(json['item']),
        reason: asString(json['reason']),
        severity: asString(json['severity']),
      );
}

class PayrollRunExplanation {
  final String status;
  final String provider;
  final String model;
  final String summary;
  final List<PayrollExplainCheck> checks;
  final String error;

  const PayrollRunExplanation({
    required this.status,
    required this.provider,
    required this.model,
    required this.summary,
    required this.checks,
    required this.error,
  });

  factory PayrollRunExplanation.fromJson(Map<String, dynamic> json) =>
      PayrollRunExplanation(
        status: asString(json['status']),
        provider: asString(json['provider']),
        model: asString(json['model']),
        summary: asString(json['summary']),
        checks: asListOfMaps(json['checks'])
            .map(PayrollExplainCheck.fromJson)
            .toList(growable: false),
        error: asString(json['error']),
      );
}

class PayrollRun {
  final String runId;
  final String fromDate;
  final String toDate;
  final int? workplaceId;
  final String status;
  final int version;
  final String source;
  final PayrollRunTotals totals;
  final List<PayrollRunIssue> issues;
  final DateTime? createdAt;
  final DateTime? reviewedAt;
  final DateTime? confirmedAt;
  final String? supersededBy;
  final List<PayrollRunStatement> statements;
  final PayrollRunExplanation explanation;

  const PayrollRun({
    required this.runId,
    required this.fromDate,
    required this.toDate,
    required this.workplaceId,
    required this.status,
    required this.version,
    required this.source,
    required this.totals,
    required this.issues,
    required this.createdAt,
    required this.reviewedAt,
    required this.confirmedAt,
    required this.supersededBy,
    required this.statements,
    required this.explanation,
  });

  factory PayrollRun.fromJson(Map<String, dynamic> json) => PayrollRun(
        runId: asString(json['run_id']),
        fromDate: asString(json['from_date']),
        toDate: asString(json['to_date']),
        workplaceId: asNullableInt(json['workplace_id']),
        status: asString(json['status']),
        version: asInt(json['version']),
        source: asString(json['source']),
        totals: PayrollRunTotals.fromJson(asMap(json['totals'])),
        issues: asListOfMaps(json['issues'])
            .map(PayrollRunIssue.fromJson)
            .toList(growable: false),
        createdAt: asDateTime(json['created_at']),
        reviewedAt: asDateTime(json['reviewed_at']),
        confirmedAt: asDateTime(json['confirmed_at']),
        supersededBy: asNullableString(json['superseded_by']),
        statements: asListOfMaps(json['statements'])
            .map(PayrollRunStatement.fromJson)
            .toList(growable: false),
        explanation: PayrollRunExplanation.fromJson(asMap(json['llm_result'])),
      );

  int get issueCount => issues.length;
  bool get hasBlockingIssues =>
      issues.any((issue) => issue.severity == 'blocking');
}

class PayrollRunList {
  final List<PayrollRun> runs;

  const PayrollRunList({required this.runs});

  factory PayrollRunList.fromJson(Map<String, dynamic> json) => PayrollRunList(
        runs: asListOfMaps(json['runs'])
            .map(PayrollRun.fromJson)
            .toList(growable: false),
      );
}
