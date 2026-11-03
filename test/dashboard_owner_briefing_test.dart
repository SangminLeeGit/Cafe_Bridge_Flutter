import 'package:cafe_bridge_flutter/services/api.dart';
import 'package:cafe_bridge_flutter/services/cache_store.dart';
import 'package:cafe_bridge_flutter/screens/dashboard.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _DashboardAppState extends AppState {
  _DashboardAppState({required this.ownerResponse});

  final Map<String, dynamic> ownerResponse;
  final List<String> endpoints = <String>[];
  final List<Map<String, Object?>?> paramsSeen = [];

  @override
  Future<CachedDataResult<T>> fetchMapParsed<T>(
    String endpoint, {
    Map<String, Object?>? params,
    required T Function(Map<String, dynamic> json) parser,
    Duration cacheTtl = const Duration(minutes: 30),
    bool allowStaleOnError = true,
    ApiCachePolicy? cachePolicy,
  }) async {
    endpoints.add(endpoint);
    paramsSeen.add(params);
    final response = switch (endpoint) {
      '/api/dashboard' => <String, dynamic>{
          'db_available': true,
          'latest_day': '2026-10-02',
          'latest_metrics': {
            'business_date': '2026-10-02',
            'gross_amount': 2500,
            'receipt_count': 1,
            'customer_count': 1,
            'card_amount': 2500,
            'cash_amount': 0,
          },
          'recent_days': [
            {
              'business_date': '2026-10-02',
              'gross_amount': 2500,
              'receipt_count': 1,
              'customer_count': 1,
            },
            {
              'business_date': '2026-09-30',
              'gross_amount': 2000,
              'receipt_count': 1,
              'customer_count': 1,
            },
          ],
          'recent_runs': <dynamic>[],
          'top_items': <dynamic>[],
          'payment_mix': <dynamic>[],
          'growers': <dynamic>[],
          'decliners': <dynamic>[],
          'week_this': 2500,
          'week_prev': 2000,
          'avg_ticket': 2500,
          'prev_avg_ticket': 2000,
        },
      '/api/daily-report' => ownerResponse,
      _ => throw ApiException('unexpected endpoint: $endpoint'),
    };
    return CachedDataResult<T>(
      data: parser(response),
      fromCache: false,
      cachedAt: DateTime.utc(2026, 10, 3),
    );
  }
}

Widget _testApp(_DashboardAppState appState) =>
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home distinguishes a missing report and requests the latest day',
      (tester) async {
    final appState = _DashboardAppState(ownerResponse: {'report': null});
    addTearDown(appState.dispose);
    await tester.pumpWidget(_testApp(appState));
    await tester.pumpAndSettle();

    expect(find.text('해당 영업일의 일일보고서가 아직 생성되지 않았습니다.'), findsOneWidget);
    expect(appState.endpoints, contains('/api/daily-report'));
    final ownerParams =
        appState.paramsSeen[appState.endpoints.indexOf('/api/daily-report')];
    expect(ownerParams, {'business_date': '2026-10-02'});
    expect(find.text('최근 영업일 매출'), findsOneWidget);
    expect(find.text('직전 수집 영업일 대비 ▲ 25.0%'), findsOneWidget);
  });

  testWidgets('home renders owner-safe report summary and actions',
      (tester) async {
    final appState = _DashboardAppState(ownerResponse: {
      'report': {
        'title': '일일보고서',
        'structured': {
          'owner_report': {
            'business_date': '2026-10-02',
            'generated_at': '2026-10-03T00:30:00+09:00',
            'data_as_of': '2026-10-02T23:50:00+09:00',
            'status_label': '확인 필요',
            'data_status_label': '일부 수집 지연',
            'data_status_reason': '수집 상태를 확인하세요.',
            'briefing': '오늘의 운영 요약입니다.',
            'data_note': '원본 기준 시각을 확인하세요.',
            'kpis': [
              {'label': '매출', 'display_value': '25,000원'},
            ],
            'actions': [
              {
                'priority': 1,
                'title': '수집 상태 확인',
                'reason': 'POS 데이터 일부 지연',
                'decision': '다음 갱신을 확인합니다.',
              },
            ],
          },
        },
      },
    });
    addTearDown(appState.dispose);
    await tester.pumpWidget(_testApp(appState));
    await tester.pumpAndSettle();

    expect(find.text('오늘의 운영 요약입니다.'), findsOneWidget);
    expect(find.text('수집 상태 확인'), findsOneWidget);
    expect(find.textContaining('원본 데이터 기준'), findsOneWidget);
    expect(appState.endpoints,
        isNot(contains('/api/admin/daily-reports/settings')));
  });
}
