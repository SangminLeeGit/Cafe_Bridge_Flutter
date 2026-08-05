import 'dart:async';
import 'dart:convert';

import 'package:cafe_bridge_flutter/services/active_task_store.dart';
import 'package:cafe_bridge_flutter/services/api.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

http.StreamedResponse _jsonResponse(
  Object payload, {
  int statusCode = 200,
  String? sessionCookie,
}) {
  final headers = <String, String>{'content-type': 'application/json'};
  if (sessionCookie != null) {
    headers['set-cookie'] = '$sessionCookie; HttpOnly';
  }
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(json.encode(payload))),
    statusCode,
    headers: headers,
  );
}

class _ScriptedClient extends http.BaseClient {
  _ScriptedClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('active task store scopes resumable work by account and server',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final store = ActiveTaskStore(preferences);

    await store.write(
      prefix: 'active_sync_task',
      scope: 'viewer@https://one.example',
      taskId: 'task-1',
    );
    await store.write(
      prefix: 'active_sync_task',
      scope: 'viewer@https://two.example',
      taskId: 'task-2',
    );

    expect(
      await store.read(
        prefix: 'active_sync_task',
        scope: 'viewer@https://one.example',
      ),
      'task-1',
    );
    expect(await store.removeScope('viewer@https://one.example'), 1);
    expect(
      await store.read(
        prefix: 'active_sync_task',
        scope: 'viewer@https://one.example',
      ),
      isNull,
    );
    expect(
      await store.read(
        prefix: 'active_sync_task',
        scope: 'viewer@https://two.example',
      ),
      'task-2',
    );
  });

  test('drops a response from the previous server before writing cache',
      () async {
    final responseReleased = Completer<void>();
    final requestStarted = Completer<void>();
    final client = _ScriptedClient((request) async {
      if (request.url.path == '/api/race') {
        if (!requestStarted.isCompleted) {
          requestStarted.complete();
        }
        await responseReleased.future;
        return _jsonResponse({'value': 7});
      }
      throw http.ClientException('unexpected request: ${request.url}');
    });
    final preferences = await SharedPreferences.getInstance();
    final state = AppState(
      apiClient: ApiClient(client: client),
      preferences: preferences,
    );
    addTearDown(state.dispose);
    await state.loadLocal(notify: false);

    final pending = state.fetchMapParsed<int>(
      '/api/race',
      parser: (json) => json['value'] as int,
    );
    await requestStarted.future;
    await state.updateApiBaseUrl('https://other.example.com');
    responseReleased.complete();

    expect((await pending).data, 7);
    expect(state.cacheEntryCount, 0);
  });

  test(
      'cookie renewal keeps request order when responses complete out of order',
      () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final secureValues = <String, String>{};
    FlutterSecureStorage.setMockInitialValues(secureValues);
    final client = _ScriptedClient((request) async {
      switch (request.url.path) {
        case '/api/auth/login':
          return _jsonResponse(
            {
              'user': {'login_id': 'tester', 'role': 'viewer'},
              'csrf_token': 'csrf',
            },
            sessionCookie: 'session=v1',
          );
        case '/api/first':
          firstStarted.complete();
          await releaseFirst.future;
          return _jsonResponse({'value': 1}, sessionCookie: 'session=v2');
        case '/api/second':
          return _jsonResponse({'value': 2}, sessionCookie: 'session=v3');
        default:
          throw http.ClientException('unexpected request: ${request.url}');
      }
    });
    final preferences = await SharedPreferences.getInstance();
    final state = AppState(
      apiClient: ApiClient(client: client),
      preferences: preferences,
    );
    addTearDown(state.dispose);
    await state.loadLocal(notify: false);
    await state.login('tester', 'password', rememberMe: true);

    final first = state.fetchMapParsed<int>(
      '/api/first',
      parser: (json) => json['value'] as int,
    );
    await firstStarted.future;
    await state.fetchMapParsed<int>(
      '/api/second',
      parser: (json) => json['value'] as int,
    );
    expect(secureValues['session_cookie'], 'session=v3');
    releaseFirst.complete();
    await first;
    expect(secureValues['session_cookie'], 'session=v3');
  });

  test('401 clears the authenticated cache scope', () async {
    final client = _ScriptedClient((request) async {
      switch (request.url.path) {
        case '/api/auth/login':
          return _jsonResponse(
            {
              'user': {'login_id': 'tester', 'role': 'viewer'},
              'csrf_token': 'csrf',
            },
            sessionCookie: 'session=one',
          );
        case '/api/report':
          return _jsonResponse({'value': 3});
        case '/api/expired':
          return _jsonResponse({'detail': 'expired'}, statusCode: 401);
        default:
          throw http.ClientException('unexpected request: ${request.url}');
      }
    });
    final preferences = await SharedPreferences.getInstance();
    final state = AppState(
      apiClient: ApiClient(client: client),
      preferences: preferences,
    );
    addTearDown(state.dispose);
    await state.loadLocal(notify: false);
    await state.login('tester', 'password', rememberMe: false);
    await state.fetchMapParsed<int>(
      '/api/report',
      parser: (json) => json['value'] as int,
    );

    await expectLater(
      state.fetchMapParsed<void>('/api/expired', parser: (_) {}),
      throwsA(isA<ApiException>()),
    );
    expect(state.isAuthenticated, isFalse);
    expect(state.cacheEntryCount, 0);
  });

  test('remembered sessions restore cached data when session check is offline',
      () async {
    final secureValues = <String, String>{};
    FlutterSecureStorage.setMockInitialValues(secureValues);
    final onlineClient = _ScriptedClient((request) async {
      if (request.url.path == '/api/auth/login') {
        return _jsonResponse(
          {
            'user': {'login_id': 'offline-user', 'role': 'viewer'},
            'csrf_token': 'csrf',
          },
          sessionCookie: 'session=remembered',
        );
      }
      if (request.url.path == '/api/offline-report') {
        return _jsonResponse({'value': 9});
      }
      throw http.ClientException('unexpected request: ${request.url}');
    });
    final preferences = await SharedPreferences.getInstance();
    final firstState = AppState(
      apiClient: ApiClient(client: onlineClient),
      preferences: preferences,
    );
    await firstState.loadLocal(notify: false);
    await firstState.login('offline-user', 'password', rememberMe: true);
    await firstState.fetchMapParsed<int>(
      '/api/offline-report',
      parser: (json) => json['value'] as int,
    );
    firstState.dispose();

    final offlineClient = _ScriptedClient((request) async {
      throw http.ClientException('offline');
    });
    final restoredState = AppState(
      apiClient: ApiClient(client: offlineClient),
      preferences: preferences,
    );
    addTearDown(restoredState.dispose);
    await restoredState.loadLocal(notify: false);
    await restoredState.loadRemote(
      notify: false,
      checkForUpdate: false,
    );

    expect(restoredState.isAuthenticated, isTrue);
    expect(restoredState.offlineMode, isTrue);
    final cached = await restoredState.fetchMapParsed<int>(
      '/api/offline-report',
      parser: (json) => json['value'] as int,
    );
    expect(cached.data, 9);
    expect(cached.fromCache, isTrue);
  });
}
