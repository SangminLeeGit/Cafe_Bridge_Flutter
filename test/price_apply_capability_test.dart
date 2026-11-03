import 'package:cafe_bridge_flutter/services/api.dart';
import 'package:cafe_bridge_flutter/services/cache_store.dart';
import 'package:cafe_bridge_flutter/screens/price_apply.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _PriceAppState extends AppState {
  final List<Map<String, dynamic>> postedBodies = <Map<String, dynamic>>[];

  static const _editorContext = <String, dynamic>{
    'scope_id': 'scope-price',
    'scope_status': 'configured',
    'role': 'admin',
    'source_ready': true,
    'capabilities': {
      'apply_price': {
        'enabled': false,
        'reason_code': 'capability_disabled',
        'message': 'Verified execution is unavailable.',
        'supported_columns': [],
      },
    },
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
    final Map<String, dynamic> response;
    if (endpoint == '/api/editor/context') {
      response = _editorContext;
    } else if (endpoint == '/api/price/browser-apply-history') {
      response = {'tasks': <dynamic>[]};
    } else if (endpoint == '/api/price/browser-apply/task-preview') {
      response = {
        'task_id': 'task-preview',
        'product_code': '000123',
        'target_price': 4500,
        'target_column': '판매가',
        'execute': false,
        'reason': 'preview',
        'actor': 'tester',
        'status': 'succeeded',
        'result': {
          'product_code': '000123',
          'target_price': 4500,
          'status': 'preview',
          'message': 'Preview ready',
          'execute': false,
          'reason': 'preview',
          'actor': 'tester',
        },
      };
    } else {
      throw ApiException('unexpected read: $endpoint');
    }
    return CachedDataResult<T>(
      data: parser(response),
      fromCache: false,
      cachedAt: DateTime.utc(2026, 10, 3),
    );
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String endpoint, {
    Map<String, dynamic>? body,
    String method = 'POST',
  }) async {
    postedBodies.add(Map<String, dynamic>.from(body ?? const {}));
    return {'task_id': 'task-preview', 'status': 'pending'};
  }

  @override
  Future<String?> readActiveTask(String taskPrefix) async => null;

  @override
  Future<void> saveActiveTask(String taskPrefix, String taskId) async {}

  @override
  Future<void> clearActiveTask(String taskPrefix) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('disabled price capability blocks execute but allows preview',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final appState = _PriceAppState();
    addTearDown(appState.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(
          home: PriceApplyScreen(
            initialProductCode: '000123',
            initialTargetPrice: 4500,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('서버가 가격 실제 반영을 허용하지 않습니다. 현재는 미리보기만 사용할 수 있습니다.'),
        findsOneWidget);
    final applyButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '미리보기만 가능'),
    );
    expect(applyButton.onPressed, isNull);
    expect(appState.postedBodies, isEmpty);

    await tester.ensureVisible(find.text('미리보기'));
    await tester.tap(find.text('미리보기'));
    await tester.pumpAndSettle();
    expect(appState.postedBodies, hasLength(1));
    expect(appState.postedBodies.single['execute'], isFalse);
    expect(appState.postedBodies.where((body) => body['execute'] == true),
        isEmpty);
  });
}
