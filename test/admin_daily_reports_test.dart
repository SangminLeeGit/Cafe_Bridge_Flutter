import 'package:cafe_bridge_flutter/screens/admin_daily_reports.dart';
import 'package:cafe_bridge_flutter/services/api.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _recipientId = '123e4567-e89b-12d3-a456-426614174000';
const _reportId = '123e4567-e89b-12d3-a456-426614174001';

class _TestAppState extends AppState {
  _TestAppState({required this.admin});

  final bool admin;

  @override
  bool canAccess(UserRole requiredRole) =>
      admin && requiredRole == UserRole.admin;
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.endpoint,
    required this.method,
    this.params,
    this.body,
  });

  final String endpoint;
  final String method;
  final Map<String, Object?>? params;
  final Map<String, dynamic>? body;
}

Widget _app({
  required AppState state,
  required DailyReportsAdminRequest request,
  Duration codexPollingInterval = const Duration(hours: 1),
  Duration runPollingInterval = const Duration(hours: 1),
}) {
  return ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      home: AdminDailyReportsScreen(
        requestJson: request,
        codexPollingInterval: codexPollingInterval,
        runPollingInterval: runPollingInterval,
      ),
    ),
  );
}

Future<void> _scrollToVisible(WidgetTester tester, Finder finder) async {
  final scrollable = find.descendant(
    of: find.byType(RefreshIndicator),
    matching: find.byType(Scrollable),
  ).first;
  await tester.scrollUntilVisible(
    finder,
    400,
    scrollable: scrollable,
  );
}

Future<void> _scrollToTop(WidgetTester tester) async {
  final scrollable = find.descendant(
    of: find.byType(RefreshIndicator),
    matching: find.byType(Scrollable),
  ).first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pumpAndSettle();
}

Map<String, dynamic> _settings() => {
      'enabled': true,
      'auto_sync_enabled': true,
      'schedule_time': '08:30',
      'previous_day_collection_time': '23:30',
      'collection_interval_minutes': 30,
      'timezone': 'Asia/Seoul',
      'weekdays': ['mon', 'tue', 'wed', 'thu', 'fri'],
      'telegram_enabled': true,
      'telegram_recipients': [
        {
          'recipient_id': _recipientId,
          'label': 'Cafe 운영',
          'chat_id': '-1001234567890',
          'enabled': true,
        },
      ],
      'title_template': 'Cafe Bridge 일일보고서 ({business_date})',
      'message_template': '{report_body}',
      'sections': ['report_metadata', 'executive_summary', 'key_metrics'],
      'collection_sources': ['sales'],
      'llm_enabled': true,
      'llm_provider': 'openai_codex',
      'llm_targets': ['summary'],
      'llm_model': '',
      'llm_system_prompt': '',
      'llm_max_output_tokens': 1200,
      'llm_reasoning_effort': 'medium',
      'detail_level': 'standard',
      'lookback_days': 28,
      'comparison_periods': ['previous_day', 'same_weekday'],
      'thresholds': {
        'sales_change_pct': 20.0,
        'order_change_pct': 20.0,
        'customer_change_pct': 20.0,
        'avg_ticket_change_pct': 15.0,
        'cancellation_rate_pct': 5.0,
        'item_concentration_pct': 50.0,
        'no_sale_hours': 2,
        'peak_shift_hours': 2,
        'repeated_pattern_days': 3,
        'min_comparison_samples': 2,
        'min_cancel_count': 2,
        'stock_cover_days': 1,
      },
      'store_profiles': {
        'default': {
          'display_name': '기본 매장',
          'operating_hours_configured': false,
          'open_time': '10:00',
          'close_time': '19:30',
          'closed_weekdays': [6, 7],
          'holidays': <String>[],
          'size': '',
          'menu_items': <String>[],
          'important_metrics': ['gross_amount', 'receipt_count'],
          'thresholds': <String, double>{},
        },
      },
      'alert_min_severity': 'low',
      'alert_min_confidence': 'low',
      'active_analysis_enabled': true,
      'max_input_records': 200,
      'retry_count': 3,
      'retry_interval_seconds': 2,
      'request_timeout_seconds': 45,
      'message_split_limit': 3500,
      'failure_notifications_enabled': true,
      'partial_failure_reporting': true,
      'send_when_no_data': false,
    };

