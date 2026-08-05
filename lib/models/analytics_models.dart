class MonthlyDayRecord {
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

  const MonthlyDayRecord({
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

  factory MonthlyDayRecord.fromJson(Map<String, dynamic> json) {
    return MonthlyDayRecord(
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

void validateAnalyticsDateRange(DateTime from, DateTime to) {
  if (from.isAfter(to)) {
    throw ArgumentError('시작일은 종료일보다 늦을 수 없습니다.');
  }
}

class MonthlyTotals {
  final int gross;
  final int pureSales;
  final int net;
  final int vat;
  final int discount;
  final int receipts;
  final int customers;
  final int card;
  final int cash;
  final int avgTicket;

  const MonthlyTotals({
    required this.gross,
    required this.pureSales,
    required this.net,
    required this.vat,
    required this.discount,
    required this.receipts,
    required this.customers,
    required this.card,
    required this.cash,
    required this.avgTicket,
  });

  factory MonthlyTotals.fromJson(Map<String, dynamic> json) {
    return MonthlyTotals(
      gross: asInt(json['gross']),
      pureSales: asInt(json['pure_sales']),
      net: asInt(json['net']),
      vat: asInt(json['vat']),
      discount: asInt(json['discount']),
      receipts: asInt(json['receipts']),
      customers: asInt(json['customers']),
      card: asInt(json['card']),
      cash: asInt(json['cash']),
      avgTicket: asInt(json['avg_ticket']),
    );
  }
}

class AnalyticsTopItem {
  final String itemName;
  final String itemCode;
  final int totalQty;
  final int totalAmount;
  final int lineCount;
  final int totalDiscount;
  final int daysSold;
  final double pct;
  final String abc;

  const AnalyticsTopItem({
    required this.itemName,
    required this.itemCode,
    required this.totalQty,
    required this.totalAmount,
    required this.lineCount,
    this.totalDiscount = 0,
    this.daysSold = 0,
    this.pct = 0,
    this.abc = '',
  });

  factory AnalyticsTopItem.fromJson(Map<String, dynamic> json) {
    return AnalyticsTopItem(
      itemName: asString(json['item_name']),
      itemCode: asString(json['item_code']),
      totalQty: asInt(json['total_qty']),
      totalAmount: asInt(json['total_amount']),
      lineCount: asInt(json['line_count']),
      totalDiscount: asInt(json['total_discount']),
      daysSold: asInt(json['days_sold']),
      pct: asDouble(json['pct']),
      abc: asString(json['abc']),
    );
  }
}

class MonthlyReportData {
  final String error;
  final int year;
  final int month;
  final List<MonthlyDayRecord> days;
  final MonthlyTotals totals;
  final List<AnalyticsTopItem> topItems;

  const MonthlyReportData({
    required this.error,
    required this.year,
    required this.month,
    required this.days,
    required this.totals,
    required this.topItems,
  });

  factory MonthlyReportData.fromJson(Map<String, dynamic> json) {
    return MonthlyReportData(
      error: asString(json['error']),
      year: asInt(json['year']),
      month: asInt(json['month']),
      days: asListOfMaps(json['days'])
          .map(MonthlyDayRecord.fromJson)
          .toList(growable: false),
      totals: MonthlyTotals.fromJson(asMap(json['totals'])),
      topItems: asListOfMaps(json['top_items'])
          .map(AnalyticsTopItem.fromJson)
          .toList(growable: false),
    );
  }
}

class ItemAnalysisData {
  final String error;
  final String fromDate;
  final String toDate;
  final List<AnalyticsTopItem> itemList;
  final int grandTotal;

  const ItemAnalysisData({
    required this.error,
    required this.fromDate,
    required this.toDate,
    required this.itemList,
    required this.grandTotal,
  });

  factory ItemAnalysisData.fromJson(Map<String, dynamic> json) {
    return ItemAnalysisData(
      error: asString(json['error']),
      fromDate: asString(json['from_date']),
      toDate: asString(json['to_date']),
      itemList: asListOfMaps(json['item_list'])
          .map(AnalyticsTopItem.fromJson)
          .toList(growable: false),
      grandTotal: asInt(json['grand_total']),
    );
  }
}

class HourlyHeatmapCell {
  final int dow;
  final String hour;
  final int billCount;
  final int totalAmount;
  final int totalCustomers;
  final int? receiptCount;

  const HourlyHeatmapCell({
    required this.dow,
    required this.hour,
    required this.billCount,
    required this.totalAmount,
    required this.totalCustomers,
    this.receiptCount,
  });

  factory HourlyHeatmapCell.fromJson(Map<String, dynamic> json) {
    return HourlyHeatmapCell(
      dow: asInt(json['dow']),
      hour: asString(json['hour']),
      billCount: asInt(json['bill_count']),
      totalAmount: asInt(json['total_amount']),
      totalCustomers: asInt(json['total_customers']),
      receiptCount: json.containsKey('receipt_count')
          ? asInt(json['receipt_count'])
          : null,
    );
  }
}

class HourlyTotal {
  final String hour;
  final int billCount;
  final int totalAmount;
  final int totalCustomers;
  final int? receiptCount;

  const HourlyTotal({
    required this.hour,
    required this.billCount,
    required this.totalAmount,
    required this.totalCustomers,
    this.receiptCount,
  });

  factory HourlyTotal.fromJson(Map<String, dynamic> json) {
    return HourlyTotal(
      hour: asString(json['hour']),
      billCount: asInt(json['bill_count']),
      totalAmount: asInt(json['total_amount']),
      totalCustomers: asInt(json['total_customers']),
      receiptCount: json.containsKey('receipt_count')
          ? asInt(json['receipt_count'])
          : null,
    );
  }
}

class HourlyAnalysisData {
  final String error;
  final String fromDate;
  final String toDate;
  final List<HourlyHeatmapCell> heatmap;
  final List<HourlyTotal> hourlyTotals;
  final int avgAmount;
  final int stdAmount;

  const HourlyAnalysisData({
    required this.error,
    required this.fromDate,
    required this.toDate,
    required this.heatmap,
    required this.hourlyTotals,
    required this.avgAmount,
    required this.stdAmount,
  });

  factory HourlyAnalysisData.fromJson(Map<String, dynamic> json) {
    return HourlyAnalysisData(
      error: asString(json['error']),
      fromDate: asString(json['from_date']),
      toDate: asString(json['to_date']),
      heatmap: asListOfMaps(json['heatmap'])
          .map(HourlyHeatmapCell.fromJson)
          .toList(growable: false),
      hourlyTotals: asListOfMaps(json['hourly_totals'])
          .map(HourlyTotal.fromJson)
          .toList(growable: false),
      avgAmount: asInt(json['avg_amount']),
      stdAmount: asInt(json['std_amount']),
    );
  }
}

class WeekdayAnalysisRow {
  final int dow;
  final String name;
  final int dayCount;
  final int totalAmount;
  final int avgAmount;
  final int totalReceipts;
  final int avgReceipts;
  final int totalCustomers;
  final int avgCustomers;
  final int avgTicket;

  const WeekdayAnalysisRow({
    required this.dow,
    required this.name,
    required this.dayCount,
    required this.totalAmount,
    required this.avgAmount,
    required this.totalReceipts,
    required this.avgReceipts,
    required this.totalCustomers,
    required this.avgCustomers,
    required this.avgTicket,
  });

  factory WeekdayAnalysisRow.fromJson(Map<String, dynamic> json) {
    return WeekdayAnalysisRow(
      dow: asInt(json['dow']),
      name: asString(json['name']),
      dayCount: asInt(json['day_count']),
      totalAmount: asInt(json['total_amount']),
      avgAmount: asInt(json['avg_amount']),
      totalReceipts: asInt(json['total_receipts']),
      avgReceipts: asInt(json['avg_receipts']),
      totalCustomers: asInt(json['total_customers']),
      avgCustomers: asInt(json['avg_customers']),
      avgTicket: asInt(json['avg_ticket']),
    );
  }
}

class WeekdayAnalysisData {
  final String error;
  final String fromDate;
  final String toDate;
  final List<WeekdayAnalysisRow> rows;
  final int weekdayAvg;
  final int weekendAvg;

  const WeekdayAnalysisData({
    required this.error,
    required this.fromDate,
    required this.toDate,
    required this.rows,
    required this.weekdayAvg,
    required this.weekendAvg,
  });

  factory WeekdayAnalysisData.fromJson(Map<String, dynamic> json) {
    return WeekdayAnalysisData(
      error: asString(json['error']),
      fromDate: asString(json['from_date']),
      toDate: asString(json['to_date']),
      rows: asListOfMaps(json['rows'])
          .map(WeekdayAnalysisRow.fromJson)
          .toList(growable: false),
      weekdayAvg: asInt(json['weekday_avg']),
      weekendAvg: asInt(json['weekend_avg']),
    );
  }
}

class PaymentDayRecord {
  final String businessDate;
  final int grossAmount;
  final int cardAmount;
  final int cashAmount;
  final int pointAmount;
  final int giftAmount;
  final int prepaidAmount;
  final int receivableAmount;
  final int exchangeAmount;
  final int staffCardAmount;
  final int emoneyAmount;
  final int receiptCount;
  final int customerCount;

  const PaymentDayRecord({
    required this.businessDate,
    required this.grossAmount,
    required this.cardAmount,
    required this.cashAmount,
    required this.pointAmount,
    required this.giftAmount,
    required this.prepaidAmount,
    required this.receivableAmount,
    required this.exchangeAmount,
    required this.staffCardAmount,
    required this.emoneyAmount,
    required this.receiptCount,
    required this.customerCount,
  });

  factory PaymentDayRecord.fromJson(Map<String, dynamic> json) {
    return PaymentDayRecord(
      businessDate: asString(json['business_date']),
      grossAmount: asInt(json['gross_amount']),
      cardAmount: asInt(json['card_amount']),
      cashAmount: asInt(json['cash_amount']),
      pointAmount: asInt(json['point_amount']),
      giftAmount: asInt(json['gift_amount']),
      prepaidAmount: asInt(json['prepaid_amount']),
      receivableAmount: asInt(json['receivable_amount']),
      exchangeAmount: asInt(json['exchange_amount']),
      staffCardAmount: asInt(json['staff_card_amount']),
      emoneyAmount: asInt(json['emoney_amount']),
      receiptCount: asInt(json['receipt_count']),
      customerCount: asInt(json['customer_count']),
    );
  }
}

class PaymentTotals {
  final int gross;
  final int card;
  final int cash;
  final int point;
  final int gift;
  final int prepaid;
  final int receivable;
  final int exchange;
  final int staffCard;
  final int emoney;
  final int receipts;

  const PaymentTotals({
    required this.gross,
    required this.card,
    required this.cash,
    required this.point,
    required this.gift,
    required this.prepaid,
    required this.receivable,
    required this.exchange,
    required this.staffCard,
    required this.emoney,
    required this.receipts,
  });

  factory PaymentTotals.fromJson(Map<String, dynamic> json) {
    return PaymentTotals(
      gross: asInt(json['gross']),
      card: asInt(json['card']),
      cash: asInt(json['cash']),
      point: asInt(json['point']),
      gift: asInt(json['gift']),
      prepaid: asInt(json['prepaid']),
      receivable: asInt(json['receivable']),
      exchange: asInt(json['exchange']),
      staffCard: asInt(json['staff_card']),
      emoney: asInt(json['emoney']),
      receipts: asInt(json['receipts']),
    );
  }
}

class MethodTicket {
  final String method;
  final int count;
  final int avgTicket;

  const MethodTicket({
    required this.method,
    required this.count,
    required this.avgTicket,
  });

  factory MethodTicket.fromJson(Map<String, dynamic> json) {
    return MethodTicket(
      method: asString(json['method']),
      count: asInt(json['cnt']),
      avgTicket: asInt(json['avg_ticket']),
    );
  }
}

class PaymentAnalysisData {
  final String error;
  final String fromDate;
  final String toDate;
  final List<PaymentDayRecord> days;
  final PaymentTotals totals;
  final List<MethodTicket> methodTickets;

  const PaymentAnalysisData({
    required this.error,
    required this.fromDate,
    required this.toDate,
    required this.days,
    required this.totals,
    required this.methodTickets,
  });

  factory PaymentAnalysisData.fromJson(Map<String, dynamic> json) {
    return PaymentAnalysisData(
      error: asString(json['error']),
      fromDate: asString(json['from_date']),
      toDate: asString(json['to_date']),
      days: asListOfMaps(json['days'])
          .map(PaymentDayRecord.fromJson)
          .toList(growable: false),
      totals: PaymentTotals.fromJson(asMap(json['totals'])),
      methodTickets: asListOfMaps(json['method_tickets'])
          .map(MethodTicket.fromJson)
          .toList(growable: false),
    );
  }
}

class CompareRangeStats {
  final String from;
  final String to;
  final List<MonthlyDayRecord> days;
  final int gross;
  final int receipts;
  final int customers;
  final int avgTicket;
  final List<AnalyticsTopItem> topItems;

  const CompareRangeStats({
    required this.from,
    required this.to,
    required this.days,
    required this.gross,
    required this.receipts,
    required this.customers,
    required this.avgTicket,
    required this.topItems,
  });

  factory CompareRangeStats.fromJson(Map<String, dynamic> json) {
    return CompareRangeStats(
      from: asString(json['from']),
      to: asString(json['to']),
      days: asListOfMaps(json['days'])
          .map(MonthlyDayRecord.fromJson)
          .toList(growable: false),
      gross: asInt(json['gross']),
      receipts: asInt(json['receipts']),
      customers: asInt(json['customers']),
      avgTicket: asInt(json['avg_ticket']),
      topItems: asListOfMaps(json['top_items'])
          .map(AnalyticsTopItem.fromJson)
          .toList(growable: false),
    );
  }
}

class CompareDeltas {
  final double gross;
  final double receipts;
  final double customers;
  final double avgTicket;

  const CompareDeltas({
    required this.gross,
    required this.receipts,
    required this.customers,
    required this.avgTicket,
  });

  factory CompareDeltas.fromJson(Map<String, dynamic> json) {
    return CompareDeltas(
      gross: asDouble(json['gross']),
      receipts: asDouble(json['receipts']),
      customers: asDouble(json['customers']),
      avgTicket: asDouble(json['avg_ticket']),
    );
  }
}

class CompareAnalysisData {
  final String error;
  final CompareRangeStats current;
  final CompareRangeStats previous;
  final CompareDeltas deltas;

  const CompareAnalysisData({
    required this.error,
    required this.current,
    required this.previous,
    required this.deltas,
  });

  factory CompareAnalysisData.fromJson(Map<String, dynamic> json) {
    return CompareAnalysisData(
      error: asString(json['error']),
      current: CompareRangeStats.fromJson(asMap(json['a'])),
      previous: CompareRangeStats.fromJson(asMap(json['b'])),
      deltas: CompareDeltas.fromJson(asMap(json['deltas'])),
    );
  }
}

class TrendDayRecord {
  final String businessDate;
  final int grossAmount;
  final int receiptCount;
  final int customerCount;
  final int discountAmount;
  final int avgTicket;
  final int perCustomer;

  const TrendDayRecord({
    required this.businessDate,
    required this.grossAmount,
    required this.receiptCount,
    required this.customerCount,
    required this.discountAmount,
    required this.avgTicket,
    required this.perCustomer,
  });

  factory TrendDayRecord.fromJson(Map<String, dynamic> json) {
    return TrendDayRecord(
      businessDate: asString(json['business_date']),
      grossAmount: asInt(json['gross_amount']),
      receiptCount: asInt(json['receipt_count']),
      customerCount: asInt(json['customer_count']),
      discountAmount: asInt(json['discount_amount']),
      avgTicket: asInt(json['avg_ticket']),
      perCustomer: asInt(json['per_customer']),
    );
  }
}

class MovingAveragePoint {
  final String businessDate;
  final int ma28;

  const MovingAveragePoint({
    required this.businessDate,
    required this.ma28,
  });

  factory MovingAveragePoint.fromJson(Map<String, dynamic> json) {
    return MovingAveragePoint(
      businessDate: asString(json['business_date']),
      ma28: asInt(json['ma28']),
    );
  }
}

class TrendsSummary {
  final int totalGross;
  final int totalReceipts;
  final int totalCustomers;
  final int avgTicket;
  final int perCustomer;
  final int dayCount;

  const TrendsSummary({
    required this.totalGross,
    required this.totalReceipts,
    required this.totalCustomers,
    required this.avgTicket,
    required this.perCustomer,
    required this.dayCount,
  });

  factory TrendsSummary.fromJson(Map<String, dynamic> json) {
    return TrendsSummary(
      totalGross: asInt(json['total_gross']),
      totalReceipts: asInt(json['total_receipts']),
      totalCustomers: asInt(json['total_customers']),
      avgTicket: asInt(json['avg_ticket']),
      perCustomer: asInt(json['per_customer']),
      dayCount: asInt(json['day_count']),
    );
  }
}

class TrendsAnalysisData {
  final String error;
  final String fromDate;
  final String toDate;
  final List<TrendDayRecord> days;
  final List<MovingAveragePoint> maSeries;
  final int forecastAvg;
  final TrendsSummary summary;

  const TrendsAnalysisData({
    required this.error,
    required this.fromDate,
    required this.toDate,
    required this.days,
    required this.maSeries,
    required this.forecastAvg,
    required this.summary,
  });

  factory TrendsAnalysisData.fromJson(Map<String, dynamic> json) {
    return TrendsAnalysisData(
      error: asString(json['error']),
      fromDate: asString(json['from_date']),
      toDate: asString(json['to_date']),
      days: asListOfMaps(json['days'])
          .map(TrendDayRecord.fromJson)
          .toList(growable: false),
      maSeries: asListOfMaps(json['ma_series'])
          .map(MovingAveragePoint.fromJson)
          .toList(growable: false),
      forecastAvg: asInt(json['forecast_avg']),
      summary: TrendsSummary.fromJson(asMap(json['summary'])),
    );
  }
}

List<Map<String, dynamic>> asListOfMaps(Object? source) {
  if (source is! List) {
    return const [];
  }

  return source
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

Map<String, dynamic> asMap(Object? source) {
  if (source is Map) {
    return Map<String, dynamic>.from(source);
  }
  return const {};
}

String asString(Object? value) {
  return value?.toString() ?? '';
}

int asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value.replaceAll(',', '')) ?? 0;
  }
  return 0;
}

double asDouble(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is int) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.replaceAll(',', '')) ?? 0;
  }
  return 0;
}

