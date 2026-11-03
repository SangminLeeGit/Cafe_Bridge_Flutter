import 'package:cafe_bridge_flutter/models/editor_product_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('editor product catalog contract', () {
    test('builds stable first and continuation request parameters', () {
      expect(editorProductFirstPageParams('  coffee  '), {
        'query': 'coffee',
        'limit': 50,
        'sort': 'code_asc',
      });
      expect(
        editorProductNextPageParams(
          query: 'coffee',
          cursor: 'opaque',
          queryKey: 'query-v1',
          generation: 12,
        ),
        {
          'query': 'coffee',
          'limit': 50,
          'sort': 'code_asc',
          'cursor': 'opaque',
          'generation': 12,
          'query_key': 'query-v1',
        },
      );
    });

    test('parses a cursor page and normalizes editor product identity', () {
      final page = EditorProductCatalogPage.fromJson({
        'scope_id': 'scope-a',
        'catalog_snapshot_id': 'catalog-v2',
        'source': 'postgres',
        'synced_at': '2026-10-03T10:00:00Z',
        'total_count': 81,
        'filtered_count': 51,
        'rows': [
          {
            'product_code': '42',
            'item_name': '아메리카노',
            'major_category': '음료',
            'middle_category': '커피',
            'editor_price': 4500,
            'editor_meta': {
              'placeable': true,
              'placeable_reason': 'ready',
            },
          },
        ],
        'next_cursor': 'opaque-cursor',
        'has_more': true,
        'query_key': 'stable-query',
        'generation': 7,
        'complete': true,
      });

      expect(page.rows, hasLength(1));
      expect(page.rows.single.code, '000042');
      expect(page.rows.single.name, '아메리카노');
      expect(page.rows.single.price, 4500);
      expect(page.rows.single.category, '음료 > 커피');
      expect(page.rows.single.placeable, isTrue);
      expect(page.nextCursor, 'opaque-cursor');
      expect(page.queryKey, 'stable-query');
      expect(page.generation, 7);
      expect(page.filteredCount, 51);
    });

    test('rejects inconsistent continuation metadata', () {
      expect(
        () => EditorProductCatalogPage.fromJson({
          'rows': [],
          'next_cursor': 'cursor',
          'has_more': false,
          'query_key': 'stable-query',
          'generation': 1,
        }),
        throwsFormatException,
      );
    });

    test('requires a query key and generation before a page can be continued',
        () {
      expect(
        () => EditorProductCatalogPage.fromJson({
          'rows': [],
          'next_cursor': null,
          'has_more': false,
          'query_key': '',
          'generation': 1,
        }),
        throwsFormatException,
      );
    });
  });
}
