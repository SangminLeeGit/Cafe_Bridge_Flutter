import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cafe_bridge_flutter/services/api.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    HttpOverrides.global = _RealHttpOverrides();
  });

  test('unknown roles parse fail-closed while known roles keep their rank', () {
    expect(UserRoleAccess.fromString(null), UserRole.unknown);
    expect(UserRoleAccess.fromString('owner'), UserRole.unknown);
    expect(UserRoleAccess.fromString(' VIEWER '), UserRole.viewer);
    expect(UserRole.unknown.allows(UserRole.viewer), isFalse);
    expect(UserRole.operator.allows(UserRole.viewer), isTrue);
  });

  test('remember-me controls persistence for login and GET cookie renewal',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://127.0.0.1:${server.port}';
    var cookieVersion = 0;
    server.listen((request) async {
      cookieVersion += 1;
      request.response.headers.contentType = ContentType.json;
      request.response.headers
          .set('set-cookie', 'session=v$cookieVersion; HttpOnly');
      if (request.uri.path == '/api/auth/login') {
        request.response.write(json.encode({
          'user': {'login_id': 'tester', 'role': 'viewer'},
          'csrf_token': 'token',
        }));
      } else {
        request.response.write(json.encode({'ok': true}));
      }
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final secureValues = <String, String>{'session_cookie': 'old'};
    FlutterSecureStorage.setMockInitialValues(secureValues);
    SharedPreferences.setMockInitialValues({
      'api_base_url': baseUrl,
      'auth_remember_me': false,
    });
    final state = AppState();
    addTearDown(state.dispose);

    await state.loadLocal();
    expect(state.isInitializing, isFalse);
    expect(secureValues, isNot(contains('session_cookie')));

    await state.login('tester', 'password', rememberMe: false);
    expect(secureValues, isNot(contains('session_cookie')));
    await state.fetchMapParsed<bool>(
      '/api/report',
      parser: (json) => json['ok'] == true,
    );
    expect(secureValues, isNot(contains('session_cookie')));

    await state.setRememberMe(true);
    expect(secureValues['session_cookie'], 'session=v2');
    await state.fetchMapParsed<bool>(
      '/api/report',
      parser: (json) => json['ok'] == true,
    );
    expect(secureValues['session_cookie'], 'session=v3');
  });

  test('writes cache after parsing and falls back only on transport errors',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://127.0.0.1:${server.port}';
    var statusCode = HttpStatus.ok;
    server.listen((request) async {
      request.response.statusCode = statusCode;
      request.response.headers.contentType = ContentType.json;
      request.response.write(json.encode(
        statusCode == HttpStatus.ok
            ? {'value': 7}
            : {'detail': 'server rejected request'},
      ));
      await request.response.close();
    });

    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({'api_base_url': baseUrl});
    final state = AppState();
    addTearDown(state.dispose);
    await state.loadLocal();

    await expectLater(
      state.fetchMapParsed<int>(
        '/api/parser-failure',
        parser: (_) => throw const FormatException('invalid contract'),
      ),
      throwsFormatException,
    );
    expect(state.cacheEntryCount, 0);

    final fresh = await state.fetchMapParsed<int>(
      '/api/report',
      parser: (json) => json['value'] as int,
    );
    expect(fresh.data, 7);
    expect(fresh.fromCache, isFalse);
    expect(state.cacheEntryCount, 1);

    statusCode = HttpStatus.internalServerError;
    await expectLater(
      state.fetchMapParsed<int>(
        '/api/report',
        parser: (json) => json['value'] as int,
      ),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 500),
      ),
    );

    await server.close(force: true);
    final stale = await state.fetchMapParsed<int>(
      '/api/report',
      parser: (json) => json['value'] as int,
    );
    expect(stale.data, 7);
    expect(stale.fromCache, isTrue);
    expect(state.offlineMode, isTrue);
  });

  test('service-health and touchkey payloads are never persisted', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(json.encode({'ok': true}));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({'api_base_url': baseUrl});
    final state = AppState();
    addTearDown(state.dispose);
    await state.loadLocal(notify: false);

    for (final endpoint in const [
      '/api/service-health',
      '/api/menu-engineering/touchkey-tables',
    ]) {
      await state.fetchMapParsed<bool>(
        endpoint,
        parser: (json) => json['ok'] == true,
        cacheTtl: const Duration(hours: 1),
      );
    }

    expect(state.cacheEntryCount, 0);
  });

  test('keeps update metadata when an unauthenticated session clears its epoch',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://127.0.0.1:${server.port}';
    final updateRequestReceived = Completer<void>();
    final releaseUpdateResponse = Completer<void>();
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/api/app-update/check') {
        if (!updateRequestReceived.isCompleted) {
          updateRequestReceived.complete();
        }
        await releaseUpdateResponse.future;
        request.response.write(json.encode({
          'platform': 'android',
          'channel': 'prod',
          'latest_version': '1.0.2',
          'latest_build': 4,
          'update_available': true,
          'download_url': 'https://releases.example.com/cafe-bridge.apk',
          'sha256':
              '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
          'file_size': 100,
        }));
      } else if (request.uri.path == '/api/auth/session') {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.write(json.encode({'detail': 'not authenticated'}));
      }
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({'api_base_url': baseUrl});
    final state = AppState();
    addTearDown(state.dispose);
    await state.loadLocal();

    final updateFuture = state.checkForAppUpdate(
      notify: false,
      ignoreErrors: false,
    );
    await updateRequestReceived.future;
    await expectLater(
      state.refreshSession(notify: false),
      throwsA(isA<ApiException>()),
    );
    releaseUpdateResponse.complete();
    await updateFuture;

    expect(state.hasRecommendedUpdate, isTrue);
    expect(state.updateInfo?.latestBuild, 4);
  });
}