// ─── Menu Engineering ─────────────────────────────────────────────────────────

class MenuEngineeringItem {
  final String itemName;
  final String itemCode;
  final int totalQty;
  final int totalAmount;
  final int totalDiscount;
  final int daysSold;
  final int lineCount;
  final int avgPrice;
  final String quadrant;
  final String label;

  const MenuEngineeringItem({
    required this.itemName,
    required this.itemCode,
    required this.totalQty,
    required this.totalAmount,
    required this.totalDiscount,
    required this.daysSold,
    required this.lineCount,
    required this.avgPrice,
    required this.quadrant,
    required this.label,
  });

  factory MenuEngineeringItem.fromJson(Map<String, dynamic> json) {
    return MenuEngineeringItem(
      itemName: asString(json['item_name']),
      itemCode: asString(json['item_code']),
      totalQty: asInt(json['total_qty']),
      totalAmount: asInt(json['total_amount']),
      totalDiscount: asInt(json['total_discount']),
      daysSold: asInt(json['days_sold']),
      lineCount: asInt(json['line_count']),
      avgPrice: asInt(json['avg_price']),
      quadrant: asString(json['quadrant']),
      label: asString(json['label']),
    );
  }
}

class MenuEngineeringData {
  final String error;
  final String fromDate;
  final String toDate;
  final List<MenuEngineeringItem> menuItems;
  final int avgQty;
  final int avgPrice;
  final Map<String, int> quadrantCounts;

