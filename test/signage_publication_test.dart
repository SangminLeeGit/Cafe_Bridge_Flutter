import 'package:cafe_bridge_flutter/screens/signage.dart';
import 'package:cafe_bridge_flutter/services/api.dart';
import 'package:cafe_bridge_flutter/services/cache_store.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _PublicationAppState extends AppState {
  _PublicationAppState({
    this.publishEnabled = true,
    this.publishStatus = 'confirmed',
  });

  final bool publishEnabled;
  final String publishStatus;
  final String reconcileStatus = 'needs-review';
  final List<String> reads = <String>[];
  final List<String> writeEndpoints = <String>[];
  final List<String> writeMethods = <String>[];
  final List<Map<String, dynamic>> writeBodies = <Map<String, dynamic>>[];

  static const Map<String, dynamic> _menu = {
    'shopName': 'Cafe',
    'shopNameLine1': '',
    'shopNameLine2': '',
    'announcement': {'text': 'Welcome'},
    'categories': [
      {
        'id': 'coffee',
        'title': 'Coffee',
        'items': [
          {'korean': 'Latte', 'english': 'Latte', 'price': 4000},
        ],
      },
    ],
  };

  Map<String, dynamic> get _draftEnvelope => {
        'scope_id': 'scope-a',
        'base_remote_hash': 'abcdef0123456789abcdef0123456789',
        'base_menu': _menu,
        'menu': _menu,
        'revision': '3',
        'updated_at': '2026-10-03T00:00:00Z',
      };

  Map<String, dynamic> get _editorContext => {
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
          'publish_signage': {
            'enabled': publishEnabled,
            'reason_code': publishEnabled ? 'ready' : 'capability_disabled',
            'message': publishEnabled ? 'Ready' : '현재 서버에서 외부 게시가 비활성화되어 있습니다.',
          },
        },
      };

  Map<String, dynamic> _publicationRecord(String status, String id) => {
        'publication_id': id,
        'status': status,
        'draft_revision': '3',
        'started_at': '2026-10-03T00:01:00Z',
        'finished_at': '2026-10-03T00:02:00Z',
        if (status == 'rejected' || status == 'failed') ...{
          'error_code': 'remote_changed',
          'error_message': 'remote_changed',
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
      json = _draftEnvelope;
    } else if (endpoint.startsWith('/api/editor/signage/publications/')) {
      final id = endpoint.split('/').last;
      json = _publicationRecord(publishStatus, id);
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
    if (endpoint == '/api/editor/signage/publish') {
      final id = body?['request_id']?.toString() ?? '';
      return _publicationRecord(publishStatus, id);
    }
    if (endpoint.endsWith('/reconcile')) {
      final id = body?['request_id']?.toString() ?? '';
      return _publicationRecord(reconcileStatus, id);
    }
    throw ApiException('unexpected write: $endpoint');
  }
}

Widget _testApp(_PublicationAppState appState) =>
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const MaterialApp(
        home: Scaffold(body: SignageScreen()),
      ),
    );

Future<void> _startPublish(WidgetTester tester) async {
  await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
  await tester.pumpAndSettle();
  final button = find.widgetWithText(FilledButton, '외부 메뉴판 게시');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.text('게시 진행'), findsOneWidget);
  expect(
    find.textContaining('외부 메뉴판이 이 서버 초안의 내용으로 변경됩니다.'),
    findsOneWidget,
  );
  expect(find.text('게시할 서버 초안 revision: 3'), findsOneWidget);
  expect(find.textContaining('Cafe · Coffee: Latte 4,000원'), findsOneWidget);
  await tester.tap(find.text('게시 진행'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('publishing is blocked while the local draft is dirty',
      (tester) async {
    final appState = _PublicationAppState();
    addTearDown(appState.dispose);
    await tester.pumpWidget(_testApp(appState));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Unsaved cafe');
    await tester.pump();
    await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, '외부 메뉴판 게시');
    await tester.ensureVisible(button);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(find.text('로컬 변경사항이 있습니다. 먼저 서버 초안에 저장해 주세요.'), findsOneWidget);
    expect(appState.writeEndpoints, isEmpty);
  });

  testWidgets(
      'publish sends UUID and exact saved-draft preconditions, then confirms',
      (tester) async {
    final appState = _PublicationAppState();
    addTearDown(appState.dispose);
    await tester.pumpWidget(_testApp(appState));
    await tester.pumpAndSettle();

    await _startPublish(tester);

    expect(appState.writeEndpoints, ['/api/editor/signage/publish']);
    expect(appState.writeMethods, ['POST']);
    final body = appState.writeBodies.single;
    expect(
      body['request_id'],
      matches(RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      )),
    );
    expect(body['expected_draft_revision'], '3');
    expect(body['expected_remote_hash'], 'abcdef0123456789abcdef0123456789');
    await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(find.textContaining('외부 메뉴판 게시가 확인되었습니다.'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.textContaining('게시 완료 확인 (confirmed)'), findsOneWidget);
    expect(
      find.text('publication_id: ${body['request_id']}'),
      findsOneWidget,
    );
    expect(find.text('시작 시각: 2026-10-03T00:01:00Z'), findsOneWidget);
    expect(find.text('종료 시각: 2026-10-03T00:02:00Z'), findsOneWidget);
    expect(find.textContaining('외부 메뉴판에 게시됩니다'), findsNothing);
  });

  testWidgets('publish requires the server publish capability', (tester) async {
    final appState = _PublicationAppState(publishEnabled: false);
    addTearDown(appState.dispose);
    await tester.pumpWidget(_testApp(appState));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, '외부 메뉴판 게시');
    await tester.ensureVisible(button);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(
      find.text('현재 서버에서 외부 게시가 비활성화되어 있습니다.'),
      findsOneWidget,
    );
    expect(appState.writeEndpoints, isEmpty);
  });

  testWidgets(
      'ambiguous publication offers lookup and POST reconcile without success',
      (tester) async {
    final appState = _PublicationAppState(publishStatus: 'unknown');
    addTearDown(appState.dispose);
    await tester.pumpWidget(_testApp(appState));
    await tester.pumpAndSettle();

    await _startPublish(tester);
    final publicationId = appState.writeBodies.single['request_id']! as String;
    await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(find.textContaining('외부 메뉴판 게시가 확인되었습니다.'), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.textContaining('외부 게시 결과 미확인 (unknown)'), findsOneWidget);
    expect(find.text('게시 상태 조회'), findsOneWidget);
    expect(find.text('게시 상태 조정'), findsOneWidget);
    expect(find.textContaining('외부 게시 결과는 아직 알 수 없습니다.'), findsOneWidget);

    await tester.tap(find.text('게시 상태 조회'));
    await tester.pumpAndSettle();
    expect(
      appState.reads,
      contains('/api/editor/signage/publications/$publicationId'),
    );

    await tester.tap(find.text('게시 상태 조정'));
    await tester.pumpAndSettle();
    expect(
      appState.writeEndpoints.last,
      '/api/editor/signage/publications/$publicationId/reconcile',
    );
    expect(appState.writeMethods.last, 'POST');
    expect(appState.writeBodies.last, {'request_id': publicationId});
    expect(find.textContaining('게시 결과 검토 필요 (needs-review)'), findsOneWidget);
    expect(find.textContaining('외부 메뉴판 게시가 확인되었습니다.'), findsNothing);
  });
}
