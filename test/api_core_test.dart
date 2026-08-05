import 'dart:convert';
import 'dart:io';

import 'package:cafe_bridge_flutter/services/api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('API URL policy', () {
    test('preserves non-standard HTTPS ports', () {
      expect(
        ApiService.normalizeBaseUrl(
          'https://pos.cafe-bridge.org:8443/',
          requireHttps: true,
        ),
        'https://pos.cafe-bridge.org:8443',
      );
    });

    test('supports an opt-in production hostname allowlist', () {
      expect(
        ApiService.normalizeBaseUrl(
          'https://legacy.example.com',
          requireHttps: true,
        ),
        'https://legacy.example.com',
      );
      expect(
        () => ApiService.normalizeBaseUrl(
          'https://legacy.example.com',
          requireHttps: true,
          allowedProductionHosts: const {'pos.cafe-bridge.org'},
        ),
        throwsFormatException,
      );
    });
  });

  test('treats 204 No Content as a successful empty payload', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
    });
    final baseUrl = 'http://127.0.0.1:${server.port}';

    expect((await ApiService.fetchJson(baseUrl, '/map')).data, isEmpty);
    expect((await ApiService.fetchJsonList(baseUrl, '/list')).data, isEmpty);
    expect((await ApiService.postJson(baseUrl, '/post')).data, isEmpty);
  });

  test('marks transport failures but not HTTP status failures', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      request.response.statusCode = HttpStatus.forbidden;
      request.response.headers.contentType = ContentType.json;
      request.response.write(json.encode({'detail': 'forbidden'}));
      await request.response.close();
    });

    await expectLater(
      ApiService.fetchJson(baseUrl, '/forbidden'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having((error) => error.isTransportError, 'transport', isFalse),
      ),
    );
    await server.close(force: true);

    await expectLater(
      ApiService.fetchJson(baseUrl, '/unreachable'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.isTransportError, 'transport', isTrue),
      ),
    );
  });
}
