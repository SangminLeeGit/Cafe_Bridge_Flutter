import 'dart:async';

import 'package:cafe_bridge_flutter/screens/settings.dart';
import 'package:cafe_bridge_flutter/services/api.dart';
import 'package:cafe_bridge_flutter/services/cache_store.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _DeployRequestAppState extends AppState {
  _DeployRequestAppState({this.startWithActiveTask = false});

  final bool startWithActiveTask;
  final List<String> endpoints = <String>[];
  final List<Map<String, dynamic>> requests = <Map<String, dynamic>>[];
  Object? postError;
  Completer<Map<String, dynamic>>? postCompleter;

  @override
  bool get hasAdminAccess => true;

  @override
  String get loginId => 'qa-admin';

  @override
  Future<CachedDataResult<T>> fetchMapParsed<T>(
    String endpoint, {
    Map<String, Object?>? params,
    required T Function(Map<String, dynamic> json) parser,
    Duration cacheTtl = const Duration(minutes: 30),
    bool allowStaleOnError = true,
    ApiCachePolicy? cachePolicy,
  }) async {
    endpoints.add(endpoint);
    final Map<String, dynamic> json;
    if (endpoint == '/api/deploy-history') {
      json = {
        'tasks': startWithActiveTask
            ? <dynamic>[_taskJson(status: 'running', taskId: 'active-task')]
            : <dynamic>[],
      };
    } else if (endpoint == '/api/deploy/flutter-apk/version-info') {
      json = {
        'pubspec': <String, dynamic>{},
        'update_policy': <String, dynamic>{},
        'latest_release': <String, dynamic>{},
      };
    } else if (endpoint.startsWith('/api/deploy/')) {
      final taskId = endpoint.substring('/api/deploy/'.length);
      json = {
        'task': _taskJson(
          status: 'running',
          taskId: taskId,
          reason: 'release verification',
        ),
      };
    } else if (endpoint == '/api/app-update/metrics') {
      json = {
        'app_update_check_total': 0,
        'app_update_check_failed_total': 0,
        'download_url_empty_total': 0,
        'policy_source_total': <String, dynamic>{},
      };
    } else if (endpoint == '/api/admin/runtime-status') {
      json = {
        'service': 'cafe-bridge',
        'status': 'running',
        'runtime': <String, dynamic>{},
        'deployment': <String, dynamic>{},
      };
    } else if (endpoint == '/api/ci/flutter-apk/jobs') {
      json = {'jobs': <dynamic>[]};
    } else {
      throw ApiException('unexpected endpoint: $endpoint');
    }

    return CachedDataResult<T>(
      data: parser(json),
      fromCache: false,
      cachedAt: DateTime.utc(2026, 11, 22),
    );
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String endpoint, {
    Map<String, dynamic>? body,
    String method = 'POST',
  }) async {
    if (postError != null) throw postError!;
    if (endpoint != '/api/deploy') {
      throw ApiException('unexpected POST endpoint: $endpoint');
    }
    requests.add(Map<String, dynamic>.of(body ?? const {}));
    if (postCompleter != null) return postCompleter!.future;
    return {'task_id': 'task-123', 'status': 'pending'};
  }

  Map<String, dynamic> _taskJson({
    required String status,
    required String taskId,
    String reason = '',
  }) {
    return {
      'task_id': taskId,
      'target': 'flutter-apk',
      'requested_by': 'qa-admin',
      'reason': reason,
      'dry_run': false,
      'status': status,
      'current_step': status == 'running' ? 'building' : 'queued',
      'log_path': '',
      'resolved_commit': '',
      'error_message': '',
    };
  }
}

Future<void> _pumpAdminPanel(
  WidgetTester tester,
  _DeployRequestAppState appState,
) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(appState.dispose);

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: AdminDeployMonitor()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('requires a reason, submits dry-run, then polls the task',
      (tester) async {
    final appState = _DeployRequestAppState();
    await _pumpAdminPanel(tester, appState);

    final requestButton = find.byKey(const ValueKey('deploy-request-button'));
    await tester.ensureVisible(requestButton);
    await tester.tap(requestButton);
    await tester.pumpAndSettle();

    expect(find.text('배포 사유를 입력해 주세요.'), findsOneWidget);
    expect(appState.requests, isEmpty);

    await tester.enterText(
      find.byType(TextFormField),
      '모바일 결제 흐름 검증',
    );
    await tester.ensureVisible(requestButton);
    await tester.tap(requestButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(appState.requests, hasLength(1));
    expect(appState.requests.single, {
      'target': 'flutter-apk',
      'reason': '모바일 결제 흐름 검증',
      'dry_run': true,
    });
    expect(find.textContaining('task-123'), findsWidgets);
    expect(find.text('pending'), findsWidgets);
    expect(appState.endpoints, contains('/api/deploy-history'));

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(appState.endpoints, contains('/api/deploy/task-123'));
    expect(find.text('running'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('production registration requires explicit confirmation',
      (tester) async {
    final appState = _DeployRequestAppState();
    await _pumpAdminPanel(tester, appState);

    await tester.enterText(
      find.byType(TextFormField),
      '정식 APK 등록',
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );

    final requestButton = find.byKey(const ValueKey('deploy-request-button'));
    await tester.ensureVisible(requestButton);
    await tester.tap(requestButton);
    await tester.pumpAndSettle();

    expect(find.text('프로덕션 APK 등록 요청 확인'), findsOneWidget);
    expect(appState.requests, isEmpty);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(appState.requests, isEmpty);

    await tester.ensureVisible(requestButton);
    await tester.tap(requestButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('등록 요청 보내기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(appState.requests.single, {
      'target': 'flutter-apk',
      'reason': '정식 APK 등록',
      'dry_run': false,
    });
    expect(find.textContaining('배포 요청 접수'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('active task disables duplicate deploy requests', (tester) async {
    final appState = _DeployRequestAppState(startWithActiveTask: true);
    await _pumpAdminPanel(tester, appState);

    final button = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('deploy-request-button')),
    );
    expect(button.onPressed, isNull);
    expect(find.textContaining('active-task'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(appState.requests, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('in-flight request disables duplicate submission', (tester) async {
    final appState = _DeployRequestAppState()
      ..postCompleter = Completer<Map<String, dynamic>>();
    await _pumpAdminPanel(tester, appState);

    await tester.enterText(find.byType(TextFormField), '중복 요청 방지');
    final requestButton = find.byKey(const ValueKey('deploy-request-button'));
    await tester.ensureVisible(requestButton);
    await tester.tap(requestButton);
    await tester.pump();

    expect(appState.requests, hasLength(1));
    expect(tester.widget<ElevatedButton>(requestButton).onPressed, isNull);
    await tester.tap(requestButton);
    expect(appState.requests, hasLength(1));

    appState.postCompleter!.complete({
      'task_id': 'task-123',
      'status': 'pending',
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('배포 요청 접수'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('request errors are shown and the form becomes usable again',
      (tester) async {
    final appState = _DeployRequestAppState()
      ..postError =
          const ApiException('server rejected request', statusCode: 409);
    await _pumpAdminPanel(tester, appState);

    await tester.enterText(find.byType(TextFormField), '충돌 테스트');
    final requestButton = find.byKey(const ValueKey('deploy-request-button'));
    await tester.ensureVisible(requestButton);
    await tester.tap(requestButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('server rejected request'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(requestButton).onPressed, isNotNull);
  });
}