  const MenuEngineeringData({
    required this.error,
    required this.fromDate,
    required this.toDate,
    required this.menuItems,
    required this.avgQty,
    required this.avgPrice,
    required this.quadrantCounts,
  });

  factory MenuEngineeringData.fromJson(Map<String, dynamic> json) {
    final rawCounts = json['quadrant_counts'];
    final counts = <String, int>{};
    if (rawCounts is Map) {
      rawCounts.forEach((k, v) {
        counts[k.toString()] = asInt(v);
      });
    }
    return MenuEngineeringData(
      error: asString(json['error']),
      fromDate: asString(json['from_date']),
      toDate: asString(json['to_date']),
      menuItems: asListOfMaps(json['menu_items'])
          .map(MenuEngineeringItem.fromJson)
          .toList(growable: false),
      avgQty: asInt(json['avg_qty']),
      avgPrice: asInt(json['avg_price']),
      quadrantCounts: counts,
    );
  }
}

// ─── Forecast ─────────────────────────────────────────────────────────────────

class ForecastDayRecord {
  final String businessDate;
  final int grossAmount;
  final int receiptCount;
  final int customerCount;

  const ForecastDayRecord({
    required this.businessDate,
    required this.grossAmount,
    required this.receiptCount,
    required this.customerCount,
  });

