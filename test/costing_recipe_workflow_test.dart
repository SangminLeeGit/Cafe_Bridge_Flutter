import 'package:cafe_bridge_flutter/screens/costing.dart';
import 'package:cafe_bridge_flutter/services/cache_store.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeRecipeAppState extends AppState {
  bool recipeCreated = false;
  bool recipeUpdated = false;
  bool recipeDeleted = false;
  final List<({String endpoint, String method, Map<String, dynamic>? body})>
      writes = [];

  @override
  bool get hasOperatorAccess => true;

  @override
  bool canAccess(UserRole requiredRole) =>
      UserRole.operator.allows(requiredRole);

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
          'ingredient_count': 1,
          'priced_ingredient_count': 1,
          'recipe_count': recipeCreated ? 1 : 0,
          'alert_recipe_count': 0,
          'recent_price_change_count': 0,
          'last_price_change_at': '',
        },
        'recent_recipes': [],
        'alerts': [],
      };
    } else if (endpoint == '/api/costing/recipes') {
      json = {
        'recipes': recipeCreated && !recipeDeleted
            ? [
                {
                  'recipe_id': 42,
                  'menu_code': 'LATTE',
                  'menu_name': '라떼',
                  'size_code': '',
                  'temperature_code': '',
                  'selling_price': 0,
                  'target_cost_ratio': 0.3,
                  'total_cost': 225,
                  'cost_ratio': 0,
                  'margin_amount': 0,
                  'status': 'draft',
                  'item_count': 1,
                  'version_no': 1,
                },
              ]
            : [],
      };
    } else if (endpoint == '/api/costing/ingredients') {
      json = {
        'ingredients': [
          {
            'ingredient_id': 17,
            'name': '원두',
            'category': 'coffee',
            'base_unit': 'g',
            'supplier_name': '농장',
            'is_active': true,
            'notes': '',
            'price_count': 1,
            'current_unit_cost': 12.5,
            'edit_revision': 2,
          },
        ],
      };
    } else if (endpoint == '/api/costing/recipes/42') {
      json = {
        'recipe': {
          'recipe_id': 42,
          'menu_code': 'LATTE',
          'menu_name': recipeUpdated ? '라떼 수정' : '라떼',
          'size_code': '',
          'temperature_code': '',
          'selling_price': 4500,
          'target_cost_ratio': 0.3,
          'total_cost': 225,
          'cost_ratio': 0.05,
          'margin_amount': 4275,
          'status': 'active',
          'notes': '표준 레시피',
          'item_count': 1,
          'version_no': 4,
        },
        'items': [
          {
            'recipe_item_id': 88,
            'recipe_id': 42,
            'ingredient_id': 17,
            'ingredient_name': '원두',
            'ingredient_base_unit': 'g',
            'quantity': 18,
            'current_unit_cost': 12.5,
            'line_cost': 225,
            'notes': '',
            'ingredient_active': true,
          },
        ],
        'summary': {
          'total_cost': 225,
          'cost_ratio': 0.05,
          'margin_amount': 4275,
          'recommended_price': 750,
          'item_count': 1,
        },
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
    if (endpoint == '/api/costing/recipes') {
      recipeCreated = true;
      return {
        'recipe': {'recipe_id': 42, 'version_no': 1}
      };
    }
    if (endpoint == '/api/costing/recipes/42' && method == 'PATCH') {
      recipeUpdated = true;
      return {
        'recipe': {'recipe_id': 42, 'version_no': 5}
      };
    }
    if (endpoint == '/api/costing/recipes/42' && method == 'DELETE') {
      recipeDeleted = true;
      return {'ok': true, 'recipe_id': 42, 'version_no': 4};
    }
    throw StateError('unexpected write endpoint $endpoint');
  }
}

void main() {
  testWidgets('creates a revisioned recipe with contiguous item ordering',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _FakeRecipeAppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: CostingScreen())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(TabBar),
      matching: find.text('레시피'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('새 레시피 등록'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == '메뉴명 *',
        ),
        '라떼');
    await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == '메뉴 코드',
        ),
        ' LATTE ');
    final ingredientDropdown = find.byType(DropdownButtonFormField<int>);
    await tester.ensureVisible(ingredientDropdown);
    await tester.tap(ingredientDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('원두 (g)').last);
    await tester.pumpAndSettle();
    final quantityField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == '사용량 * (g)',
    );
    await tester.ensureVisible(quantityField);
    await tester.enterText(
      quantityField,
      '18',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('저장'),
      ),
    );
    await tester.pumpAndSettle();

    expect(state.writes, hasLength(1));
    final write = state.writes.single;
    expect(write.endpoint, '/api/costing/recipes');
    expect(write.method, 'POST');
    expect(write.body?['menu_name'], '라떼');
    expect(write.body?['menu_code'], 'LATTE');
    expect(write.body?['target_cost_ratio'], 0.3);
    expect(write.body?['status'], 'draft');
    expect(write.body?['expected_version_no'], isNull);
    expect(write.body?['items'], [
      {
        'ingredient_id': 17,
        'quantity': 18.0,
        'unit': 'g',
        'sort_order': 0,
      },
    ]);
    expect(
      write.body?['request_id'],
      matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
    );
    expect(find.text('라떼'), findsOneWidget);
  });

  testWidgets('updates a recipe with the loaded version guard', (tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _FakeRecipeAppState()..recipeCreated = true;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: CostingScreen())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(TabBar),
      matching: find.text('레시피'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('라떼'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('레시피 수정'));
    await tester.pumpAndSettle();

    final nameField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == '메뉴명 *',
    );
    await tester.enterText(nameField, '라떼 수정');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('저장'),
      ),
    );
    await tester.pumpAndSettle();

    expect(state.writes, hasLength(1));
    final write = state.writes.single;
    expect(write.endpoint, '/api/costing/recipes/42');
    expect(write.method, 'PATCH');
    expect(write.body?['menu_name'], '라떼 수정');
    expect(write.body?['expected_version_no'], 4);
    expect(write.body?['items'].single['sort_order'], 0);
    expect(state.recipeUpdated, isTrue);
  });

  testWidgets('deletes a recipe only after confirmation with its version guard',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _FakeRecipeAppState()..recipeCreated = true;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: CostingScreen())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(TabBar),
      matching: find.text('레시피'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('라떼'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('레시피 삭제'));
    await tester.pumpAndSettle();
    expect(
      find.text('삭제 후에는 복구할 수 없습니다. 계속하시겠습니까?'),
      findsOneWidget,
    );
    expect(state.writes, isEmpty);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(state.writes, isEmpty);

    await tester.tap(find.byTooltip('레시피 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('영구 삭제'));
    await tester.pumpAndSettle();

    expect(state.writes, hasLength(1));
    final write = state.writes.single;
    expect(write.endpoint, '/api/costing/recipes/42');
    expect(write.method, 'DELETE');
    expect(write.body?['expected_version_no'], 4);
    expect(
      write.body?['request_id'],
      matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
    );
    expect(state.recipeDeleted, isTrue);
    expect(find.text('새 레시피 등록'), findsOneWidget);
  });
}
