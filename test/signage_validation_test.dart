import 'package:cafe_bridge_flutter/screens/signage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts comma-formatted signage prices', () {
    expect(parseSignagePrice('1,000'), 1000);
    expect(parseSignagePrice(2500), 2500);
  });

  test('rejects malformed signage prices', () {
    expect(parseSignagePrice('12원'), isNull);
    expect(parseSignagePrice('1.5'), isNull);
  });
}