  factory ForecastDayRecord.fromJson(Map<String, dynamic> json) {
    return ForecastDayRecord(
      businessDate: asString(json['business_date']),
      grossAmount: asInt(json['gross_amount']),
      receiptCount: asInt(json['receipt_count']),
      customerCount: asInt(json['customer_count']),
    );
  }
}

class ForecastPrediction {
  final String predictedDate;
  final int predictedTotal;

  const ForecastPrediction({
    required this.predictedDate,
    required this.predictedTotal,
  });

  factory ForecastPrediction.fromJson(Map<String, dynamic> json) {
    return ForecastPrediction(
      predictedDate: asString(json['predicted_date']),
      predictedTotal: asInt(json['predicted_total']),
    );
  }
}

class ForecastData {
  final String error;
  final int year;
  final int month;
  final List<ForecastDayRecord> days;
  final List<ForecastPrediction> forecastDays;
  final int daysInMonth;
  final int actualTotal;
  final int actualDays;
  final int remainingDays;
  final int forecastRemaining;
  final int projectedTotal;
  final int dailyAvg;
  final double progressPct;

  const ForecastData({
    required this.error,
    required this.year,
    required this.month,
    required this.days,
    required this.forecastDays,
    required this.daysInMonth,
    required this.actualTotal,
    required this.actualDays,
    required this.remainingDays,
    required this.forecastRemaining,
    required this.projectedTotal,
    required this.dailyAvg,
    required this.progressPct,
  });

