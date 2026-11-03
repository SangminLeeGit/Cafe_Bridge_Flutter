// Models for the costing (원가 관리) feature.

import 'api_contracts.dart';

class CostingCalculationItem {
  final int ingredientId;
  final double quantity;
  final String unit;

  const CostingCalculationItem({
    required this.ingredientId,
    required this.quantity,
    required this.unit,
  });

  Map<String, dynamic> toJson({required int sortOrder}) => {
        'ingredient_id': ingredientId,
        'quantity': quantity,
        'unit': unit,
        'sort_order': sortOrder,
      };
}

/// Serializes calculation and recipe item inputs in their displayed order.
/// The backend requires sort_order to be the contiguous range 0..n-1.
List<Map<String, dynamic>> buildCostingItemsPayload(
  Iterable<CostingCalculationItem> items,
) {
  final orderedItems = items.toList(growable: false);
  return List<Map<String, dynamic>>.generate(
    orderedItems.length,
    (index) => orderedItems[index].toJson(sortOrder: index),
    growable: false,
  );
}

Map<String, dynamic> buildCostingIngredientCreatePayload({
  required String name,
  required String category,
  required String baseUnit,
  required String supplierName,
  required String notes,
  required String requestId,
}) =>
    {
      'name': name.trim(),
      'category': category.trim().isEmpty ? 'other' : category.trim(),
      'base_unit': baseUnit,
      if (supplierName.trim().isNotEmpty) 'supplier_name': supplierName.trim(),
      if (notes.trim().isNotEmpty) 'notes': notes.trim(),
      'is_active': true,
      'request_id': requestId,
    };

Map<String, dynamic> buildCostingIngredientPricePayload({
  required double purchasePrice,
  required double purchaseQty,
  required String purchaseUnit,
  required int expectedEditRevision,
  required String requestId,
  double? usableQty,
  String effectiveFrom = '',
  String supplierName = '',
  String memo = '',
}) =>
    {
      'purchase_price': purchasePrice,
      'purchase_qty': purchaseQty,
      'purchase_unit': purchaseUnit,
      if (usableQty != null) 'usable_qty': usableQty,
      if (effectiveFrom.trim().isNotEmpty)
        'effective_from': effectiveFrom.trim(),
      if (supplierName.trim().isNotEmpty) 'supplier_name': supplierName.trim(),
      if (memo.trim().isNotEmpty) 'memo': memo.trim(),
      'expected_edit_revision': expectedEditRevision,
      'request_id': requestId,
    };

Map<String, dynamic> buildCostingIngredientUpdatePayload({
  required String name,
  required String category,
  required String baseUnit,
  required String supplierName,
  required String notes,
  required bool isActive,
  required int expectedEditRevision,
  required String requestId,
}) =>
    {
      'name': name.trim(),
      'category': category.trim(),
      'base_unit': baseUnit,
      'supplier_name': supplierName.trim(),
      'notes': notes.trim(),
      'is_active': isActive,
      'expected_edit_revision': expectedEditRevision,
      'request_id': requestId,
    };

Map<String, dynamic> buildCostingRecipePayload({
  required String menuName,
  required String menuCode,
  required String sizeCode,
  required String temperatureCode,
  required int? sellingPrice,
  required double targetCostRatio,
  required String status,
  required String notes,
  required Iterable<CostingCalculationItem> items,
  required String requestId,
  int? expectedVersionNo,
}) =>
    {
      'menu_name': menuName.trim(),
      'menu_code': menuCode.trim(),
      'size_code': sizeCode.trim(),
      'temperature_code': temperatureCode.trim(),
      if (sellingPrice != null) 'selling_price': sellingPrice,
      'target_cost_ratio': targetCostRatio,
      'status': status,
      'notes': notes.trim(),
      'items': buildCostingItemsPayload(items),
      if (expectedVersionNo != null) 'expected_version_no': expectedVersionNo,
      'request_id': requestId,
    };

Map<String, dynamic> buildCostingRecipeDeletePayload({
  required int expectedVersionNo,
  required String requestId,
}) =>
    {
      'expected_version_no': expectedVersionNo,
      'request_id': requestId,
    };

class CostingDashboardSummary {
  final int ingredientCount;
  final int pricedIngredientCount;
  final int recipeCount;
  final int alertRecipeCount;
  final int recentPriceChangeCount;
  final String lastPriceChangeAt;

  const CostingDashboardSummary({
    required this.ingredientCount,
    required this.pricedIngredientCount,
    required this.recipeCount,
    required this.alertRecipeCount,
    required this.recentPriceChangeCount,
    required this.lastPriceChangeAt,
  });

