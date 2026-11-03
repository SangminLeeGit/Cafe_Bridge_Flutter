import 'package:cafe_bridge_flutter/models/product_identity.dart';
import 'package:cafe_bridge_flutter/screens/product_lookup.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:cafe_bridge_flutter/widgets/access_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AccessGate role order', () {
    test('viewer access does not include operator actions', () {
      expect(
        AccessGate.roleAllows(UserRole.viewer, UserRole.viewer),
        isTrue,
      );
      expect(
        AccessGate.roleAllows(UserRole.viewer, UserRole.operator),
        isFalse,
      );
    });

    test('admin includes every lower role', () {
      expect(
        AccessGate.roleAllows(UserRole.admin, UserRole.viewer),
        isTrue,
      );
      expect(
        AccessGate.roleAllows(UserRole.admin, UserRole.operator),
        isTrue,
      );
      expect(
        AccessGate.roleAllows(UserRole.admin, UserRole.admin),
        isTrue,
      );
    });
  });

  group('product lookup parsing', () {
    test('numeric product codes are displayed with six digits', () {
      expect(normalizeProductCode('123'), '000123');
      expect(normalizeProductCode(' 001234 '), '001234');
      expect(normalizeProductCode('ABC-1'), 'ABC-1');
    });

    test('accepts integral numeric prices without accepting fractions', () {
      expect(
        ProductIdentity.fromRegistrationJson(
          {'product_code': '42', 'editor_price': 4500.0},
          priceFields: const ['editor_price'],
        ).salePrice,
        4500,
      );
      expect(parseProductPrice('4500.25'), isNull);
    });

    test('registration rows parse Korean API fields', () {
      final item = ProductLookupItem.fromJson({
        '상품코드': '42',
        '상품명': '아메리카노',
        '판매가': '4,500',
        '대분류명': '음료',
        '중분류명': '커피',
      });

      expect(item.code, '000042');
      expect(item.name, '아메리카노');
      expect(item.salePrice, 4500);
      expect(item.category, '음료 > 커피');
    });

    test('registration rows accept English API fields with the same identity',
        () {
      final item = ProductLookupItem.fromJson({
        'item_code': '42',
        'item_name': 'Americano',
        'sale_price': '4,500',
        'major_category': 'Drinks',
        'middle_category': 'Coffee',
      });

      expect(item.code, '000042');
      expect(item.name, 'Americano');
      expect(item.salePrice, 4500);
      expect(item.category, 'Drinks > Coffee');
    });

    test('callers can preserve their price field precedence', () {
      final identity = ProductIdentity.fromRegistrationJson(
        {
          'sale_price': 3500,
          'target_price': 4000,
        },
        priceFields: const ['판매가', 'target_price', 'sale_price'],
      );

      expect(identity.salePrice, 4000);
      expect(
        ProductIdentity.fromRegistrationJson(
          {'sale_price': 3500, 'target_price': 4000},
        ).salePrice,
        3500,
      );
    });
  });
}
