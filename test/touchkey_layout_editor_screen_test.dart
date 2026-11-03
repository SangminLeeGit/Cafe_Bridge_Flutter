import 'package:cafe_bridge_flutter/screens/touchkey_layout_editor.dart';
import 'package:cafe_bridge_flutter/services/cache_store.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeAppState extends AppState {
  _FakeAppState();

  final List<({String endpoint, Map<String, Object?>? params})> reads = [];
  String? writeEndpoint;
  String? writeMethod;
  Map<String, dynamic>? writeBody;

  @override
  bool get hasOperatorAccess => true;

  Map<String, dynamic> _envelope(String code, String revision) => {
        'scope_id': 'scope-a',
        'definition': {
          'layout_id': 'touchkey-layout-a',
          'class_code': '01',
          'sort_value': '1',
          'page': 1,
          'columns': 1,
          'rows': 1,
          'complete': true,
          'issues': [],
        },
        'base': {
          'snapshot_id': 'base-snapshot-a',
          'revision': '0',
          'complete': true,
          'placements': {'1:1': '100'},
          'issues': [],
        },
        'saved': {
          'snapshot_id': 'saved-snapshot-$revision',
          'revision': revision,
          'complete': true,
          'placements': {'1:1': code},
          'issues': [],
        },
        'products': {
          '100': {
            'product_code': '100',
            'name': '아메리카노',
            'price': 4500,
            'placeable': true,
          },
          '200': {
            'product_code': '200',
            'name': '라떼',
            'price': 5000,
            'placeable': true,
          },
        },
        'capabilities': {
          'edit': {'enabled': true, 'reasons': []},
          'apply': {
            'enabled': false,
            'reasons': ['capability_disabled']
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
    reads.add((endpoint: endpoint, params: params));
    final Map<String, dynamic> json;
    if (endpoint == '/api/editor/context') {
      json = {
        'scope_id': 'scope-a',
        'capabilities': {
          'save_touchkey_draft': {'enabled': true, 'reason_code': 'ready'},
        },
      };
    } else if (endpoint == '/api/editor/touchkey/layout') {
      json = _envelope('100', '4');
    } else {
      throw StateError('unexpected endpoint $endpoint');
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
    writeEndpoint = endpoint;
    writeMethod = method;
    writeBody = body;
    return _envelope('200', '5');
  }
}

void main() {
  testWidgets('edits and saves a versioned local touchkey draft only',
      (tester) async {
    final state = _FakeAppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(
          home: TouchkeyLayoutEditorScreen(
            classCode: '01',
            sortValue: '1',
            className: '커피',
            page: 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('아메리카노'), findsOneWidget);
    await tester.tap(find.text('아메리카노'));
    await tester.pumpAndSettle();
    expect(find.text('라떼'), findsOneWidget);
    await tester.tap(find.text('라떼'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('서버 초안 저장'));
    await tester.pumpAndSettle();

    expect(
        state.writeEndpoint, '/api/editor/touchkey/layouts/touchkey-layout-a');
    expect(state.writeMethod, 'PUT');
    expect(state.writeBody?['expected_revision'], '4');
    expect(state.writeBody?['base_snapshot_id'], 'base-snapshot-a');
    expect(state.writeBody?['slots'], [
      {'h': 1, 'v': 1, 'product_code': '200'},
    ]);
    expect(find.text('서버 초안을 저장했습니다. POS 변경은 실행하지 않았습니다.'), findsOneWidget);
  });
}