  factory ForecastData.fromJson(Map<String, dynamic> json) {
    final forecastDays = asListOfMaps(json['forecast_days'])
        .map(ForecastPrediction.fromJson)
        .toList(growable: false);
    final forecastRemaining = forecastDays.fold<int>(
      0,
      (sum, day) => sum + day.predictedTotal,
    );
    final actualTotal = asInt(json['actual_total']);
    return ForecastData(
      error: asString(json['error']),
      year: asInt(json['year']),
      month: asInt(json['month']),
      days: asListOfMaps(json['days'])
          .map(ForecastDayRecord.fromJson)
          .toList(growable: false),
      forecastDays: forecastDays,
      daysInMonth: asInt(json['days_in_month']),
      actualTotal: actualTotal,
      actualDays: asInt(json['actual_days']),
      remainingDays: asInt(json['remaining_days']),
      forecastRemaining: forecastRemaining,
      projectedTotal: actualTotal + forecastRemaining,
      dailyAvg: asInt(json['daily_avg']),
      progressPct: asDouble(json['progress_pct']),
    );
  }
}

// ─── ABC Analysis ─────────────────────────────────────────────────────────────

class AbcItem {
  final String itemName;
  final int totalQty;
  final int totalAmount;
  final double pct;
  final double cumPct;
  final String grade;

