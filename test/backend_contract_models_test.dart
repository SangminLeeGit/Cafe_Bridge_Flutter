import 'package:cafe_bridge_flutter/models/api_contracts.dart';
import 'package:cafe_bridge_flutter/models/costing_models.dart';
import 'package:cafe_bridge_flutter/models/service_health_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('costing models parse backend purchase and recipe fields', () {
    final price = IngredientPrice.fromJson({
      'price_id': 7,
      'ingredient_id': 3,
      'purchase_price': 12000,
      'purchase_qty': 2,
      'purchase_unit': 'kg',
      'usable_qty': 1900,
      'unit_cost': 6.32,
      'effective_from': '2026-08-07',
      'supplier_name': '공급처',
      'memo': '테스트',
    });
    final item = RecipeItem.fromJson({
      'recipe_item_id': 8,
      'recipe_id': 4,
      'ingredient_id': 3,
      'ingredient_name': '원두',
      'ingredient_base_unit': 'g',
      'quantity': 18.5,
      'current_unit_cost': 6.32,
      'line_cost': 117,
      'notes': '',
    });

    expect(price.purchasePrice, 12000);
    expect(price.usableQty, 1900);
    expect(price.effectiveFrom, '2026-08-07');
    expect(price.memo, '테스트');
    expect(item.quantity, 18.5);
  });

  test('audit logs parse event, target, and detail_json fields', () {
    final entry = AuditLogEntryContract.fromJson({
      'id': 11,
      'user_id': 2,
      'login_id': 'admin',
      'event_type': 'user_updated',
      'target': 'viewer',
      'created_at': '2026-08-07T05:00:00Z',
      'detail_json': '{"role":"viewer"}',
    });

    expect(entry.id, '11');
    expect(entry.eventType, 'user_updated');
    expect(entry.target, 'viewer');
    expect(entry.detailJson, '{"role":"viewer"}');
  });

  test('service health snapshot parses settings and targets', () {
    final snapshot = ServiceHealthSnapshot.fromJson({
      'version': '1',
      'generated_at': '2026-08-07T05:00:00Z',
      'settings': [
        {
          'key': 'signage',
          'label': '메뉴판 서버',
          'enabled': true,
          'endpoint': 'https://signage.example/healthz',
          'timeout_ms': 2000,
          'interval_seconds': 60,
          'component_key': null,
          'source': 'environment',
        },
      ],
      'targets': [
        {
          'key': 'signage',
          'label': '메뉴판 서버',
          'enabled': true,
          'endpoint': 'https://signage.example/healthz',
          'component_key': null,
          'state': 'Alive',
          'reason': 'remote_alive',
          'health_status': 'alive',
          'last_checked_at': '2026-08-07T05:00:00Z',
          'response_time_ms': 42,
          'http_status': 200,
          'checks': {
            'time_server': {'status': 'alive'}
          },
          'message': '정상 응답',
        },
      ],
    });

    expect(snapshot.settings.single.key, 'signage');
    expect(snapshot.targets.single.state, 'Alive');
    expect(snapshot.targets.single.responseTimeMs, 42);
    expect(snapshot.targets.single.checks['time_server'], isA<Map>());
  });
}
