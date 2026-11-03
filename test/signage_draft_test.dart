import 'package:cafe_bridge_flutter/screens/signage.dart';
import 'package:cafe_bridge_flutter/services/api.dart';
import 'package:cafe_bridge_flutter/services/cache_store.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _SignageAppState extends AppState {
  _SignageAppState({
    this.loseFirstWriteResponse = false,
    this.conflictOnFirstWrite = false,
  });

  final bool loseFirstWriteResponse;
  final bool conflictOnFirstWrite;
  final List<String> reads = <String>[];
  final List<String> writeEndpoints = <String>[];
  final List<String> writeMethods = <String>[];
  final List<Map<String, dynamic>> writeBodies = <Map<String, dynamic>>[];
  int draftReads = 0;

  static const Map<String, dynamic> _menu = {
    'vendor_schema': {'revision': 4},
    'shopName': 'Cafe',
    'shopNameLine1': '',
    'shopNameLine2': '',
    'announcement': {'text': 'Welcome', 'pos_display': true},
    'categories': [
      {
        'id': 'coffee',
        'title': 'Coffee',
        'description': '',
        'layout_hint': 'two-column',
        'items': [
          {
            'korean': 'Latte',
            'english': 'Latte',
            'price': 4000,
            'note': '',
            'sku': 'sku-latte',
          },
        ],
      },
    ],
  };

  Map<String, dynamic> _draftEnvelope({
    String revision = '3',
    Map<String, dynamic>? menu,
  }) =>
      {
        'scope_id': 'scope-a',
        'base_remote_hash': 'abcdef0123456789abcdef0123456789',
        'base_menu': _menu,
        'menu': menu ?? _menu,
        'revision': revision,
        'updated_at': '2026-10-03T00:00:00Z',
      };

  static const Map<String, dynamic> _editorContext = {
    'scope_id': 'scope-a',
    'scope_status': 'configured',
    'role': 'operator',
    'source_ready': true,
    'capabilities': {
      'save_signage_draft': {
        'enabled': true,
        'reason_code': 'ready',
        'message': 'Ready',
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
    reads.add(endpoint);
    late final Map<String, dynamic> json;
    if (endpoint == '/api/editor/context') {
      json = _editorContext;
    } else if (endpoint == '/api/editor/signage/draft') {
      draftReads += 1;
      json = conflictOnFirstWrite && draftReads > 1
          ? _draftEnvelope(
              revision: '4',
              menu: {..._menu, 'shopName': 'Remote updated'},
            )
          : _draftEnvelope();
    } else if (endpoint.startsWith('/api/editor/write-receipts/')) {
      throw const ApiException('receipt not found', statusCode: 404);
    } else {
      throw ApiException('unexpected read: $endpoint');
    }
    return CachedDataResult<T>(
      data: parser(json),
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
    writeEndpoints.add(endpoint);
    writeMethods.add(method);
    writeBodies.add(Map<String, dynamic>.from(body ?? const {}));
    if (loseFirstWriteResponse && writeBodies.length == 1) {
      throw const ApiException('connection lost', isTransportError: true);
    }
    if (conflictOnFirstWrite && writeBodies.length == 1) {
      throw const ApiException(
        'draft changed',
        statusCode: 409,
        code: 'draft_changed',
      );
    }
    return _draftEnvelope(
      revision: conflictOnFirstWrite ? '5' : '4',
      menu: Map<String, dynamic>.from((body?['menu'] as Map?) ?? const {}),
    );
  }
}

Widget _testApp(_SignageAppState appState) =>
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const MaterialApp(
        home: Scaffold(body: SignageScreen()),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('saves an immutable versioned server draft, not a publication',
      (tester) async {
    final appState = _SignageAppState();
    addTearDown(appState.dispose);
    await tester.pumpWidget(_testApp(appState));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Cafe updated');
    await tester.pump();
    await tester.tap(find.text('서버 초안 저장'));
    await tester.pumpAndSettle();

    expect(appState.writeEndpoints, ['/api/editor/signage/draft']);
    expect(appState.writeMethods, ['PUT']);
    final body = appState.writeBodies.single;
    expect(body['expected_revision'], '3');
    expect(body['base_remote_hash'], 'abcdef0123456789abcdef0123456789');
    expect(
        body['request_id'],
        matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        )));
    final menu = Map<String, dynamic>.from(body['menu'] as Map);
    expect(menu['shopName'], 'Cafe updated');
    expect(menu['vendor_schema'], {'revision': 4});
    expect((menu['announcement'] as Map)['pos_display'], isTrue);
    final category = (menu['categories'] as List).single as Map;
    expect(category['layout_hint'], 'two-column');
    expect((category['items'] as List).single['sku'], 'sku-latte');
    expect(find.textContaining('외부 메뉴판에는 게시되지 않았습니다'), findsOneWidget);
    expect(appState.writeEndpoints, isNot(contains('/api/signage/menu')));
  });

  testWidgets('dirty refresh cancellation preserves local edits',
      (tester) async {
    final appState = _SignageAppState();
    addTearDown(appState.dispose);
    await tester.pumpWidget(_testApp(appState));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Unsaved change');
    await tester.pump();
    await tester.tap(find.text('새로고침'));
    await tester.pumpAndSettle();
    expect(find.text('로컬 변경사항 새로고침'), findsOneWidget);
    await tester.tap(find.text('계속 편집'));
    await tester.pumpAndSettle();

    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Unsaved change');
    expect(appState.draftReads, 1);
  });

  testWidgets('ambiguous save retries the identical request ID and payload',
      (tester) async {
    final appState = _SignageAppState(loseFirstWriteResponse: true);
    addTearDown(appState.dispose);
    await tester.pumpWidget(_testApp(appState));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Retry cafe');
    await tester.pump();
    await tester.tap(find.text('서버 초안 저장'));
    await tester.pumpAndSettle();
    expect(appState.writeBodies, hasLength(1));
    expect(
        appState.reads
            .where((path) => path.startsWith('/api/editor/write-receipts/')),
        hasLength(1));

    await tester.tap(find.text('서버 초안 저장'));
    await tester.pumpAndSettle();
    expect(appState.writeBodies, hasLength(2));
    expect(appState.writeBodies[1], appState.writeBodies[0]);
    expect(appState.writeMethods, ['PUT', 'PUT']);
    expect(find.textContaining('외부 메뉴판에는 게시되지 않았습니다'), findsOneWidget);
  });

  testWidgets('revision conflict keeps local edits until explicit comparison',
      (tester) async {
    final appState = _SignageAppState(conflictOnFirstWrite: true);
    addTearDown(appState.dispose);
    await tester.pumpWidget(_testApp(appState));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'My local draft');
    await tester.pump();
    await tester.tap(find.text('서버 초안 저장'));
    await tester.pumpAndSettle();

    expect(find.text('서버 초안 충돌 비교'), findsOneWidget);
    expect(find.textContaining('My local draft'), findsOneWidget);
    expect(find.textContaining('Remote updated'), findsOneWidget);

    await tester.tap(find.text('비교한 서버 버전 기준으로 계속 편집'));
    await tester.pumpAndSettle();
    expect(find.textContaining('로컬 초안은 유지'), findsOneWidget);
    await tester.tap(find.text('서버 초안 저장'));
    await tester.pumpAndSettle();

    expect(appState.writeBodies, hasLength(2));
    expect(appState.writeBodies[1]['expected_revision'], '4');
    expect(
        (appState.writeBodies[1]['menu'] as Map)['shopName'], 'My local draft');
  });
}
