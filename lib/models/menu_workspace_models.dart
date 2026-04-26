import 'api_contracts.dart';

// Models for the menu workspace (메뉴 워크스페이스) feature.

class MenuEntry {
  final int id;
  final String kind;
  final String status;
  final String itemCode;
  final String itemName;
  final int? currentPrice;
  final int? targetPrice;
  final String categoryHint;
  final String majorCategory;
  final String middleCategory;
  final String minorCategory;
  final String unitName;
  final String taxMode;
  final String useMode;
  final String stockMode;
  final String barcode;
  final String description;
  final int? costPrice;
  final int? supplyPrice;
  final String notes;
  final String source;
  final String createdAt;
  final String updatedAt;

  const MenuEntry({
    required this.id,
    required this.kind,
    required this.status,
    required this.itemCode,
    required this.itemName,
    this.currentPrice,
    this.targetPrice,
    required this.categoryHint,
    required this.majorCategory,
    required this.middleCategory,
    required this.minorCategory,
    required this.unitName,
    required this.taxMode,
    required this.useMode,
    required this.stockMode,
    required this.barcode,
    required this.description,
    this.costPrice,
    this.supplyPrice,
    required this.notes,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MenuEntry.fromJson(Map<String, dynamic> json) {
    return MenuEntry(
      id: asInt(json['id']),
      kind: asString(json['kind']),
      status: asString(json['status']),
      itemCode: asString(json['item_code']),
      itemName: asString(json['item_name']),
      currentPrice: json['current_price'] == null ? null : asInt(json['current_price']),
      targetPrice: json['target_price'] == null ? null : asInt(json['target_price']),
      categoryHint: asString(json['category_hint']),
      majorCategory: asString(json['major_category']),
      middleCategory: asString(json['middle_category']),
      minorCategory: asString(json['minor_category']),
      unitName: asString(json['unit_name']),
      taxMode: asString(json['tax_mode']),
      useMode: asString(json['use_mode']),
      stockMode: asString(json['stock_mode']),
      barcode: asString(json['barcode']),
      description: asString(json['description']),
      costPrice: json['cost_price'] == null ? null : asInt(json['cost_price']),
      supplyPrice: json['supply_price'] == null ? null : asInt(json['supply_price']),
      notes: asString(json['notes']),
      source: asString(json['source']),
      createdAt: asString(json['created_at']),
      updatedAt: asString(json['updated_at']),
    );
  }

  int get priceDelta => (targetPrice ?? 0) - (currentPrice ?? 0);
}

class WorkspaceSnapshotSummary {
  final int totalEntries;
  final int priceDeltaTotal;
  final int newItemCount;
  final int readyCount;

  const WorkspaceSnapshotSummary({
    required this.totalEntries,
    required this.priceDeltaTotal,
    required this.newItemCount,
    required this.readyCount,
  });

  factory WorkspaceSnapshotSummary.fromJson(Map<String, dynamic> json) {
    return WorkspaceSnapshotSummary(
      totalEntries: asInt(json['total_entries']),
      priceDeltaTotal: asInt(json['price_delta_total']),
      newItemCount: asInt(json['new_item_count']),
      readyCount: asInt(json['ready_count']),
    );
  }
}

class WorkspaceSnapshot {
  final List<MenuEntry> entries;
  final Map<String, int> statusCounts;
  final Map<String, int> kindCounts;
  final WorkspaceSnapshotSummary summary;

  const WorkspaceSnapshot({
    required this.entries,
    required this.statusCounts,
    required this.kindCounts,
    required this.summary,
  });

  factory WorkspaceSnapshot.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status_counts'];
    final statusCounts = <String, int>{};
    if (rawStatus is Map) {
      rawStatus.forEach((k, v) => statusCounts[k.toString()] = asInt(v));
    }

    final rawKind = json['kind_counts'];
    final kindCounts = <String, int>{};
    if (rawKind is Map) {
      rawKind.forEach((k, v) => kindCounts[k.toString()] = asInt(v));
    }

    return WorkspaceSnapshot(
      entries: asListOfMaps(json['entries'])
          .map(MenuEntry.fromJson)
          .toList(growable: false),
      statusCounts: statusCounts,
      kindCounts: kindCounts,
      summary: WorkspaceSnapshotSummary.fromJson(asMap(json['summary'])),
    );
  }
}

class ProductRegistrationLookup {
  final String productCode;
  final bool found;
  final Map<String, dynamic> row;
  final String source;
  final String syncedAt;

  const ProductRegistrationLookup({
    required this.productCode,
    required this.found,
    required this.row,
    required this.source,
    required this.syncedAt,
  });

  factory ProductRegistrationLookup.fromJson(Map<String, dynamic> json) {
    return ProductRegistrationLookup(
      productCode: asString(json['product_code']),
      found: json['found'] == true,
      row: asMap(json['row']),
      source: asString(json['source']),
      syncedAt: asString(json['synced_at']),
    );
  }
}

class NewItemValidationIssue {
  final int entryId;
  final String itemName;
  final String itemCode;
  final List<String> messages;

  const NewItemValidationIssue({
    required this.entryId,
    required this.itemName,
    required this.itemCode,
    required this.messages,
  });

