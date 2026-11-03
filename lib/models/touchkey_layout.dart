import 'api_contracts.dart';

class TouchkeyLayoutIssue {
  final String code;
  final String message;

  const TouchkeyLayoutIssue({required this.code, required this.message});

  factory TouchkeyLayoutIssue.fromJson(Map<String, dynamic> json) =>
      TouchkeyLayoutIssue(
        code: asString(json['code']),
        message: asString(json['message']),
      );
}

class TouchkeyLayoutDefinition {
  final String layoutId;
  final String classCode;
  final String sortValue;
  final int page;
  final int columns;
  final int rows;
  final bool complete;
  final List<TouchkeyLayoutIssue> issues;

  const TouchkeyLayoutDefinition({
    required this.layoutId,
    required this.classCode,
    required this.sortValue,
    required this.page,
    required this.columns,
    required this.rows,
    required this.complete,
    required this.issues,
  });

  factory TouchkeyLayoutDefinition.fromJson(Map<String, dynamic> json) =>
      TouchkeyLayoutDefinition(
        layoutId: asString(json['layout_id']),
        classCode: asString(json['class_code']),
        sortValue: asString(json['sort_value']),
        page: asInt(json['page']),
        columns: asInt(json['columns']),
        rows: asInt(json['rows']),
        complete: asBool(json['complete']),
        issues: asListOfMaps(json['issues'])
            .map(TouchkeyLayoutIssue.fromJson)
            .toList(growable: false),
      );

  int get slotCount => columns * rows;

  bool get hasSafeDimensions =>
      columns > 0 &&
      rows > 0 &&
      columns <= 100 &&
      rows <= 100 &&
      slotCount <= 10000;
}

class TouchkeyLayoutSnapshot {
  final String snapshotId;
  final String revision;
  final Map<String, String?> placements;
  final bool complete;
  final List<TouchkeyLayoutIssue> issues;

  const TouchkeyLayoutSnapshot({
    required this.snapshotId,
    required this.revision,
    required this.placements,
    required this.complete,
    required this.issues,
  });

  factory TouchkeyLayoutSnapshot.fromJson(
    Map<String, dynamic> json, {
    required TouchkeyLayoutDefinition definition,
  }) {
    final rawPlacements = json['placements'];
    final placements = <String, String?>{};
    if (rawPlacements is Map) {
      rawPlacements.forEach((key, value) {
        final text = value?.toString().trim() ?? '';
        placements[key.toString()] = text.isEmpty ? null : text;
      });
    }
    final expected = <String>{
      for (var vertical = 1; vertical <= definition.rows; vertical++)
        for (var horizontal = 1; horizontal <= definition.columns; horizontal++)
          '$horizontal:$vertical',
    };
    final complete = asBool(json['complete']);
    if (complete && placements.keys.toSet().difference(expected).isNotEmpty) {
      throw const FormatException('터치키 슬롯 응답에 알 수 없는 좌표가 있습니다.');
    }
    final actualKeys = placements.keys.toSet();
    if (complete &&
        (actualKeys.length != expected.length ||
            !actualKeys.containsAll(expected))) {
      throw const FormatException('완성된 터치키 초안에 모든 슬롯 좌표가 포함되지 않았습니다.');
    }
    return TouchkeyLayoutSnapshot(
      snapshotId: asString(json['snapshot_id']),
      revision: asString(json['revision']),
      placements: Map.unmodifiable(placements),
      complete: complete,
      issues: asListOfMaps(json['issues'])
          .map(TouchkeyLayoutIssue.fromJson)
          .toList(growable: false),
    );
  }
}

class TouchkeyLayoutProduct {
  final String code;
  final String name;
  final String price;
  final bool placeable;

  const TouchkeyLayoutProduct({
    required this.code,
    required this.name,
    required this.price,
    required this.placeable,
  });

  factory TouchkeyLayoutProduct.fromJson(Map<String, dynamic> json) =>
      TouchkeyLayoutProduct(
        code: asString(json['product_code']).trim(),
        name: asString(json['name']).trim(),
        price: asString(json['price']).trim(),
        placeable: asBool(json['placeable']),
      );
}