  factory CostingDashboardSummary.fromJson(Map<String, dynamic> json) {
    return CostingDashboardSummary(
      ingredientCount: asInt(json['ingredient_count']),
      pricedIngredientCount: asInt(json['priced_ingredient_count']),
      recipeCount: asInt(json['recipe_count']),
      alertRecipeCount: asInt(json['alert_recipe_count']),
      recentPriceChangeCount: asInt(json['recent_price_change_count']),
      lastPriceChangeAt: asString(json['last_price_change_at']),
    );
  }
}

class RecipeSummaryRow {
  final int recipeId;
  final String menuCode;
  final String menuName;
  final String sizeCode;
  final String temperatureCode;
  final int sellingPrice;
  final double targetCostRatio;
  final int totalCost;
  final double costRatio;
  final int marginAmount;
  final String status;
  final String notes;
  final int itemCount;
  final int? versionNo;

  const RecipeSummaryRow({
    required this.recipeId,
    required this.menuCode,
    required this.menuName,
    required this.sizeCode,
    required this.temperatureCode,
    required this.sellingPrice,
    required this.targetCostRatio,
    required this.totalCost,
    required this.costRatio,
    required this.marginAmount,
    required this.status,
    this.notes = '',
    required this.itemCount,
    this.versionNo,
  });

  factory RecipeSummaryRow.fromJson(Map<String, dynamic> json) {
    return RecipeSummaryRow(
      recipeId: asInt(json['recipe_id']),
      menuCode: asString(json['menu_code']),
      menuName: asString(json['menu_name']),
      sizeCode: asString(json['size_code']),
      temperatureCode: asString(json['temperature_code']),
      sellingPrice: asInt(json['selling_price']),
      targetCostRatio: asDouble(json['target_cost_ratio']),
      totalCost: asInt(json['total_cost']),
      costRatio: asDouble(json['cost_ratio']),
      marginAmount: asInt(json['margin_amount']),
      status: asString(json['status']),
      notes: asString(json['notes']),
      itemCount: asInt(json['item_count']),
      versionNo: asNullableInt(json['version_no']),
    );
  }

  bool get isOverCost =>
      costRatio > targetCostRatio && sellingPrice > 0 && targetCostRatio > 0;
}

class CostingDashboardData {
  final String error;
  final CostingDashboardSummary summary;
  final List<RecipeSummaryRow> recentRecipes;
  final List<RecipeSummaryRow> alerts;

  const CostingDashboardData({
    required this.error,
    required this.summary,
    required this.recentRecipes,
    required this.alerts,
  });

  factory CostingDashboardData.fromJson(Map<String, dynamic> json) {
    return CostingDashboardData(
      error: asString(json['error']),
      summary: CostingDashboardSummary.fromJson(asMap(json['summary'])),
      recentRecipes: asListOfMaps(json['recent_recipes'])
          .map(RecipeSummaryRow.fromJson)
          .toList(growable: false),
      alerts: asListOfMaps(json['alerts'])
          .map(RecipeSummaryRow.fromJson)
          .toList(growable: false),
    );
  }
}

class Ingredient {
  final int ingredientId;
  final String name;
  final String category;
  final String baseUnit;
  final String supplierName;
  final bool isActive;
  final String notes;
  final int priceCount;
  final double? currentUnitCost;
  final int? editRevision;

  const Ingredient({
    required this.ingredientId,
    required this.name,
    required this.category,
    required this.baseUnit,
    required this.supplierName,
    required this.isActive,
    required this.notes,
    required this.priceCount,
    this.currentUnitCost,
    this.editRevision,
  });

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    final rawCost = json['current_unit_cost'];
    return Ingredient(
      ingredientId: asInt(json['ingredient_id']),
      name: asString(json['name']),
      category: asString(json['category']),
      baseUnit: asString(json['base_unit']),
      supplierName: asString(json['supplier_name']),
      isActive: json['is_active'] == true,
      notes: asString(json['notes']),
      priceCount: asInt(json['price_count']),
      currentUnitCost: rawCost == null ? null : asDouble(rawCost),
      editRevision: asNullableInt(json['edit_revision']),
    );
  }
}

class IngredientPrice {
  final int priceId;
  final int ingredientId;
  final double purchasePrice;
  final double purchaseQty;
  final String purchaseUnit;
  final double usableQty;
  final double unitCost;
  final String effectiveFrom;
  final String supplierName;
  final String memo;

