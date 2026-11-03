import 'package:cafe_bridge_flutter/screens/editor_product_catalog.dart';
import 'package:cafe_bridge_flutter/services/cache_store.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeAppState extends AppState {
  _FakeAppState(this.handler);

  final Map<String, dynamic> Function(
    String endpoint,
    Map<String, Object?>? params,
  ) handler;
  final List<({String endpoint, Map<String, Object?>? params})> requests = [];

  @override
  Future<CachedDataResult<T>> fetchMapParsed<T>(
    String endpoint, {
    Map<String, Object?>? params,
    required T Function(Map<String, dynamic> json) parser,
    Duration cacheTtl = const Duration(minutes: 30),
    bool allowStaleOnError = true,
    ApiCachePolicy? cachePolicy,
  }) async {
    requests.add((endpoint: endpoint, params: params));
    final data = handler(endpoint, params);
    return CachedDataResult<T>(
      data: parser(data),
      fromCache: false,
      cachedAt: DateTime.now(),
    );
  }
}

void main() {
  testWidgets('loads the next catalog page with its opaque cursor context',
      (tester) async {
    final productRequests = <Map<String, Object?>?>[];
    final state = _FakeAppState((endpoint, params) {
      if (endpoint == '/api/editor/context') {
        return {
          'scope_id': 'scope-a',
          'capabilities': {
            'browse_products': {'enabled': true, 'reason_code': 'ready'},
          },
        };
      }
      if (endpoint == '/api/editor/products') {
        productRequests.add(params);
        if (params?['cursor'] == null) {
          return {
            'scope_id': 'scope-a',
            'catalog_snapshot_id': 'snapshot-a',
            'source': 'postgres',
            'total_count': 51,
            'filtered_count': 51,
            'rows': [
              {'product_code': '1', 'item_name': '첫 상품', 'editor_price': 1000},
            ],
            'next_cursor': 'opaque-next',
            'has_more': true,
            'query_key': 'query-a',
            'generation': 6,
            'complete': true,
          };
        }
        return {
          'scope_id': 'scope-a',
          'catalog_snapshot_id': 'snapshot-a',
          'source': 'postgres',
          'total_count': 51,
          'filtered_count': 51,
          'rows': [
            {'product_code': '2', 'item_name': '두 번째 상품', 'editor_price': 2000},
          ],
          'next_cursor': null,
          'has_more': false,
          'query_key': 'query-a',
          'generation': 6,
          'complete': true,
        };
      }
      throw StateError('unexpected endpoint $endpoint');
    });
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: EditorProductCatalogScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('첫 상품'), findsOneWidget);
    expect(find.text('다음 50개 불러오기'), findsOneWidget);
    expect(productRequests, hasLength(1));
    expect(productRequests.first?['sort'], 'code_asc');
    expect(productRequests.first?['limit'], 50);

    await tester.ensureVisible(find.text('다음 50개 불러오기'));
    await tester.tap(find.text('다음 50개 불러오기'));
    await tester.pumpAndSettle();

    expect(find.text('두 번째 상품'), findsOneWidget);
    expect(productRequests, hasLength(2));
    expect(productRequests.last?['cursor'], 'opaque-next');
    expect(productRequests.last?['query_key'], 'query-a');
    expect(productRequests.last?['generation'], 6);
  });
}
