import 'package:cafe_bridge_flutter/models/analytics_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses comma-formatted analytics numbers consistently', () {
    expect(asInt('1,000'), 1000);
    expect(asDouble('1,000.5'), 1000.5);
  });

  test('parses every backend payment method', () {
    final data = PaymentAnalysisData.fromJson({
      'totals': {
        'gross': '10,000',
        'card': '1,000',
        'cash': '2,000',
        'point': '300',
        'gift': '400',
        'prepaid': '500',
        'receivable': '600',
        'exchange': '700',
        'staff_card': '800',
        'emoney': '900',
        'receipts': '10',
      },
      'days': [
        {
          'receivable_amount': '1,100',
          'exchange_amount': '1,200',
          'staff_card_amount': '1,300',
          'emoney_amount': '1,400',
        },
      ],
    });

    expect(data.totals.receivable, 600);
    expect(data.totals.exchange, 700);
    expect(data.totals.staffCard, 800);
    expect(data.totals.emoney, 900);
    expect(data.days.single.receivableAmount, 1100);
    expect(data.days.single.exchangeAmount, 1200);
    expect(data.days.single.staffCardAmount, 1300);
    expect(data.days.single.emoneyAmount, 1400);
  });

  test('uses forecast day predictions for forecast totals', () {
    final data = ForecastData.fromJson({
      'actual_total': '10,000',
      'forecast_remaining': 999999,
      'projected_total': 999999,
      'forecast_days': [
        {'predicted_date': '2026-07-25', 'predicted_total': '1,000'},
        {'predicted_date': '2026-07-26', 'predicted_total': 2500},
      ],
    });

    expect(data.forecastRemaining, 3500);
    expect(data.projectedTotal, 13500);
    expect(data.forecastDays.first.predictedTotal, 1000);
  });

  test('keeps optional hourly receipt count separate from bill count', () {
    final withReceipts = HourlyTotal.fromJson({
      'hour': '09',
      'bill_count': 12,
      'receipt_count': '10',
    });
    final withoutReceipts = HourlyTotal.fromJson({
      'hour': '10',
      'bill_count': 8,
    });

    expect(withReceipts.receiptCount, 10);
    expect(withoutReceipts.receiptCount, isNull);
  });

  test('rejects a reversed analytics date range', () {
    expect(
      () => validateAnalyticsDateRange(
        DateTime(2026, 7, 25),
        DateTime(2026, 7, 24),
      ),
      throwsArgumentError,
    );
  });

  test('keeps independently selected compare range dates', () {
    final data = CompareAnalysisData.fromJson({
      'a': {'from': '2026-10-01', 'to': '2026-10-07'},
      'b': {'from': '2026-08-12', 'to': '2026-08-14'},
      'deltas': {},
    });

    expect(data.current.from, '2026-10-01');
    expect(data.current.to, '2026-10-07');
    expect(data.previous.from, '2026-08-12');
    expect(data.previous.to, '2026-08-14');
  });
}
