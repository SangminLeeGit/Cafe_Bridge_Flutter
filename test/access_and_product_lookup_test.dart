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
  });
}
