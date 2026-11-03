import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiResponse<T> {
  final T data;
  final String? sessionCookie;

  const ApiResponse({
    required this.data,
    this.sessionCookie,
  });
}

class ApiService {
  static const String _defaultBaseUrl = 'https://pos.cafe-bridge.org';
  static const Set<String> _debugHttpHosts = {
    'localhost',
    '127.0.0.1',
    '10.0.2.2',
  };

  static String defaultBaseUrl() {
    return _defaultBaseUrl;
  }

  static String normalizeBaseUrl(
    String raw, {
    bool requireHttps = !kDebugMode,
    Set<String>? allowedProductionHosts,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return defaultBaseUrl();
    }

    final schemeProbe = Uri.tryParse('//$trimmed');
    final useDebugHttp = !requireHttps &&
        schemeProbe != null &&
        _debugHttpHosts.contains(schemeProbe.host.toLowerCase());
    final defaultScheme = useDebugHttp ? 'http' : 'https';
    final withScheme =
        trimmed.contains('://') ? trimmed : '$defaultScheme://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) {
      throw const FormatException('올바른 서버 주소를 입력해 주세요.');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const FormatException('서버 주소는 HTTP 또는 HTTPS URL이어야 합니다.');
    }
    if (uri.scheme == 'http' &&
        (requireHttps || !_debugHttpHosts.contains(uri.host.toLowerCase()))) {
      throw const FormatException('HTTP 서버는 디버그 빌드의 로컬 개발 주소에서만 사용할 수 있습니다.');
    }
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw const FormatException('서버 주소에는 인증 정보, 쿼리 또는 프래그먼트를 사용할 수 없습니다.');
    }
    if (requireHttps &&
        allowedProductionHosts != null &&
        !allowedProductionHosts
            .map((host) => host.toLowerCase())
            .contains(uri.host.toLowerCase())) {
      throw const FormatException('허용되지 않은 서버 호스트입니다.');
    }

    if (uri.scheme == 'https') {
      return uri.toString().replaceAll(RegExp(r'/$'), '');
    }

    if (uri.hasPort) {
      return uri.toString().replaceAll(RegExp(r'/$'), '');
    }

    return uri.replace(port: 8087).toString().replaceAll(RegExp(r'/$'), '');
  }

  static Uri buildUri(
    String baseUrl,
    String endpoint, {
    Map<String, Object?>? params,
  }) {
    final base = Uri.parse(normalizeBaseUrl(baseUrl));
    final uri = base.resolve(endpoint);
    if (params == null || params.isEmpty) {
      return uri;
    }

    final query = <String, String>{};
    for (final entry in params.entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }
      final stringValue = value.toString();
      if (stringValue.isNotEmpty) {
        query[entry.key] = stringValue;
      }
    }

    return uri.replace(queryParameters: query.isEmpty ? null : query);
  }

  static String formatDate(DateTime date) => _formatDate(date);

  static DateTime kstNow() {
    final value = DateTime.now().toUtc().add(const Duration(hours: 9));
    return DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
  }

  // Static entry points are kept for pure callers and tests. Stateful code
  // should use an injected ApiClient so a single HTTP client can be reused.
  static Future<ApiResponse<Map<String, dynamic>>> fetchJson(
    String baseUrl,
    String endpoint, {
    Map<String, Object?>? params,
    String? sessionCookie,
  }) =>
      _withClient(
        (client) => client.fetchJson(
          baseUrl,
          endpoint,
          params: params,
          sessionCookie: sessionCookie,
        ),
      );

  static Future<ApiResponse<List<dynamic>>> fetchJsonList(
    String baseUrl,
    String endpoint, {
    Map<String, Object?>? params,
    String? sessionCookie,
  }) =>
      _withClient(
        (client) => client.fetchJsonList(
          baseUrl,
          endpoint,
          params: params,
          sessionCookie: sessionCookie,
        ),
      );

  static Future<ApiResponse<Map<String, dynamic>>> postJson(
    String baseUrl,
    String endpoint, {
    Map<String, dynamic>? body,
    String? sessionCookie,
    String? csrfToken,
    bool includeCsrfToken = true,
    String method = 'POST',
  }) =>
      _withClient(
        (client) => client.postJson(
          baseUrl,
          endpoint,
          body: body,
          sessionCookie: sessionCookie,
          csrfToken: csrfToken,
          includeCsrfToken: includeCsrfToken,
          method: method,
        ),
      );

  static Future<T> _withClient<T>(Future<T> Function(ApiClient) action) async {
    final client = ApiClient();
    try {
      return await action(client);
    } finally {
      client.close();
    }
  }

  static String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

