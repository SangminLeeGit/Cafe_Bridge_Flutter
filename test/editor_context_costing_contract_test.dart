import 'package:cafe_bridge_flutter/models/costing_models.dart';
import 'package:cafe_bridge_flutter/models/editor_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('editor price capability', () {
    test('fails closed when backend disables apply_price', () {
      final context = EditorContext.fromJson({
        'scope_id': 'scope-1',
        'scope_status': 'configured',
        'role': 'admin',
        'source_ready': true,
        'capabilities': {
          'apply_price': {
            'enabled': false,
            'reason_code': 'capability_disabled',
            'message': 'Verifier unavailable',
            'supported_columns': [],
          },
        },
      });

      expect(context.canApplyPrice('판매가'), isFalse);
      expect(context.priceApplyBlockReason('판매가'), contains('미리보기만'));
    });

    test('requires the requested price column to be explicitly supported', () {
      final context = EditorContext.fromJson({
        'capabilities': {
          'apply_price': {
            'enabled': true,
            'reason_code': 'ready',
            'supported_columns': ['가격1'],
          },
        },
      });

      expect(context.canApplyPrice('판매가'), isFalse);
      expect(context.canApplyPrice('가격1'), isTrue);
    });

    test('missing apply capability does not enable execution', () {
      final context = EditorContext.fromJson({'capabilities': {}});
      expect(context.canApplyPrice('판매가'), isFalse);
      expect(context.priceApplyBlockReason('판매가'), isNotEmpty);
    });
  });

  group('costing item serialization', () {
    const beans = CostingCalculationItem(
      ingredientId: 7,
      quantity: 18.5,
      unit: 'g',
    );
    const milk = CostingCalculationItem(
      ingredientId: 3,
      quantity: 120,
      unit: 'ml',
    );

    test('assigns zero-based contiguous order to a single item', () {
      expect(buildCostingItemsPayload([beans]), [
        {
          'ingredient_id': 7,
          'quantity': 18.5,
          'unit': 'g',
          'sort_order': 0,
        },
      ]);
    });

    test('rebuilds order after deletion and reordering', () {
      final payload = buildCostingItemsPayload([milk, beans]);
      expect(payload.map((item) => item['ingredient_id']), [3, 7]);
      expect(payload.map((item) => item['sort_order']), [0, 1]);

      final afterDelete = buildCostingItemsPayload([beans]);
      expect(afterDelete.single['sort_order'], 0);
    });
  });

  group('costing mutation payloads', () {
    test('creates and updates recipes with contiguous items and version guards',
        () {
      const requestId = '12345678-1234-4234-8234-123456789abc';
      final recipePayload = buildCostingRecipePayload(
        menuName: '  카페 라떼  ',
        menuCode: ' LATTE ',
        sizeCode: 'L',
        temperatureCode: 'HOT',
        sellingPrice: 4500,
        targetCostRatio: 0.28,
        status: 'active',
        notes: '  표준 레시피  ',
        items: const [
          CostingCalculationItem(ingredientId: 7, quantity: 18, unit: 'g'),
          CostingCalculationItem(ingredientId: 3, quantity: 120, unit: 'ml'),
        ],
        requestId: requestId,
        expectedVersionNo: 9,
      );

      expect(recipePayload, {
        'menu_name': '카페 라떼',
        'menu_code': 'LATTE',
        'size_code': 'L',
        'temperature_code': 'HOT',
        'selling_price': 4500,
        'target_cost_ratio': 0.28,
        'status': 'active',
        'notes': '표준 레시피',
        'items': [
          {
            'ingredient_id': 7,
            'quantity': 18.0,
            'unit': 'g',
            'sort_order': 0,
          },
          {
            'ingredient_id': 3,
            'quantity': 120.0,
            'unit': 'ml',
            'sort_order': 1,
          },
        ],
        'expected_version_no': 9,
        'request_id': requestId,
      });
    });

    test('parses recipe revision and note metadata for safe editing', () {
      final recipe = RecipeSummaryRow.fromJson({
        'recipe_id': 42,
        'menu_name': '라떼',
        'version_no': 5,
        'notes': '표준 레시피',
      });

      expect(recipe.versionNo, 5);
      expect(recipe.notes, '표준 레시피');
    });

    test('deletes recipes with expected version and idempotency metadata', () {
      expect(
        buildCostingRecipeDeletePayload(
          expectedVersionNo: 11,
          requestId: '12345678-1234-4234-8234-123456789abc',
        ),
        {
          'expected_version_no': 11,
          'request_id': '12345678-1234-4234-8234-123456789abc',
        },
      );
    });

    test('creates an ingredient with the operator request receipt ID', () {
      expect(
        buildCostingIngredientCreatePayload(
          name: '  원두  ',
          category: 'coffee',
          baseUnit: 'g',
          supplierName: '  공급처  ',
          notes: '  매장용  ',
          requestId: '12345678-1234-4234-8234-123456789abc',
        ),
        {
          'name': '원두',
          'category': 'coffee',
          'base_unit': 'g',
          'supplier_name': '공급처',
          'notes': '매장용',
          'is_active': true,
          'request_id': '12345678-1234-4234-8234-123456789abc',
        },
      );
    });

    test('records ingredient prices using the latest edit revision', () {
      expect(
        buildCostingIngredientPricePayload(
          purchasePrice: 12500,
          purchaseQty: 1,
          purchaseUnit: 'kg',
          usableQty: 950,
          expectedEditRevision: 3,
          requestId: '12345678-1234-4234-8234-123456789abc',
          supplierName: '농장',
          memo: '  수율 반영  ',
        ),
        {
          'purchase_price': 12500.0,
          'purchase_qty': 1.0,
          'purchase_unit': 'kg',
          'usable_qty': 950.0,
          'supplier_name': '농장',
          'memo': '수율 반영',
          'expected_edit_revision': 3,
          'request_id': '12345678-1234-4234-8234-123456789abc',
        },
      );
    });

    test('updates an ingredient with compare-and-swap revision metadata', () {
      expect(
        buildCostingIngredientUpdatePayload(
          name: '  귀리 우유  ',
          category: 'dairy',
          baseUnit: 'ml',
          supplierName: '',
          notes: '  무가당  ',
          isActive: false,
          expectedEditRevision: 8,
          requestId: '12345678-1234-4234-8234-123456789abc',
        ),
        {
          'name': '귀리 우유',
          'category': 'dairy',
          'base_unit': 'ml',
          'supplier_name': '',
          'notes': '무가당',
          'is_active': false,
          'expected_edit_revision': 8,
          'request_id': '12345678-1234-4234-8234-123456789abc',
        },
      );
    });

    test('parses an ingredient write revision when present', () {
      expect(
        Ingredient.fromJson({
          'ingredient_id': 5,
          'name': '원두',
          'base_unit': 'g',
          'edit_revision': 7,
        }).editRevision,
        7,
      );
    });
  });
}
