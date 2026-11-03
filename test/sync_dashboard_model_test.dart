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

  test(
      'labels latest sales and comparison dates by their actual business dates',
      () {
    final now = DateTime.utc(2026, 10, 2, 16); // 2026-10-03 01:00 KST
    expect(
      UiFormat.latestSalesLabel('2026-10-03', now: now),
      '오늘 매출',
    );
    expect(
      UiFormat.latestSalesLabel('2026-10-02', now: now),
      '최근 영업일 매출',
    );
    expect(
      UiFormat.previousBusinessDayLabel('2026-10-03', '2026-10-02'),
      '전일 대비',
    );
    expect(
      UiFormat.previousBusinessDayLabel('2026-10-03', '2026-09-30'),
      '직전 수집 영업일 대비',
    );
    expect(
      UiFormat.previousBusinessDayLabel('2026-10-03', null),
      '비교 데이터 없음',
    );
  });

  test('distinguishes an ungenerated owner report from zero-valued data', () {
    expect(OwnerBriefingResponse.fromJson({'report': null}).report, isNull);

    final response = OwnerBriefingResponse.fromJson({
      'report': {
        'title': '일일보고서',
        'structured': {
          'owner_report': {
            'business_date': '2026-10-02',
            'generated_at': '2026-10-03T00:30:00+09:00',
            'data_as_of': '2026-10-02T23:50:00+09:00',
            'status_label': '주의',
            'data_status_label': '일부 데이터 미수집',
            'data_status_reason': '일부 원본 수집이 지연되었습니다.',
            'briefing': '보고서 요약',
            'data_note': '데이터 품질 안내',
            'kpis': [
              {'label': '매출', 'display_value': '0원'},
            ],
            'actions': [
              {
                'priority': 1,
                'title': '수집 상태 확인',
                'reason': '원본 일부 미수집',
                'decision': '다음 단계 검토',
              },
            ],
          },
        },
      },
    });

    expect(response.report?.businessDate, '2026-10-02');
    expect(response.report?.kpis.single.displayValue, '0원');
    expect(response.report?.actions.single.title, '수집 상태 확인');
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

  test('parses sync run warnings and server business date', () {
    final data = SyncRunsData.fromJson({
      'today': '2026-11-03',
      'error': '',
      'runs': [
        {
          'target_date': '2026-11-02',
          'status': 'partial_failed',
          'source_count': 12,
          'loaded_count': 10,
          'warnings': ['2개 품목 누락', '  ', null],
          'started_at': '2026-11-03T01:00:00+09:00',
          'finished_at': '2026-11-03T01:02:00+09:00',
        },
      ],
    });

    expect(data.today, '2026-11-03');
    expect(data.runs.single.warnings, ['2개 품목 누락']);
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
