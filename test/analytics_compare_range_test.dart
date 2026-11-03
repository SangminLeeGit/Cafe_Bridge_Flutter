import 'package:cafe_bridge_flutter/services/cache_store.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:cafe_bridge_flutter/screens/analytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _CompareAppState extends AppState {
  final List<Map<String, Object?>?> compareParams = [];

  @override
  Future<CachedDataResult<T>> fetchMapParsed<T>(
    String endpoint, {
    Map<String, Object?>? params,
    required T Function(Map<String, dynamic> json) parser,
    Duration cacheTtl = const Duration(minutes: 30),
    bool allowStaleOnError = true,
    ApiCachePolicy? cachePolicy,
  }) async {
    if (endpoint != '/api/compare') {
      throw StateError('Unexpected endpoint: $endpoint');
    }
    compareParams
        .add(params == null ? null : Map<String, Object?>.from(params));
    final response = {
      'error': '',
      'a': {
        'from': params?['a_from'],
        'to': params?['a_to'],
        'days': [],
        'top_items': [],
      },
      'b': {
        'from': params?['b_from'],
        'to': params?['b_to'],
        'days': [],
        'top_items': [],
      },
      'deltas': {},
    };
    return CachedDataResult<T>(
      data: parser(response),
      fromCache: false,
      cachedAt: DateTime.now(),
    );
  }
}

DateTime _date(Map<String, Object?> params, String key) =>
    DateTime.parse(params[key]! as String);

void _expectPreviousEqualLengthRange(Map<String, Object?> params) {
  final aFrom = _date(params, 'a_from');
  final aTo = _date(params, 'a_to');
  final bFrom = _date(params, 'b_from');
  final bTo = _date(params, 'b_to');
  expect(bTo.add(const Duration(days: 1)), aFrom);
  expect(bTo.difference(bFrom), aTo.difference(aFrom));
}

String _dateInput(DateTime date) => '${date.month}/${date.day}/${date.year}';

void main() {
  testWidgets('compare period B can be selected independently and reset',
      (tester) async {
    final state = _CompareAppState();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(body: AnalyticsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('비교'));
    await tester.pumpAndSettle();
    expect(state.compareParams, isNotEmpty);
    final initialParams = state.compareParams.last!;
    _expectPreviousEqualLengthRange(initialParams);

    await tester.tap(find.widgetWithText(OutlinedButton, '비교 기간 B'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();

    final initialAStart = _date(initialParams, 'a_from');
    final selectedBStart = initialAStart.subtract(const Duration(days: 30));
    final selectedBEnd = initialAStart.subtract(const Duration(days: 28));
    final dateFields = find.byType(TextField);
    expect(dateFields, findsNWidgets(2));
    await tester.enterText(dateFields.at(0), _dateInput(selectedBStart));
    await tester.enterText(dateFields.at(1), _dateInput(selectedBEnd));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextButton).last);
    await tester.pumpAndSettle();

    final independentParams = state.compareParams.last!;
    expect(
        independentParams['b_from'],
        '${selectedBStart.year}-'
        '${selectedBStart.month.toString().padLeft(2, '0')}-'
        '${selectedBStart.day.toString().padLeft(2, '0')}');
    expect(
        independentParams['b_to'],
        '${selectedBEnd.year}-'
        '${selectedBEnd.month.toString().padLeft(2, '0')}-'
        '${selectedBEnd.day.toString().padLeft(2, '0')}');
    expect(independentParams['b_to'], isNot(initialParams['b_to']));

    await tester.tap(find.text('직전 동일 기간'));
    await tester.pumpAndSettle();
    _expectPreviousEqualLengthRange(state.compareParams.last!);
  });
}
