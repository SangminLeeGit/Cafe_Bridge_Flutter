import 'api_contracts.dart';
import 'product_identity.dart';

const int editorProductCatalogPageSize = 50;

Map<String, Object?> editorProductFirstPageParams(String query) => {
      'query': query.trim(),
      'limit': editorProductCatalogPageSize,
      'sort': 'code_asc',
    };

Map<String, Object?> editorProductNextPageParams({
  required String query,
  required String cursor,
  required String queryKey,
  required int generation,
}) =>
    {
      'query': query.trim(),
      'limit': editorProductCatalogPageSize,
      'sort': 'code_asc',
      'cursor': cursor,
      'generation': generation,
      'query_key': queryKey,
    };

/// A read-only product row returned by the server-backed editor catalog.
class EditorCatalogProduct {
  final Map<String, dynamic> raw;
  final String code;
  final String name;
  final int? price;
  final String category;
  final bool placeable;
  final String placeableReason;

  const EditorCatalogProduct({
    required this.raw,
    required this.code,
    required this.name,
    required this.price,
    required this.category,
    required this.placeable,
    required this.placeableReason,
  });

  factory EditorCatalogProduct.fromJson(Map<String, dynamic> json) {
    final identity = ProductIdentity.fromRegistrationJson(
      json,
      priceFields: const ['editor_price'],
    );
    final meta = asMap(json['editor_meta']);
    return EditorCatalogProduct(
      raw: Map<String, dynamic>.unmodifiable(json),
      code: identity.code,
      name: identity.name,
      price: identity.salePrice,
      category: identity.category,
      placeable: asBool(meta['placeable']),
      placeableReason: asString(meta['placeable_reason']),
    );
  }
}

/// One stable-generation page from `/api/editor/products`.
class EditorProductCatalogPage {
  final String scopeId;
  final String? catalogSnapshotId;
  final String source;
  final String? syncedAt;
  final int totalCount;
  final int filteredCount;
  final List<EditorCatalogProduct> rows;
  final String? nextCursor;
  final bool hasMore;
  final String queryKey;
  final int generation;
  final bool complete;

  const EditorProductCatalogPage({
    required this.scopeId,
    required this.catalogSnapshotId,
    required this.source,
    required this.syncedAt,
    required this.totalCount,
    required this.filteredCount,
    required this.rows,
    required this.nextCursor,
    required this.hasMore,
    required this.queryKey,
    required this.generation,
    required this.complete,
  });

  factory EditorProductCatalogPage.fromJson(Map<String, dynamic> json) {
    final rows = requireListOfMaps(json, 'rows')
        .map(EditorCatalogProduct.fromJson)
        .toList(growable: false);
    final cursor = asNullableString(json['next_cursor']);
    final hasMore = asBool(json['has_more']);
    final queryKey = asString(json['query_key']).trim();
    final generation = asInt(json['generation']);
    if (hasMore != (cursor != null)) {
      throw const FormatException('상품 카탈로그 페이지 정보가 일치하지 않습니다.');
    }
    if (queryKey.isEmpty || generation <= 0) {
      throw const FormatException('상품 카탈로그의 검색 버전 정보가 없습니다.');
    }
    return EditorProductCatalogPage(
      scopeId: asString(json['scope_id']),
      catalogSnapshotId: asNullableString(json['catalog_snapshot_id']),
      source: asString(json['source']),
      syncedAt: asNullableString(json['synced_at']),
      totalCount: asInt(json['total_count']),
      filteredCount: asInt(json['filtered_count']),
      rows: rows,
      nextCursor: cursor,
      hasMore: hasMore,
      queryKey: queryKey,
      generation: generation,
      complete: asBool(json['complete']),
    );
  }
}