/// Stateful HTTP boundary. A single client is reused by [AppState] and can be
/// replaced in tests without making UI code know about the http package.
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  static const Duration _timeout = Duration(seconds: 15);

  final http.Client _client;
  bool _closed = false;

  Future<ApiResponse<Map<String, dynamic>>> fetchJson(
    String baseUrl,
    String endpoint, {
    Map<String, Object?>? params,
    String? sessionCookie,
  }) {
    return _guard(() async {
      final response = await _send(
        'GET',
        ApiService.buildUri(baseUrl, endpoint, params: params),
        sessionCookie: sessionCookie,
      );
      return ApiResponse(
        data: _decodeMap(response),
        sessionCookie: _extractSessionCookie(response),
      );
    });
  }

  Future<ApiResponse<List<dynamic>>> fetchJsonList(
    String baseUrl,
    String endpoint, {
    Map<String, Object?>? params,
    String? sessionCookie,
  }) {
    return _guard(() async {
      final response = await _send(
        'GET',
        ApiService.buildUri(baseUrl, endpoint, params: params),
        sessionCookie: sessionCookie,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _exceptionFromResponse(response);
      }
      if (response.statusCode == 204) {
        return ApiResponse(
          data: const <dynamic>[],
          sessionCookie: _extractSessionCookie(response),
        );
      }
      final decoded = json.decode(utf8.decode(response.bodyBytes));
      if (decoded is List<dynamic>) {
        return ApiResponse(
          data: decoded,
          sessionCookie: _extractSessionCookie(response),
        );
      }
      throw const ApiException('예상과 다른 응답 형식입니다.');
    });
  }

  Future<ApiResponse<Map<String, dynamic>>> postJson(
    String baseUrl,
    String endpoint, {
    Map<String, dynamic>? body,
    String? sessionCookie,
    String? csrfToken,
    bool includeCsrfToken = true,
    String method = 'POST',
  }) {
    return _guard(() async {
      final response = await _send(
        method,
        ApiService.buildUri(baseUrl, endpoint),
        body: body,
        sessionCookie: sessionCookie,
        csrfToken: includeCsrfToken ? csrfToken : null,
      );
      return ApiResponse(
        data: _decodeMap(response),
        sessionCookie: _extractSessionCookie(response),
      );
    });
  }

  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on TimeoutException catch (error) {
      throw ApiException('요청 시간 초과: $error', isTransportError: true);
    } on http.ClientException catch (error) {
      throw ApiException('네트워크 요청 실패: $error', isTransportError: true);
    } on FormatException catch (error) {
      throw ApiException('응답 파싱 실패: $error');
    }
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
    String? sessionCookie,
    String? csrfToken,
  }) async {
    if (_closed) {
      throw StateError('ApiClient has been closed.');
    }
    final request = http.Request(method, uri);
    request.headers['Accept'] = 'application/json';
    if (sessionCookie != null && sessionCookie.isNotEmpty) {
      request.headers['Cookie'] = sessionCookie;
    }
    if (csrfToken != null && csrfToken.isNotEmpty) {
      request.headers['X-CSRF-Token'] = csrfToken;
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = json.encode(body);
    }
    return _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(_timeout);
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _client.close();
  }

  static Map<String, dynamic> _decodeMap(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _exceptionFromResponse(response);
    }
    if (response.statusCode == 204) {
      return const <String, dynamic>{};
    }
    final decoded = json.decode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const ApiException('예상과 다른 응답 형식입니다.');
  }

  static ApiException _exceptionFromResponse(http.Response response) {
    Object? payload;
    try {
      payload = json.decode(utf8.decode(response.bodyBytes));
    } catch (_) {
      // Fall back to the HTTP reason phrase when the error body is not JSON.
    }

    final root = payload is Map ? Map<String, dynamic>.from(payload) : null;
    final detail = root?['detail'];
    final error = root?['error'];
    final detailMessage = _normalizeErrorDetail(detail);
    final errorMessage = _normalizeErrorDetail(error);
    final rootMessage = _normalizeErrorDetail(root?['message']);
    final message = detailMessage.isNotEmpty
        ? detailMessage
        : errorMessage.isNotEmpty
            ? errorMessage
            : rootMessage.isNotEmpty
                ? rootMessage
                : response.reasonPhrase ?? '오류';

    final detailMap = detail is Map ? Map<String, dynamic>.from(detail) : null;
    final errorMap = error is Map ? Map<String, dynamic>.from(error) : null;
    final code = _firstNonEmpty([
      detailMap?['code'],
      detailMap?['reason_code'],
      errorMap?['code'],
      errorMap?['reason_code'],
      root?['code'],
      root?['reason_code'],
    ]);
    final requestId = _firstNonEmpty([
      response.headers['x-request-id'],
      response.headers['request-id'],
      response.headers['x-correlation-id'],
      root?['request_id'],
      root?['requestId'],
      detailMap?['request_id'],
      errorMap?['request_id'],
    ]);

    return ApiException(
      message,
      statusCode: response.statusCode,
      code: code,
      requestId: requestId,
      fieldErrors: _collectFieldErrors(detail),
    );
  }

  static String? _firstNonEmpty(Iterable<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static Map<String, String> _collectFieldErrors(Object? value) {
    final result = <String, String>{};
    void collect(Object? current) {
      if (current is List) {
        for (final item in current) {
          collect(item);
        }
        return;
      }
      if (current is! Map) return;
      final map = Map<String, dynamic>.from(current);
      final location = map['loc'];
      final field = location is List
          ? location
              .map((part) => part.toString())
              .where(
                  (part) => part != 'body' && part != 'query' && part != 'path')
              .join('.')
          : '';
      final message = _normalizeErrorDetail(map['msg']);
      if (field.isNotEmpty && message.isNotEmpty) {
        result[field] = message;
      }
      collect(map['detail']);
      collect(map['errors']);
    }

    collect(value);
    return result;
  }

  static String _normalizeErrorDetail(Object? detail) {
    if (detail == null) {
      return '';
    }
    if (detail is String) {
      return detail.trim();
    }
    if (detail is List) {
      return detail
          .map(_normalizeErrorDetail)
          .where((item) => item.isNotEmpty)
          .join('; ');
    }
    if (detail is Map) {
      final nested = Map<String, dynamic>.from(detail);
      final location = nested['loc'];
      final locationLabel = location is List
          ? location.map((item) => item.toString()).join('.')
          : '';
      final message = _firstNonEmpty([
            nested['message'],
            nested['msg'],
          ]) ??
          '';
      if (locationLabel.isNotEmpty && message.isNotEmpty) {
        return '$locationLabel: $message';
      }
      if (message.isNotEmpty) {
        return message;
      }
      final nestedDetail = _normalizeErrorDetail(nested['detail']);
      if (nestedDetail.isNotEmpty) return nestedDetail;
      return _normalizeErrorDetail(nested['errors']);
    }
    return detail.toString().trim();
  }

  static String? _extractSessionCookie(http.Response response) {
    final raw = response.headers['set-cookie'];
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final firstPart = raw.split(';').first.trim();
    if (!firstPart.contains('=')) {
      return null;
    }
    return firstPart;
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;
  final String? requestId;
  final Map<String, String> fieldErrors;
  final bool isTransportError;

  const ApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.requestId,
    this.fieldErrors = const <String, String>{},
    this.isTransportError = false,
  });

  @override
  String toString() => message;
}
