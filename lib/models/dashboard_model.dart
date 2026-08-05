import 'package:intl/intl.dart';

import 'api_contracts.dart';

class UiFormat {
  static final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'ko_KR',
    symbol: '',
    decimalDigits: 0,
  );
  static final NumberFormat _numberFormat =
      NumberFormat.decimalPattern('ko_KR');
  static final DateFormat _dateTimeFormat = DateFormat('MM-dd HH:mm');
  static const List<String> _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  static String won(num? amount) {
    return '${_currencyFormat.format(amount ?? 0)}원';
  }

  static String number(num? value) {
    return _numberFormat.format(value ?? 0);
  }

  static String weekday(String date) {
    final parsed = _strictDate(date);
    if (parsed == null) {
      return date;
    }
    return '$date (${_weekdays[parsed.weekday - 1]})';
  }

  static String delta(num? current, num? previous) {
    final currentValue = (current ?? 0).toDouble();
    final previousValue = (previous ?? 0).toDouble();
    if (previousValue == 0) {
      return '비교 불가';
    }

    final pct = ((currentValue / previousValue) - 1) * 100;
    final sign = pct >= 0 ? '▲' : '▼';
    return '$sign ${pct.abs().toStringAsFixed(1)}%';
  }

  static String compactDateTime(String? value) {
    if (value == null || value.isEmpty) {
      return '-';
    }

    final normalized = value.trim().replaceFirst(' ', 'T');
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) {
      return value;
    }
    if (!normalized.endsWith('Z') &&
        !RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(normalized)) {
      return _dateTimeFormat.format(parsed);
    }
    final kst = parsed.toUtc().add(const Duration(hours: 9));
    return _dateTimeFormat.format(DateTime(
      kst.year,
      kst.month,
      kst.day,
      kst.hour,
      kst.minute,
    ));
  }

  static DateTime? _strictDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed;
  }
}

class DashboardMetric {
  final String businessDate;
  final String shopNo;
  final int grossAmount;
  final int receiptCount;
  final int customerCount;
  final int cardAmount;
  final int cashAmount;

  const DashboardMetric({
    required this.businessDate,
    required this.shopNo,
    required this.grossAmount,
    required this.receiptCount,
    required this.customerCount,
    required this.cardAmount,
    required this.cashAmount,
  });

  factory DashboardMetric.fromJson(Map<String, dynamic> json) {
    return DashboardMetric(
      businessDate: asString(json['business_date']),
      shopNo: asString(json['shop_no']),
      grossAmount: asInt(json['gross_amount']),
      receiptCount: asInt(json['receipt_count']),
      customerCount: asInt(json['customer_count']),
      cardAmount: asInt(json['card_amount']),
      cashAmount: asInt(json['cash_amount']),
    );
  }
}

class SalesDaySummary {
  final String businessDate;
  final int grossAmount;
  final int pureSalesAmount;
  final int netAmount;
  final int vatAmount;
  final int discountAmount;
  final int receiptCount;
  final int customerCount;
  final int cardAmount;
  final int cashAmount;
  final int pointAmount;
  final int giftAmount;
  final int prepaidAmount;

  const SalesDaySummary({
    required this.businessDate,
    required this.grossAmount,
    required this.pureSalesAmount,
    required this.netAmount,
    required this.vatAmount,
    required this.discountAmount,
    required this.receiptCount,
    required this.customerCount,
    required this.cardAmount,
    required this.cashAmount,
    required this.pointAmount,
    required this.giftAmount,
    required this.prepaidAmount,
  });

  factory SalesDaySummary.fromJson(Map<String, dynamic> json) {
    return SalesDaySummary(
      businessDate: asString(json['business_date']),
      grossAmount: asInt(json['gross_amount']),
      pureSalesAmount: asInt(json['pure_sales_amount']),
      netAmount: asInt(json['net_amount']),
      vatAmount: asInt(json['vat_amount']),
      discountAmount: asInt(json['discount_amount']),
      receiptCount: asInt(json['receipt_count']),
      customerCount: asInt(json['customer_count']),
      cardAmount: asInt(json['card_amount']),
      cashAmount: asInt(json['cash_amount']),
      pointAmount: asInt(json['point_amount']),
      giftAmount: asInt(json['gift_amount']),
      prepaidAmount: asInt(json['prepaid_amount']),
    );
  }
}

