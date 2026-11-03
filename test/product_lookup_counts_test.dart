import 'package:cafe_bridge_flutter/screens/product_lookup.dart';
import 'package:cafe_bridge_flutter/services/cache_store.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _ProductLookupAppState extends AppState {
  _ProductLookupAppState(this.response);

  final Map<String, dynamic> response;
  Map<String, Object?>? requestParams;

  @override
  bool canAccess(UserRole requiredRole) => true;

  @override
  Future<CachedDataResult<T>> fetchMapParsed<T>(
    String endpoint, {
    Map<String, Object?>? params,
    required T Function(Map<String, dynamic> json) parser,
    Duration cacheTtl = const Duration(minutes: 30),
    bool allowStaleOnError = true,
    ApiCachePolicy? cachePolicy,
  }) async {
    if (endpoint != '/api/products/registration') {
      throw StateError('Unexpected endpoint: $endpoint');
    }
    requestParams = params;
    return CachedDataResult<T>(
      data: parser(response),
      fromCache: false,
      cachedAt: DateTime.now(),
    );
  }
}

Map<String, dynamic> _productResponse({required int rowCount}) => {
      'total_count': 3120,
      'filtered_count': 240,
      'limit': 100,
      'complete': true,
      'last_verified_at': '2026-11-03T01:00:00+09:00',
      'last_full_snapshot_at': '2026-11-02T22:00:00+09:00',
      'last_changed_at': '2026-11-02T19:30:00+09:00',
      'generation': 17,
      'source': 'postgres',
      'synced_at': '2026-11-03T01:05:00+09:00',
      'rows': List.generate(
        rowCount,
        (index) => {
          'product_code': 'code-$index',
          'item_name': '상품 $index',
        },
      ),
    };

void main() {
  test('parses product lookup count and snapshot freshness metadata', () {
    final data = ProductLookupData.fromJson(_productResponse(rowCount: 100));

    expect(data.rows, hasLength(100));
    expect(data.totalCount, 3120);
    expect(data.filteredCount, 240);
    expect(data.limit, 100);
    expect(data.complete, isTrue);
    expect(data.lastVerifiedAt, '2026-11-03T01:00:00+09:00');
    expect(data.lastFullSnapshotAt, '2026-11-02T22:00:00+09:00');
    expect(data.lastChangedAt, '2026-11-02T19:30:00+09:00');
    expect(data.generation, 17);
    expect(data.source, 'postgres');
    expect(data.syncedAt, '2026-11-03T01:05:00+09:00');
  });

  testWidgets('shows lookup counts, snapshot metadata, and truncation action',
      (tester) async {
    final state = _ProductLookupAppState(_productResponse(rowCount: 100));
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(body: ProductLookupScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('표시 100 / 검색 240 / 전체 3,120'), findsOneWidget);
    expect(find.text('전체 스냅샷 완료'), findsOneWidget);
    expect(find.text('generation 17'), findsOneWidget);
    expect(
        find.textContaining('최종 검증 2026-11-03T01:00:00+09:00'), findsOneWidget);
    expect(
      find.text('검색 결과 240개 중 100개만 표시 중입니다.'),
      findsOneWidget,
    );
    expect(find.text('페이지형 카탈로그로 전체 탐색'), findsOneWidget);
    expect(state.requestParams?['limit'], '100');
  });
}