class TouchkeyLayoutEnvelope {
  final String scopeId;
  final TouchkeyLayoutDefinition definition;
  final TouchkeyLayoutSnapshot base;
  final TouchkeyLayoutSnapshot saved;
  final Map<String, TouchkeyLayoutProduct> products;
  final bool canEdit;
  final bool canApply;

  const TouchkeyLayoutEnvelope({
    required this.scopeId,
    required this.definition,
    required this.base,
    required this.saved,
    required this.products,
    required this.canEdit,
    required this.canApply,
  });

  factory TouchkeyLayoutEnvelope.fromJson(Map<String, dynamic> json) {
    final definition =
        TouchkeyLayoutDefinition.fromJson(asMap(json['definition']));
    final scopeId = asString(json['scope_id']).trim();
    if (scopeId.isEmpty ||
        definition.layoutId.trim().isEmpty ||
        definition.page < 1 ||
        definition.classCode.trim().isEmpty) {
      throw const FormatException('터치키 초안의 편집 범위 또는 레이아웃 식별 정보가 없습니다.');
    }
    final base = TouchkeyLayoutSnapshot.fromJson(asMap(json['base']),
        definition: definition);
    final saved = TouchkeyLayoutSnapshot.fromJson(asMap(json['saved']),
        definition: definition);
    final rawProducts = json['products'];
    final products = <String, TouchkeyLayoutProduct>{};
    if (rawProducts is Map) {
      rawProducts.forEach((key, value) {
        if (value is Map) {
          final product = TouchkeyLayoutProduct.fromJson(asMap(value));
          products[key.toString()] = product;
        }
      });
    }
    final capabilities = asMap(json['capabilities']);
    return TouchkeyLayoutEnvelope(
      scopeId: scopeId,
      definition: definition,
      base: base,
      saved: saved,
      products: Map.unmodifiable(products),
      canEdit: asBool(asMap(capabilities['edit'])['enabled']),
      canApply: asBool(asMap(capabilities['apply'])['enabled']),
    );
  }
}

/// Builds the complete idempotent server-draft save contract.
Map<String, dynamic> buildTouchkeyLayoutSavePayload({
  required TouchkeyLayoutEnvelope envelope,
  required Map<String, String?> placements,
  required String requestId,
}) {
  final definition = envelope.definition;
  if (!definition.hasSafeDimensions ||
      !definition.complete ||
      !envelope.base.complete ||
      !envelope.saved.complete ||
      !envelope.canEdit) {
    throw StateError('터치키 원본 또는 저장 초안이 완전하지 않아 편집할 수 없습니다.');
  }
  final normalizedRequestId = requestId.trim();
  if (!RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        caseSensitive: false,
      ).hasMatch(normalizedRequestId) ||
      envelope.base.snapshotId.trim().isEmpty ||
      !RegExp(r'^\d+$').hasMatch(envelope.saved.revision)) {
    throw StateError('터치키 저장 요청의 ID 또는 revision 정보가 올바르지 않습니다.');
  }
  final expectedKeys = <String>{
    for (var vertical = 1; vertical <= definition.rows; vertical++)
      for (var horizontal = 1; horizontal <= definition.columns; horizontal++)
        '$horizontal:$vertical',
  };
  final placementKeys = placements.keys.toSet();
  if (placementKeys.length != expectedKeys.length ||
      !placementKeys.containsAll(expectedKeys)) {
    throw StateError('터치키 초안에 모든 슬롯 값이 필요합니다.');
  }
  final productCodes = placements.values
      .whereType<String>()
      .where((code) => code.isNotEmpty)
      .toList();
  if (productCodes.length != productCodes.toSet().length) {
    throw StateError('같은 상품을 여러 터치키 슬롯에 배치할 수 없습니다.');
  }
  final slots = <Map<String, dynamic>>[
    for (var vertical = 1; vertical <= definition.rows; vertical++)
      for (var horizontal = 1; horizontal <= definition.columns; horizontal++)
        {
          'h': horizontal,
          'v': vertical,
          'product_code': placements['$horizontal:$vertical'],
        },
  ];
  return {
    'request_id': normalizedRequestId,
    'expected_revision': envelope.saved.revision,
    'base_snapshot_id': envelope.base.snapshotId,
    'class_code': definition.classCode,
    'sort_value': definition.sortValue,
    'page': definition.page,
    'slots': slots,
  };
}