class TopItemSummary {
  final String itemName;
  final String itemCode;
  final int totalQty;
  final int totalAmount;
  final int lineCount;
  final int totalDiscount;

  const TopItemSummary({
    required this.itemName,
    required this.itemCode,
    required this.totalQty,
    required this.totalAmount,
    required this.lineCount,
    this.totalDiscount = 0,
  });

  factory TopItemSummary.fromJson(Map<String, dynamic> json) {
    return TopItemSummary(
      itemName: asString(json['item_name']),
      itemCode: asString(json['item_code']),
      totalQty: asInt(json['total_qty']),
      totalAmount: asInt(json['total_amount']),
      lineCount: asInt(json['line_count']),
      totalDiscount: asInt(json['total_discount']),
    );
  }
}

class PaymentMixItem {
  final String method;
  final int amount;
  final double pct;

  const PaymentMixItem({
    required this.method,
    required this.amount,
    required this.pct,
  });

  factory PaymentMixItem.fromJson(Map<String, dynamic> json) {
    return PaymentMixItem(
      method: asString(json['method']),
      amount: asInt(json['amount']),
      pct: asDouble(json['pct']),
    );
  }
}

class TrendItem {
  final String itemName;
  final int currentAmount;
  final int previousAmount;
  final int delta;

  const TrendItem({
    required this.itemName,
    required this.currentAmount,
    required this.previousAmount,
    required this.delta,
  });

  factory TrendItem.fromJson(Map<String, dynamic> json) {
    return TrendItem(
      itemName: asString(json['item_name']),
      currentAmount: asInt(json['cur_amt']),
      previousAmount: asInt(json['prev_amt']),
      delta: asInt(json['delta']),
    );
  }
}

class SyncRun {
  final String targetDate;
  final String status;
  final int sourceCount;
  final int loadedCount;
  final String startedAt;
  final String finishedAt;

  const SyncRun({
    required this.targetDate,
    required this.status,
    required this.sourceCount,
    required this.loadedCount,
    required this.startedAt,
    required this.finishedAt,
  });

  factory SyncRun.fromJson(Map<String, dynamic> json) {
    return SyncRun(
      targetDate: asString(json['target_date']),
      status: asString(json['status']),
      sourceCount: asInt(json['source_count']),
      loadedCount: asInt(json['loaded_count']),
      startedAt: asString(json['started_at']),
      finishedAt: asString(json['finished_at']),
    );
  }
}

class DashboardSnapshot {
  final bool dbAvailable;
  final String error;
  final String? latestDay;
  final DashboardMetric latestMetrics;
  final List<SalesDaySummary> recentDays;
  final List<SyncRun> recentRuns;
  final List<TopItemSummary> topItems;
  final List<PaymentMixItem> paymentMix;
  final List<TrendItem> growers;
  final List<TrendItem> decliners;
  final int weekThis;
  final int weekPrev;
  final int avgTicket;
  final int prevAvgTicket;

  const DashboardSnapshot({
    required this.dbAvailable,
    required this.error,
    required this.latestDay,
    required this.latestMetrics,
    required this.recentDays,
    required this.recentRuns,
    required this.topItems,
    required this.paymentMix,
    required this.growers,
    required this.decliners,
    required this.weekThis,
    required this.weekPrev,
    required this.avgTicket,
    required this.prevAvgTicket,
  });

  factory DashboardSnapshot.fromJson(Map<String, dynamic> json) {
    return DashboardSnapshot(
      dbAvailable: json['db_available'] == true,
      error: asString(json['error']),
      latestDay: asNullableString(json['latest_day']),
      latestMetrics: DashboardMetric.fromJson(asMap(json['latest_metrics'])),
      recentDays: asListOfMaps(json['recent_days'])
          .map(SalesDaySummary.fromJson)
          .toList(growable: false),
      recentRuns: asListOfMaps(json['recent_runs'])
          .map(SyncRun.fromJson)
          .toList(growable: false),
      topItems: asListOfMaps(json['top_items'])
          .map(TopItemSummary.fromJson)
          .toList(growable: false),
      paymentMix: asListOfMaps(json['payment_mix'])
          .map(PaymentMixItem.fromJson)
          .toList(growable: false),
      growers: asListOfMaps(json['growers'])
          .map(TrendItem.fromJson)
          .toList(growable: false),
      decliners: asListOfMaps(json['decliners'])
          .map(TrendItem.fromJson)
          .toList(growable: false),
      weekThis: asInt(json['week_this']),
      weekPrev: asInt(json['week_prev']),
      avgTicket: asInt(json['avg_ticket']),
      prevAvgTicket: asInt(json['prev_avg_ticket']),
    );
  }
}

