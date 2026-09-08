class ProductIdentity {
  final String code;
  final String name;
  final int? salePrice;
  final String category;

  const ProductIdentity({
    required this.code,
    required this.name,
    required this.salePrice,
    required this.category,
  });

  factory ProductIdentity.fromRegistrationJson(
    Map<String, dynamic> json, {
    List<String> priceFields = const ['판매가', 'sale_price', 'target_price'],
  }) {
    final major =
        (json['대분류명'] ?? json['major_category'] ?? '').toString().trim();
    final middle =
        (json['중분류명'] ?? json['middle_category'] ?? '').toString().trim();
    return ProductIdentity(
      code: normalizeProductCode(
        (json['상품코드'] ?? json['item_code'] ?? '').toString(),
      ),
      name: (json['상품명'] ?? json['item_name'] ?? '').toString(),
      salePrice: parseProductPrice(_firstPresentValue(json, priceFields)),
      category: [major, middle].where((value) => value.isNotEmpty).join(' > '),
    );
  }
}

Object? _firstPresentValue(Map<String, dynamic> json, List<String> fields) {
  for (final field in fields) {
    final value = json[field];
    if (value != null) {
      return value;
    }
  }
  return null;
}

String normalizeProductCode(String value) {
  final code = value.trim();
  if (code.isNotEmpty && RegExp(r'^\d+$').hasMatch(code) && code.length < 6) {
    return code.padLeft(6, '0');
  }
  return code;
}

int? parseProductPrice(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse((value ?? '').toString().replaceAll(',', '').trim());
}