  factory NewItemValidationIssue.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
    return NewItemValidationIssue(
      entryId: asInt(json['entry_id']),
      itemName: asString(json['item_name']),
      itemCode: asString(json['item_code']),
      messages: rawMessages is List ? rawMessages.map((v) => v.toString()).toList(growable: false) : const [],
    );
  }
}

class NewItemValidationDuplicateIssue {
  final String field;
  final String value;
  final List<int> entryIds;

  const NewItemValidationDuplicateIssue({
    required this.field,
    required this.value,
    required this.entryIds,
  });

  factory NewItemValidationDuplicateIssue.fromJson(Map<String, dynamic> json) {
    final rawIds = json['entry_ids'];
    return NewItemValidationDuplicateIssue(
      field: asString(json['field']),
      value: asString(json['value']),
      entryIds: rawIds is List ? rawIds.map(asInt).toList(growable: false) : const [],
    );
  }
}

class NewItemValidationResponse {
  final String scope;
  final int entryCount;
  final int issueCount;
  final int validCount;
  final List<int> validEntryIds;
  final List<NewItemValidationIssue> issues;
  final List<NewItemValidationDuplicateIssue> duplicateIssues;

  const NewItemValidationResponse({
    required this.scope,
    required this.entryCount,
    required this.issueCount,
    required this.validCount,
    required this.validEntryIds,
    required this.issues,
    required this.duplicateIssues,
  });

  factory NewItemValidationResponse.fromJson(Map<String, dynamic> json) {
    final rawValidIds = json['valid_entry_ids'];
    final rawIssues = json['issues'];
    final rawDuplicates = json['duplicate_issues'];
    return NewItemValidationResponse(
      scope: asString(json['scope']),
      entryCount: asInt(json['entry_count']),
      issueCount: asInt(json['issue_count']),
      validCount: asInt(json['valid_count']),
      validEntryIds: rawValidIds is List ? rawValidIds.map(asInt).toList(growable: false) : const [],
      issues: rawIssues is List
          ? rawIssues.whereType<Map>().map((item) => NewItemValidationIssue.fromJson(Map<String, dynamic>.from(item))).toList(growable: false)
          : const [],
      duplicateIssues: rawDuplicates is List
          ? rawDuplicates
              .whereType<Map>()
              .map((item) => NewItemValidationDuplicateIssue.fromJson(Map<String, dynamic>.from(item)))
              .toList(growable: false)
          : const [],
    );
  }
}

class WorkspaceTaskHistoryEntry {
  final Map<String, dynamic> data;

  const WorkspaceTaskHistoryEntry({required this.data});

  factory WorkspaceTaskHistoryEntry.fromJson(Map<String, dynamic> json) {
    return WorkspaceTaskHistoryEntry(data: Map<String, dynamic>.from(json));
  }

  String get taskId => asString(data['task_id']);
  String get status => asString(data['status']);
  String get reason => asString(data['reason']);
  String get actor => asString(data['actor']);
  String get startedAt => asString(data['started_at']);
  String get finishedAt => asString(data['finished_at']);
  String get errorMessage => asString(data['error_message']);
  bool get execute => data['execute'] == true || data['execute'] == 1;
  String get itemName => asString(data['item_name']);
  String get itemCode => asString(data['item_code']);
  String get productCode => asString(data['product_code']);
  Map<String, dynamic> get result => asMap(data['result']);
  int? get targetPrice {
    final value = data['target_price'];
    if (value == null) return null;
    return asInt(value);
  }
  String get resultStatus => asString(result['status']);
  String get resultMessage => asString(result['message']);
  String get savedItemCode {
    final direct = asString(result['saved_item_code']).trim();
    if (direct.isNotEmpty) return direct;
    return asString(asMap(result['saved_item'])['item_code']).trim();
  }
  Map<String, dynamic> get resolvedCategories => asMap(result['resolved_categories']);
  String get displayTitle =>
      itemName.isNotEmpty ? itemName : (productCode.isNotEmpty ? productCode : taskId);
  String get displaySubtitle {
    final pieces = <String>[
      if (itemCode.isNotEmpty) '코드 $itemCode',
      if (savedItemCode.isNotEmpty && savedItemCode != itemCode) '저장코드 $savedItemCode',
      if (productCode.isNotEmpty && productCode != itemCode) '상품코드 $productCode',
      if (reason.isNotEmpty) reason,
    ];
    return pieces.join(' · ');
  }
}

class PriceApplyRun {
  final String taskId;
  final String status;
  final int totalItems;
  final int appliedCount;
  final int failedCount;
  final String startedAt;
  final String finishedAt;
  final String errorMessage;

  const PriceApplyRun({
    required this.taskId,
    required this.status,
    required this.totalItems,
    required this.appliedCount,
    required this.failedCount,
    required this.startedAt,
    required this.finishedAt,
    required this.errorMessage,
  });

  factory PriceApplyRun.fromJson(Map<String, dynamic> json) {
    return PriceApplyRun(
      taskId: asString(json['task_id']),
      status: asString(json['status']),
      totalItems: asInt(json['total_items']),
      appliedCount: asInt(json['applied_count']),
      failedCount: asInt(json['failed_count']),
      startedAt: asString(json['started_at']),
      finishedAt: asString(json['finished_at']),
      errorMessage: asString(json['error_message']),
    );
  }
}