class DaySummary {
  final int grossAmount;
  final int pureSalesAmount;
  final int netAmount;
  final int vatAmount;
  final int discountAmount;
  final int receiptCount;
  final int customerCount;
  final int cashAmount;
  final int cardAmount;
  final int pointAmount;
  final int giftAmount;
  final int prepaidAmount;

  const DaySummary({
    required this.grossAmount,
    required this.pureSalesAmount,
    required this.netAmount,
    required this.vatAmount,
    required this.discountAmount,
    required this.receiptCount,
    required this.customerCount,
    required this.cashAmount,
    required this.cardAmount,
    required this.pointAmount,
    required this.giftAmount,
    required this.prepaidAmount,
  });

  factory DaySummary.fromJson(Map<String, dynamic> json) {
    return DaySummary(
      grossAmount: asInt(json['gross_amount']),
      pureSalesAmount: asInt(json['pure_sales_amount']),
      netAmount: asInt(json['net_amount']),
      vatAmount: asInt(json['vat_amount']),
      discountAmount: asInt(json['discount_amount']),
      receiptCount: asInt(json['receipt_count']),
      customerCount: asInt(json['customer_count']),
      cashAmount: asInt(json['cash_amount']),
      cardAmount: asInt(json['card_amount']),
      pointAmount: asInt(json['point_amount']),
      giftAmount: asInt(json['gift_amount']),
      prepaidAmount: asInt(json['prepaid_amount']),
    );
  }
}

class HourlySalesPoint {
  final String hour;
  final int billCount;
  final int totalAmount;
  final int totalCustomers;

  const HourlySalesPoint({
    required this.hour,
    required this.billCount,
    required this.totalAmount,
    required this.totalCustomers,
  });

  factory HourlySalesPoint.fromJson(Map<String, dynamic> json) {
    return HourlySalesPoint(
      hour: asString(json['hour']),
      billCount: asInt(json['bill_count']),
      totalAmount: asInt(json['total_amount']),
      totalCustomers: asInt(json['total_customers']),
    );
  }
}

class PosBreakdown {
  final String posNo;
  final int billCount;
  final int totalAmount;
  final int totalCustomers;

  const PosBreakdown({
    required this.posNo,
    required this.billCount,
    required this.totalAmount,
    required this.totalCustomers,
  });

  factory PosBreakdown.fromJson(Map<String, dynamic> json) {
    return PosBreakdown(
      posNo: asString(json['pos_no']),
      billCount: asInt(json['bill_count']),
      totalAmount: asInt(json['total_amount']),
      totalCustomers: asInt(json['total_customers']),
    );
  }
}

class BillRecord {
  final String posNo;
  final String billNo;
  final String payTime;
  final String saleFlag;
  final String saleType;
  final int grossAmount;
  final int pureSalesAmount;
  final int discountAmount;
  final int customerCount;
  final int itemCount;

  const BillRecord({
    required this.posNo,
    required this.billNo,
    required this.payTime,
    required this.saleFlag,
    required this.saleType,
    required this.grossAmount,
    required this.pureSalesAmount,
    required this.discountAmount,
    required this.customerCount,
    required this.itemCount,
  });

  String get formattedPayTime {
    final compact = RegExp(r'^(\d{2})(\d{2})$').firstMatch(payTime);
    if (compact == null) {
      return payTime;
    }
    final hour = int.parse(compact.group(1)!);
    final minute = int.parse(compact.group(2)!);
    if (hour > 23 || minute > 59) return payTime;
    return '${compact.group(1)}:${compact.group(2)}';
  }

  factory BillRecord.fromJson(Map<String, dynamic> json) {
    return BillRecord(
      posNo: asString(json['pos_no']),
      billNo: asString(json['bill_no']),
      payTime: asString(json['pay_time']),
      saleFlag: asString(json['sale_flag']),
      saleType: asString(json['sale_type']),
      grossAmount: asInt(json['gross_amount']),
      pureSalesAmount: asInt(json['pure_sales_amount']),
      discountAmount: asInt(json['discount_amount']),
      customerCount: asInt(json['customer_count']),
      itemCount: asInt(json['item_count']),
    );
  }
}