Map<String, dynamic> _settingsResponse([Map<String, dynamic>? settings]) => {
      'version': 7,
      'settings': settings ?? _settings(),
      'secret_status': {
        'telegram_bot_token': {
          'configured': true,
          'masked': '***never-render-this***',
          'source': 'keyring',
        },
        'opencode_go_api_token': {
          'configured': false,
          'masked': '',
          'source': 'missing',
        },
      },
    };

Map<String, dynamic> _providersResponse() => {
      'providers': [
        {
          'id': 'openai_codex',
          'name': 'OpenAI Codex',
          'enabled': true,
          'available': true,
        },
        {
          'id': 'opencode_go',
          'name': 'OpenCode',
          'enabled': true,
          'available': true,
        },
      ],
      'codex_auth': {
        'status': 'authenticated',
        'configured': true,
        'auth_method': 'chatgpt',
        'source': 'codex_session',
      },
    };

Map<String, dynamic> _notFoundCodexLogin() => {
      'flow_id': '',
      'status': 'not_found',
      'method': '',
      'auth_url': '',
      'verification_url': '',
      'user_code': '',
      'message': '',
      'expires_in_seconds': 0,
    };

Map<String, dynamic> _run({
  String id = 'run-1',
  String status = 'succeeded',
  String reportId = _reportId,
  List<Map<String, dynamic>> deliveries = const [],
}) =>
    {
      'id': id,
      'report_id': reportId,
      'target_date': '2026-11-21',
      'status': status,
      'trigger': 'manual',
      'requested_by': 'admin',
      'created_at': '2026-11-21T03:00:00Z',
      'started_at': '2026-11-21T03:00:01Z',
      'finished_at': status == 'succeeded' ? '2026-11-21T03:01:00Z' : null,
      'records_collected': 42,
      'attempts': 1,
      'current_step': status == 'running' ? 'collecting' : 'completed',
      'error_message': '',
      'warning_message': '',
      'delivery_status': 'sent',
      'delivery_summary': {
        'total': deliveries.length,
        'sent': deliveries.where((item) => item['status'] == 'sent').length,
        'failed': 0,
        'partial_failed': 0,
        'ambiguous': 0,
        'skipped': 0,
        'pending': 0,
        'sending': 0,
      },
      'deliveries': deliveries,
      'external_calls': <Map<String, dynamic>>[],
      'report': {
        'title': '11월 21일 일일보고서',
        'content': '오늘의 매출 요약',
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('non-admin users cannot load the admin API', (tester) async {
    final state = _TestAppState(admin: false);
    addTearDown(state.dispose);
    final calls = <_RecordedRequest>[];

    Future<Map<String, dynamic>> request(
      String endpoint, {
      required String method,
      Map<String, Object?>? params,
      Map<String, dynamic>? body,
    }) async {
      calls.add(_RecordedRequest(
        endpoint: endpoint,
        method: method,
        params: params,
        body: body,
      ));
      return {};
    }

    await tester.pumpWidget(_app(state: state, request: request));
    await tester.pumpAndSettle();

    expect(find.textContaining('필요 권한: admin'), findsOneWidget);
    expect(calls, isEmpty);
  });

  testWidgets('validates and saves versioned scheduler settings',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _TestAppState(admin: true);
    addTearDown(state.dispose);
    final calls = <_RecordedRequest>[];

    Future<Map<String, dynamic>> request(
      String endpoint, {
      required String method,
      Map<String, Object?>? params,
      Map<String, dynamic>? body,
    }) async {
      calls.add(_RecordedRequest(
        endpoint: endpoint,
        method: method,
        params: params,
        body: body,
      ));
      if (endpoint.endsWith('/settings') && method == 'GET') {
        return _settingsResponse();
      }
      if (endpoint.endsWith('/settings/validate')) {
        return {'valid': true, 'errors': [], 'warnings': []};
      }
      if (endpoint.endsWith('/settings') && method == 'PUT') {
        return _settingsResponse(
          Map<String, dynamic>.from(body!['settings'] as Map),
        )..['version'] = 8;
      }
      if (endpoint.endsWith('/providers')) return _providersResponse();
      if (endpoint.endsWith('/auth/codex/login')) {
        return _notFoundCodexLogin();
      }
      if (endpoint.endsWith('/runs')) return {'runs': <dynamic>[]};
      if (endpoint.endsWith('/audits')) return {'audits': <dynamic>[]};
      throw StateError('Unexpected request: $method $endpoint');
    }

    await tester.pumpWidget(_app(state: state, request: request));
    await tester.pumpAndSettle();

    final intervalField =
        find.byKey(const ValueKey('settings-collection_interval_minutes-1'));
    await _scrollToVisible(tester, intervalField);
    await tester.enterText(intervalField, '10.5');
    await _scrollToVisible(tester, find.text('설정 검증'));
    await tester.tap(find.text('설정 검증'));
    await tester.pumpAndSettle();
    await _scrollToTop(tester);
    await _scrollToVisible(tester, find.text('정수로 입력하세요.'));
    expect(find.text('정수로 입력하세요.'), findsOneWidget);
    expect(
      calls.where((call) => call.endpoint.endsWith('/settings/validate')),
      isEmpty,
    );

    await tester.enterText(intervalField, '31');
    final scheduleField =
        find.byKey(const ValueKey('settings-schedule_time-1'));
    await _scrollToVisible(tester, scheduleField);
    await tester.enterText(scheduleField, '09:15');
    await _scrollToVisible(tester, find.text('토'));
    await tester.tap(find.text('토'));
    await _scrollToVisible(tester, find.text('설정 검증'));
    await tester.tap(find.text('설정 검증'));
    await tester.pumpAndSettle();

    final validationRequest =
        calls.lastWhere((call) => call.endpoint.endsWith('/settings/validate'));
    final validationBody = validationRequest.body!;
    final validationProfile =
        (validationBody['store_profiles'] as Map)['default'] as Map;
    expect(validationRequest.method, 'POST');
    expect(validationBody['schedule_time'], '09:15');
    expect(validationBody['collection_interval_minutes'], 31);
    expect(validationBody['weekdays'], contains('sat'));
    expect(validationProfile['closed_weekdays'], [7]);
    await _scrollToTop(tester);
    expect(find.text('설정 검증을 통과했습니다.'), findsOneWidget);

    await _scrollToVisible(tester, find.text('설정 저장'));
    await tester.tap(find.text('설정 저장'));
    await tester.pumpAndSettle();

    final saveRequest =
        calls.lastWhere((call) => call.endpoint.endsWith('/settings') &&
            call.method == 'PUT');
    final savedSettings = saveRequest.body!['settings'] as Map;
    final savedProfile =
        (savedSettings['store_profiles'] as Map)['default'] as Map;
    expect(saveRequest.body?['expected_version'], 7);
    expect(savedSettings['schedule_time'], '09:15');
    expect(savedProfile['operating_hours_configured'], isTrue);
    expect(find.textContaining('설정됨'), findsWidgets);
    expect(find.text('***never-render-this***'), findsNothing);
  });

  testWidgets('manual runs and active-run cancellation use admin routes',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _TestAppState(admin: true);
    addTearDown(state.dispose);
    final calls = <_RecordedRequest>[];
    var runStatus = 'running';
    Map<String, dynamic>? manualRunBody;

    Future<Map<String, dynamic>> request(
      String endpoint, {
      required String method,
      Map<String, Object?>? params,
      Map<String, dynamic>? body,
    }) async {
      calls.add(_RecordedRequest(
        endpoint: endpoint,
        method: method,
        params: params,
        body: body,
      ));
      if (endpoint.endsWith('/settings')) return _settingsResponse();
      if (endpoint.endsWith('/providers')) return _providersResponse();
      if (endpoint.endsWith('/auth/codex/login')) {
        return _notFoundCodexLogin();
      }
      if (endpoint.endsWith('/runs/run-1/cancel')) {
        runStatus = 'cancelled';
        return {'run': _run(status: runStatus)};
      }
      if (endpoint.endsWith('/runs') && method == 'POST') {
        manualRunBody = body;
        return {'run': _run(id: 'run-2', status: 'running')};
      }
      if (endpoint.endsWith('/runs/run-2')) {
        return {'run': _run(id: 'run-2', status: 'running')};
      }
      if (endpoint.endsWith('/runs/run-1')) {
        return {'run': _run(status: runStatus)};
      }
      if (endpoint.endsWith('/runs')) {
        return {
          'runs': [
            {
              'id': 'run-1',
              'report_id': _reportId,
              'target_date': '2026-11-21',
              'status': runStatus,
              'trigger': 'manual',
              'created_at': '2026-11-21T03:00:00Z',
            },
          ],
        };
      }
      if (endpoint.endsWith('/audits')) return {'audits': <dynamic>[]};
      throw StateError('Unexpected request: $method $endpoint');
    }

    await tester.pumpWidget(_app(state: state, request: request));
    await tester.pumpAndSettle();

    final runTile = find.text('2026-11-21');
    await _scrollToVisible(tester, runTile);
    await tester.tap(runTile);
    await tester.pumpAndSettle();
    expect(find.text('오늘의 매출 요약'), findsOneWidget);

    await _scrollToVisible(tester, find.text('실행 취소'));
    await tester.tap(find.text('실행 취소'));
    await tester.pumpAndSettle();

    expect(runStatus, 'cancelled');
    expect(
      calls.any((call) =>
          call.endpoint.endsWith('/runs/run-1/cancel') &&
          call.method == 'POST'),
      isTrue,
    );

    await _scrollToVisible(tester, find.text('보고서 실행'));
    await tester.tap(find.text('보고서 실행'));
    await tester.pumpAndSettle();
    expect(
      manualRunBody?['target_date'],
      matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
    );
    expect(
      manualRunBody?['request_id'],
      matches(RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      )),
    );
    expect(manualRunBody?['reason'], 'Flutter 관리자 수동 실행');
  });

  testWidgets('Codex login cancellation stops the pending polling flow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _TestAppState(admin: true);
    addTearDown(state.dispose);
    final calls = <_RecordedRequest>[];

    Future<Map<String, dynamic>> request(
      String endpoint, {
      required String method,
      Map<String, Object?>? params,
      Map<String, dynamic>? body,
    }) async {
      calls.add(_RecordedRequest(
        endpoint: endpoint,
        method: method,
        params: params,
        body: body,
      ));
      if (endpoint.endsWith('/settings')) return _settingsResponse();
      if (endpoint.endsWith('/providers')) return _providersResponse();
      if (endpoint.endsWith('/auth/codex/login') && method == 'GET') {
        return _notFoundCodexLogin();
      }
      if (endpoint.endsWith('/auth/codex/login') && method == 'POST') {
        return {
          'flow_id': 'flow-1',
          'status': 'pending',
          'method': 'device_code',
          'auth_url': '',
          'verification_url': 'https://login.example.test/device',
          'user_code': 'ABCD-EFGH',
          'message': 'Continue in your browser',
          'expires_in_seconds': 300,
        };
      }
      if (endpoint.endsWith('/flow-1/cancel') && method == 'POST') {
        return {
          'flow_id': 'flow-1',
          'status': 'cancelled',
          'method': 'device_code',
          'auth_url': '',
          'verification_url': '',
          'user_code': '',
          'message': 'Cancelled',
          'expires_in_seconds': 0,
        };
      }
      if (endpoint.endsWith('/runs')) return {'runs': <dynamic>[]};
      if (endpoint.endsWith('/audits')) return {'audits': <dynamic>[]};
      throw StateError('Unexpected request: $method $endpoint');
    }

    await tester.pumpWidget(_app(
      state: state,
      request: request,
      codexPollingInterval: const Duration(seconds: 30),
    ));
    await tester.pumpAndSettle();

    await _scrollToVisible(tester, find.text('디바이스 로그인'));
    await tester.tap(find.text('디바이스 로그인'));
    await tester.pumpAndSettle();
    expect(find.text('ABCD-EFGH'), findsOneWidget);
    expect(find.text('로그인 URL 복사'), findsOneWidget);

    await _scrollToVisible(tester, find.text('로그인 취소'));
    await tester.tap(find.text('로그인 취소'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 31));

    expect(
      calls.any((call) =>
          call.endpoint.endsWith('/flow-1/cancel') &&
          call.method == 'POST'),
      isTrue,
    );
    expect(
      calls.where((call) =>
          call.method == 'GET' &&
          call.endpoint.endsWith('/auth/codex/login/flow-1')),
      isEmpty,
    );
    expect(find.textContaining('취소됨'), findsOneWidget);
  });

  testWidgets('resend with prior delivery requires duplicate confirmation',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _TestAppState(admin: true);
    addTearDown(state.dispose);
    final calls = <_RecordedRequest>[];
    Map<String, dynamic>? resendBody;
    final run = _run(deliveries: [
      {
        'delivery_id': 'delivery-1',
        'recipient_id': _recipientId,
        'recipient_label': 'Cafe 운영',
        'target_masked': '***7890',
        'status': 'sent',
        'chunk_count': 1,
        'sent_count': 1,
      },
    ]);

    Future<Map<String, dynamic>> request(
      String endpoint, {
      required String method,
      Map<String, Object?>? params,
      Map<String, dynamic>? body,
    }) async {
      calls.add(_RecordedRequest(
        endpoint: endpoint,
        method: method,
        params: params,
        body: body,
      ));
      if (endpoint.endsWith('/settings')) return _settingsResponse();
      if (endpoint.endsWith('/providers')) return _providersResponse();
      if (endpoint.endsWith('/auth/codex/login')) {
        return _notFoundCodexLogin();
      }
      if (endpoint.contains('/runs/')) {
        final id = endpoint.split('/').last;
        return {
          'run': id == 'run-1' ? run : _run(id: id, status: 'pending'),
        };
      }
      if (endpoint.endsWith('/runs')) {
        return {
          'runs': [
            {
              'id': 'run-1',
              'report_id': _reportId,
              'target_date': '2026-11-21',
              'status': 'succeeded',
              'trigger': 'manual',
              'created_at': '2026-11-21T03:00:00Z',
            },
          ],
        };
      }
      if (endpoint.endsWith('/resend')) {
        resendBody = body;
        return {'run': _run(id: 'run-resend', status: 'pending')};
      }
      if (endpoint.endsWith('/audits')) return {'audits': <dynamic>[]};
      throw StateError('Unexpected request: $method $endpoint');
    }

    await tester.pumpWidget(_app(state: state, request: request));
    await tester.pumpAndSettle();
    final runTile = find.text('2026-11-21');
    await _scrollToVisible(tester, runTile);
    await tester.tap(runTile);
    await tester.pumpAndSettle();
    await _scrollToVisible(tester, find.text('보고서 재전송'));
    await tester.tap(find.text('보고서 재전송'));
    await tester.pumpAndSettle();

    expect(find.text('보고서 선택 재전송'), findsOneWidget);
    await tester.tap(find.text('Cafe 운영'));
    await tester.pumpAndSettle();

    final confirmLabel = find.textContaining('중복 수신이 발생할 수 있음을 확인');
    expect(confirmLabel, findsOneWidget);
    final resendButton = find.text('재전송 (1명)');
    final disabledButton = tester.widget<FilledButton>(
      find.ancestor(
        of: resendButton,
        matching: find.byType(FilledButton),
      ),
    );
    expect(disabledButton.onPressed, isNull);
    await tester.tap(confirmLabel);
    await tester.pumpAndSettle();
    await tester.tap(resendButton);
    await tester.pumpAndSettle();

    expect(resendBody?['request_id'], matches(RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    )));
    expect(resendBody?['expected_settings_version'], 7);
    expect(resendBody?['recipient_ids'], [_recipientId]);
    expect(resendBody?['mode'], 'full_report');
    expect(resendBody?['confirm_possible_duplicate'], isTrue);
  });

  testWidgets('ambiguous manual-run retry reuses its request ID',
      (tester) async {
    final state = _TestAppState(admin: true);
    addTearDown(state.dispose);
    final requestIds = <String>[];
    var failFirstRun = true;

    Future<Map<String, dynamic>> request(
      String endpoint, {
      required String method,
      Map<String, Object?>? params,
      Map<String, dynamic>? body,
    }) async {
      if (endpoint.endsWith('/settings')) return _settingsResponse();
      if (endpoint.endsWith('/providers')) return _providersResponse();
      if (endpoint.endsWith('/auth/codex/login')) {
        return _notFoundCodexLogin();
      }
      if (endpoint.endsWith('/runs') && method == 'POST') {
        requestIds.add(body!['request_id'] as String);
        if (failFirstRun) {
          failFirstRun = false;
          throw const ApiException(
            'network outcome is unknown',
            isTransportError: true,
          );
        }
        return {'run': _run(id: 'run-retried', status: 'running')};
      }
      if (endpoint.endsWith('/runs/run-retried')) {
        return {'run': _run(id: 'run-retried', status: 'running')};
      }
      if (endpoint.endsWith('/runs')) return {'runs': <dynamic>[]};
      if (endpoint.endsWith('/audits')) return {'audits': <dynamic>[]};
      throw StateError('Unexpected request: $method $endpoint');
    }

    await tester.pumpWidget(_app(state: state, request: request));
    await tester.pumpAndSettle();
    final runButton = find.text('보고서 실행');
    await _scrollToVisible(tester, runButton);
    await tester.tap(runButton);
    await tester.pumpAndSettle();
    expect(requestIds, hasLength(1));

    await _scrollToVisible(tester, runButton);
    await tester.tap(runButton);
    await tester.pumpAndSettle();

    expect(requestIds, hasLength(2));
    expect(requestIds.last, requestIds.first);
    expect(requestIds.first, matches(RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    )));
  });

  testWidgets('ambiguous Telegram test asks before another delivery attempt',
      (tester) async {
    final state = _TestAppState(admin: true);
    addTearDown(state.dispose);
    var failFirstTest = true;
    var testCalls = 0;

    Future<Map<String, dynamic>> request(
      String endpoint, {
      required String method,
      Map<String, Object?>? params,
      Map<String, dynamic>? body,
    }) async {
      if (endpoint.endsWith('/settings')) return _settingsResponse();
      if (endpoint.endsWith('/providers')) return _providersResponse();
      if (endpoint.endsWith('/auth/codex/login')) {
        return _notFoundCodexLogin();
      }
      if (endpoint.endsWith('/tests/telegram')) {
        testCalls += 1;
        if (failFirstTest) {
          failFirstTest = false;
          throw const ApiException(
            'network outcome is unknown',
            isTransportError: true,
          );
        }
        return {'ok': true, 'latency_ms': 10};
      }
      if (endpoint.endsWith('/runs')) return {'runs': <dynamic>[]};
      if (endpoint.endsWith('/audits')) return {'audits': <dynamic>[]};
      throw StateError('Unexpected request: $method $endpoint');
    }

    await tester.pumpWidget(_app(state: state, request: request));
    await tester.pumpAndSettle();
    final testButton = find.widgetWithText(OutlinedButton, '연결 테스트');
    await _scrollToVisible(tester, testButton);
    await tester.tap(testButton);
    await tester.pumpAndSettle();
    expect(testCalls, 1);

    await _scrollToVisible(tester, testButton);
    await tester.tap(testButton);
    await tester.pumpAndSettle();
    expect(find.text('테스트 전송 결과 확인'), findsOneWidget);
    expect(testCalls, 1);

    await tester.tap(find.text('대화를 확인하고 다시 테스트'));
    await tester.pumpAndSettle();
    expect(testCalls, 2);
    await _scrollToTop(tester);
    expect(find.textContaining('Telegram 연결을 확인했습니다'), findsOneWidget);
  });

  testWidgets('does not render sensitive server error details', (tester) async {
    final state = _TestAppState(admin: true);
    addTearDown(state.dispose);

    Future<Map<String, dynamic>> request(
      String endpoint, {
      required String method,
      Map<String, Object?>? params,
      Map<String, dynamic>? body,
    }) async {
      if (endpoint.endsWith('/settings')) {
        throw const ApiException(
          'token=very-secret-value',
          statusCode: 500,
        );
      }
      if (endpoint.endsWith('/providers')) return _providersResponse();
      if (endpoint.endsWith('/auth/codex/login')) {
        return _notFoundCodexLogin();
      }
      if (endpoint.endsWith('/runs')) return {'runs': <dynamic>[]};
      if (endpoint.endsWith('/audits')) return {'audits': <dynamic>[]};
      throw StateError('Unexpected request: $method $endpoint');
    }

    await tester.pumpWidget(_app(state: state, request: request));
    await tester.pumpAndSettle();

    expect(find.textContaining('very-secret-value'), findsNothing);
    expect(find.textContaining('HTTP 500'), findsOneWidget);
  });
}