  const AbcItem({
    required this.itemName,
    required this.totalQty,
    required this.totalAmount,
    required this.pct,
    required this.cumPct,
    required this.grade,
  });

  factory AbcItem.fromJson(Map<String, dynamic> json) {
    return AbcItem(
      itemName: asString(json['item_name']),
      totalQty: asInt(json['total_qty']),
      totalAmount: asInt(json['total_amount']),
      pct: asDouble(json['pct']),
      cumPct: asDouble(json['cum_pct']),
      grade: asString(json['grade']),
    );
  }
}

class AbcData {
  final String error;
  final List<AbcItem> items;
  final Map<String, int> counts;
  final int grandTotal;

  const AbcData({
    required this.error,
    required this.items,
    required this.counts,
    required this.grandTotal,
  });

  factory AbcData.fromJson(Map<String, dynamic> json) {
    final rawCounts = json['counts'];
    final counts = <String, int>{};
    if (rawCounts is Map) {
      rawCounts.forEach((k, v) {
        counts[k.toString()] = asInt(v);
      });
    }
    return AbcData(
      error: asString(json['error']),
      items: asListOfMaps(json['items'])
          .map(AbcItem.fromJson)
          .toList(growable: false),
      counts: counts,
      grandTotal: asInt(json['grand_total']),
    );
  }
}