class DayDetailData {
  final String error;
  final String date;
  final DaySummary summary;
  final List<TopItemSummary> topItems;
  final List<PaymentMixItem> paymentMix;
  final List<HourlySalesPoint> hourlySales;
  final List<PosBreakdown> posBreakdown;
  final List<BillRecord> bills;
  final String? prevDate;
  final String? nextDate;

  const DayDetailData({
    required this.error,
    required this.date,
    required this.summary,
    required this.topItems,
    required this.paymentMix,
    required this.hourlySales,
    required this.posBreakdown,
    required this.bills,
    required this.prevDate,
    required this.nextDate,
  });

  factory DayDetailData.fromJson(Map<String, dynamic> json) {
    return DayDetailData(
      error: asString(json['error']),
      date: asString(json['date']),
      summary: DaySummary.fromJson(asMap(json['summary'])),
      topItems: asListOfMaps(json['top_items'])
          .map(TopItemSummary.fromJson)
          .toList(growable: false),
      paymentMix: asListOfMaps(json['payment_mix'])
          .map(PaymentMixItem.fromJson)
          .toList(growable: false),
      hourlySales: asListOfMaps(json['hourly_sales'])
          .map(HourlySalesPoint.fromJson)
          .toList(growable: false),
      posBreakdown: asListOfMaps(json['pos_breakdown'])
          .map(PosBreakdown.fromJson)
          .toList(growable: false),
      bills: asListOfMaps(json['bills'])
          .map(BillRecord.fromJson)
          .toList(growable: false),
      prevDate: asNullableString(json['prev_date']),
      nextDate: asNullableString(json['next_date']),
    );
  }
}

class SyncRunsData {
  final List<SyncRun> runs;
  final String today;
  final String error;

  const SyncRunsData({
    required this.runs,
    required this.today,
    required this.error,
  });

  factory SyncRunsData.fromJson(Map<String, dynamic> json) {
    return SyncRunsData(
      runs: asListOfMaps(json['runs'])
          .map(SyncRun.fromJson)
          .toList(growable: false),
      today: asString(json['today']),
      error: asString(json['error']),
    );
  }
}

class SyncTaskStatusData {
  final String taskId;
  final String targetDate;
  final String status;
  final String errorMessage;
  final int headerCount;
  final int itemCount;
  final int summaryCount;
  final int loadedCount;
  final String startedAt;
  final String finishedAt;
  final bool overdue;
  final String responseError;

  const SyncTaskStatusData({
    required this.taskId,
    required this.targetDate,
    required this.status,
    required this.errorMessage,
    required this.headerCount,
    required this.itemCount,
    required this.summaryCount,
    required this.loadedCount,
    required this.startedAt,
    required this.finishedAt,
    this.overdue = false,
    this.responseError = '',
  });

  bool get isRunning => status == 'pending' || status == 'running';
  bool get isFinished =>
      status == 'succeeded' || status == 'failed' || status == 'partial_failed';
  bool get isSuccessful => status == 'succeeded';

  factory SyncTaskStatusData.fromJson(Map<String, dynamic> json) {
    final task = asMap(json['task']);
    final responseError = asString(json['error']);
    return SyncTaskStatusData(
      taskId: asString(task['task_id']),
      targetDate: asString(task['target_date']),
      status: asString(task['status']),
      errorMessage: asString(task['error_message']),
      headerCount: asInt(task['header_count']),
      itemCount: asInt(task['item_count']),
      summaryCount: asInt(task['summary_count']),
      loadedCount: asInt(task['loaded_count']),
      startedAt: asString(task['started_at']),
      finishedAt: asString(task['finished_at']),
      overdue: task['overdue'] == true,
      responseError: responseError,
    );
  }
}

class SidebarDay {
  final String businessDate;
  final int grossAmount;

  const SidebarDay({
    required this.businessDate,
    required this.grossAmount,
  });

  factory SidebarDay.fromJson(Map<String, dynamic> json) {
    return SidebarDay(
      businessDate: asString(json['business_date']),
      grossAmount: asInt(json['gross_amount']),
    );
  }
}
