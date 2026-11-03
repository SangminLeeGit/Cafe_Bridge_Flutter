import 'dart:convert';
import 'dart:io';

import 'package:cafe_bridge_flutter/models/api_contracts.dart';
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

  test('preserves structured backend error codes, messages, fields and IDs',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = HttpStatus.conflict;
      request.response.headers.contentType = ContentType.json;
      switch (request.uri.path) {
        case '/code':
          request.response.headers.set('x-request-id', 'req-code-7');
          request.response.write(json.encode({
            'detail': {
              'code': 'legacy_mutation_disabled',
              'message': 'Preview only',
            },
          }));
        case '/reason':
          request.response.write(json.encode({
            'detail': {
              'reason_code': 'snapshot_changed',
              'message': 'Reload before saving',
            },
          }));
        case '/fields':
          request.response.statusCode = HttpStatus.unprocessableEntity;
          request.response.write(json.encode({
            'detail': [
              {
                'loc': ['body', 'items', 0, 'quantity'],
                'msg': 'must be positive',
              },
            ],
          }));
        default:
          request.response.write(json.encode({'detail': 'plain detail'}));
      }
      await request.response.close();
    });
    final baseUrl = 'http://127.0.0.1:${server.port}';

    await expectLater(
      ApiService.fetchJson(baseUrl, '/code'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 409)
            .having((error) => error.code, 'code', 'legacy_mutation_disabled')
            .having((error) => error.message, 'message', 'Preview only')
            .having((error) => error.requestId, 'requestId', 'req-code-7'),
      ),
    );
    await expectLater(
      ApiService.fetchJson(baseUrl, '/reason'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.code, 'code', 'snapshot_changed')
            .having(
                (error) => error.message, 'message', 'Reload before saving'),
      ),
    );
    await expectLater(
      ApiService.fetchJson(baseUrl, '/fields'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 422)
            .having(
          (error) => error.fieldErrors,
          'fieldErrors',
          const {'items.0.quantity': 'must be positive'},
        ),
      ),
    );
    await expectLater(
      ApiService.fetchJson(baseUrl, '/plain'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'plain detail',
        ),
      ),
    );
  });

  test('required list parsing rejects missing and malformed response fields',
      () {
    expect(
      () => requireListOfMaps(const <String, dynamic>{}, 'rows'),
      throwsFormatException,
    );
    expect(
      () => requireListOfMaps(
        const <String, dynamic>{
          'rows': <Object?>[1]
        },
        'rows',
      ),
      throwsFormatException,
    );
    expect(
      requireListOfMaps(
        const <String, dynamic>{
          'rows': <Object?>[
            <String, dynamic>{'id': 1}
          ]
        },
        'rows',
      ),
      hasLength(1),
    );
  });
}
