import 'package:cafe_bridge_flutter/models/dashboard_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats timezone-aware timestamps in KST', () {
    expect(UiFormat.compactDateTime('2026-07-24T00:30:00Z'), '07-24 09:30');
    expect(
      UiFormat.compactDateTime('2026-07-24T09:30:00+09:00'),
      '07-24 09:30',
    );
  });
  test('treats partial_failed as terminal and parses overdue', () {
    final task = SyncTaskStatusData.fromJson({
      'task': {
        'task_id': 'task-1',
        'status': 'partial_failed',
        'overdue': true,
        'loaded_count': '1,000',
      },
    });

    expect(task.isFinished, isTrue);
    expect(task.isSuccessful, isFalse);
    expect(task.overdue, isTrue);
    expect(task.loadedCount, 1000);
  });

  test('retains an error from a successful HTTP payload', () {
    final task = SyncTaskStatusData.fromJson({'error': '작업 조회 실패'});
    expect(task.responseError, '작업 조회 실패');
  });

  test('formats only valid dates and compact times', () {
    expect(UiFormat.weekday('2026-07-24'), '2026-07-24 (금)');
    expect(UiFormat.weekday('2026-02-30'), '2026-02-30');

    const valid = BillRecord(
      posNo: '',
      billNo: '',
      payTime: '2359',
      saleFlag: '',
      saleType: '',
      grossAmount: 0,
      pureSalesAmount: 0,
      discountAmount: 0,
      customerCount: 0,
      itemCount: 0,
    );
    const invalid = BillRecord(
      posNo: '',
      billNo: '',
      payTime: '2961',
      saleFlag: '',
      saleType: '',
      grossAmount: 0,
      pureSalesAmount: 0,
      discountAmount: 0,
      customerCount: 0,
      itemCount: 0,
    );
    expect(valid.formattedPayTime, '23:59');
    expect(invalid.formattedPayTime, '2961');
  });
}