  const IngredientPrice({
    required this.priceId,
    required this.ingredientId,
    required this.purchasePrice,
    required this.purchaseQty,
    required this.purchaseUnit,
    required this.usableQty,
    required this.unitCost,
    required this.effectiveFrom,
    required this.supplierName,
    required this.memo,
  });

  factory IngredientPrice.fromJson(Map<String, dynamic> json) {
    return IngredientPrice(
      priceId: asInt(json['price_id']),
      ingredientId: asInt(json['ingredient_id']),
      purchasePrice: asDouble(json['purchase_price']),
      purchaseQty: asDouble(json['purchase_qty']),
      purchaseUnit: asString(json['purchase_unit']),
      usableQty: asDouble(json['usable_qty']),
      unitCost: asDouble(json['unit_cost']),
      effectiveFrom: asString(json['effective_from']),
      supplierName: asString(json['supplier_name']),
      memo: asString(json['memo']),
    );
  }
}

class IngredientPriceHistoryData {
  final Ingredient ingredient;
  final List<IngredientPrice> prices;

  const IngredientPriceHistoryData({
    required this.ingredient,
    required this.prices,
  });

  factory IngredientPriceHistoryData.fromJson(Map<String, dynamic> json) {
    final rawIngredient = json['ingredient'];
    if (rawIngredient is! Map) {
      throw const FormatException('재료 단가 응답에 재료 편집 revision이 없습니다.');
    }
    final ingredient =
        Ingredient.fromJson(Map<String, dynamic>.from(rawIngredient));
    final rawPrices = json['prices'];
    final prices = rawPrices is List
        ? rawPrices
            .whereType<Map>()
            .map((item) =>
                IngredientPrice.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false)
        : const <IngredientPrice>[];
    return IngredientPriceHistoryData(ingredient: ingredient, prices: prices);
  }
}

class RecipeItem {
  final int recipeItemId;
  final int recipeId;
  final int ingredientId;
  final String ingredientName;
  final String ingredientBaseUnit;
  final double quantity;
  final double? currentUnitCost;
  final double? lineCost;
  final String notes;
  final bool ingredientActive;

  const RecipeItem({
    required this.recipeItemId,
    required this.recipeId,
    required this.ingredientId,
    required this.ingredientName,
    required this.ingredientBaseUnit,
    required this.quantity,
    this.currentUnitCost,
    this.lineCost,
    required this.notes,
    this.ingredientActive = true,
  });

  factory RecipeItem.fromJson(Map<String, dynamic> json) {
    return RecipeItem(
      recipeItemId: asInt(json['recipe_item_id']),
      recipeId: asInt(json['recipe_id']),
      ingredientId: asInt(json['ingredient_id']),
      ingredientName: asString(json['ingredient_name']),
      ingredientBaseUnit: asString(json['ingredient_base_unit']),
      quantity: asDouble(json['quantity']),
      currentUnitCost: json['current_unit_cost'] == null
          ? null
          : asDouble(json['current_unit_cost']),
      lineCost: json['line_cost'] == null ? null : asDouble(json['line_cost']),
      notes: asString(json['notes']),
      ingredientActive: json['ingredient_active'] == true,
    );
  }
}

class RecipeCalculateSummary {
  final int totalCost;
  final double costRatio;
  final int marginAmount;
  final int recommendedPrice;
  final int itemCount;

  const RecipeCalculateSummary({
    required this.totalCost,
    required this.costRatio,
    required this.marginAmount,
    required this.recommendedPrice,
    required this.itemCount,
  });

  factory RecipeCalculateSummary.fromJson(Map<String, dynamic> json) {
    return RecipeCalculateSummary(
      totalCost: asInt(json['total_cost']),
      costRatio: asDouble(json['cost_ratio']),
      marginAmount: asInt(json['margin_amount']),
      recommendedPrice: asInt(json['recommended_price']),
      itemCount: asInt(json['item_count']),
    );
  }
}

class RecipeDetailData {
  final RecipeSummaryRow recipe;
  final List<RecipeItem> items;
  final RecipeCalculateSummary summary;

  const RecipeDetailData({
    required this.recipe,
    required this.items,
    required this.summary,
  });

  factory RecipeDetailData.fromJson(Map<String, dynamic> json) {
    return RecipeDetailData(
      recipe: RecipeSummaryRow.fromJson(asMap(json['recipe'])),
      items: asListOfMaps(json['items'])
          .map(RecipeItem.fromJson)
          .toList(growable: false),
      summary: RecipeCalculateSummary.fromJson(asMap(json['summary'])),
    );
  }
}
