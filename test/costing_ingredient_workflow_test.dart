import 'package:cafe_bridge_flutter/screens/costing.dart';
import 'package:cafe_bridge_flutter/services/cache_store.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeCostingAppState extends AppState {
  bool ingredientCreated = false;
  bool priceAdded = false;
  final List<({String endpoint, String method, Map<String, dynamic>? body})>
      writes = [];

  @override
  bool get hasOperatorAccess => true;

  @override
  bool canAccess(UserRole requiredRole) =>
      UserRole.operator.allows(requiredRole);

  Map<String, dynamic> _ingredient({int revision = 1, int priceCount = 0}) => {
        'ingredient_id': 17,
        'name': '원두',
        'category': 'coffee',
        'base_unit': 'g',
        'supplier_name': '농장',
        'is_active': true,
        'notes': '',
        'price_count': priceCount,
        'edit_revision': revision,
        'current_unit_cost': priceAdded ? 12.5 : null,
      };

  @override
  Future<CachedDataResult<T>> fetchMapParsed<T>(
    String endpoint, {
    Map<String, Object?>? params,
    required T Function(Map<String, dynamic> json) parser,
    Duration cacheTtl = const Duration(minutes: 30),
    bool allowStaleOnError = true,
    ApiCachePolicy? cachePolicy,
  }) async {
    final Map<String, dynamic> json;
    if (endpoint == '/api/costing/dashboard') {
      json = {
        'summary': {
          'ingredient_count': ingredientCreated ? 1 : 0,
          'priced_ingredient_count': priceAdded ? 1 : 0,
          'recipe_count': 0,
          'alert_recipe_count': 0,
          'recent_price_change_count': 0,
          'last_price_change_at': '',
        },
        'recent_recipes': [],
        'alerts': [],
      };
    } else if (endpoint == '/api/costing/ingredients') {
      json = {
        'ingredients': ingredientCreated
            ? [
                _ingredient(
                    revision: priceAdded ? 2 : 1,
                    priceCount: priceAdded ? 1 : 0)
              ]
            : [],
      };
    } else if (endpoint == '/api/costing/recipes') {
      json = {'recipes': []};
    } else if (endpoint == '/api/costing/ingredients/17/prices') {
      json = {
        'ingredient': _ingredient(
            revision: priceAdded ? 2 : 1, priceCount: priceAdded ? 1 : 0),
        'prices': priceAdded
            ? [
                {
                  'price_id': 91,
                  'ingredient_id': 17,
                  'purchase_price': 12500,
                  'purchase_qty': 1,
                  'purchase_unit': 'kg',
                  'usable_qty': 1000,
                  'unit_cost': 12.5,
                  'effective_from': '2026-10-03',
                  'supplier_name': '농장',
                  'memo': '',
                },
              ]
            : [],
      };
    } else {
      throw StateError('unexpected read endpoint $endpoint');
    }
    return CachedDataResult<T>(
      data: parser(json),
      fromCache: false,
      cachedAt: DateTime.now(),
    );
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String endpoint, {
    Map<String, dynamic>? body,
    String method = 'POST',
  }) async {
    writes.add((endpoint: endpoint, method: method, body: body));
    if (endpoint == '/api/costing/ingredients') {
      ingredientCreated = true;
      return {'ingredient': _ingredient()};
    }
    if (endpoint == '/api/costing/ingredients/17/prices') {
      priceAdded = true;
      return {
        'ingredient': _ingredient(revision: 2, priceCount: 1),
        'prices': [],
      };
    }
    throw StateError('unexpected write endpoint $endpoint');
  }
}

void main() {
  testWidgets('creates an ingredient and records a revisioned price',
      (tester) async {
    final state = _FakeCostingAppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: CostingScreen())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('재료'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('새 재료 등록'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '원두');
    await tester.tap(find.text('등록'));
    await tester.pumpAndSettle();

    expect(state.writes, hasLength(1));
    expect(state.writes.first.endpoint, '/api/costing/ingredients');
    expect(state.writes.first.method, 'POST');
    expect(state.writes.first.body?['name'], '원두');
    expect(state.writes.first.body?['base_unit'], 'g');
    expect(
      state.writes.first.body?['request_id'],
      matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
    );
    expect(find.text('원두'), findsOneWidget);

    await tester.tap(find.text('원두'));
    await tester.pumpAndSettle();
    expect(find.text('등록된 단가 이력이 없습니다.'), findsOneWidget);
    await tester.tap(find.text('단가 등록'));
    await tester.pumpAndSettle();
    final purchasePrice = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == '매입금액 *',
    );
    final purchaseQty = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == '매입 수량 *',
    );
    await tester.enterText(purchasePrice, '12500');
    await tester.enterText(purchaseQty, '1');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('단가 등록'),
      ),
    );
    await tester.pumpAndSettle();

    expect(state.writes, hasLength(2));
    final priceWrite = state.writes.last;
    expect(priceWrite.endpoint, '/api/costing/ingredients/17/prices');
    expect(priceWrite.method, 'POST');
    expect(priceWrite.body?['purchase_price'], 12500.0);
    expect(priceWrite.body?['purchase_qty'], 1.0);
    expect(priceWrite.body?['expected_edit_revision'], 1);
    expect(
      priceWrite.body?['request_id'],
      matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
    );
    expect(find.textContaining('구매 12500원'), findsOneWidget);
  });
}
