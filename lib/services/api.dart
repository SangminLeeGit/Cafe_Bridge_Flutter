import 'dart:convert';
import 'dart:io';

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
  static const Duration _timeout = Duration(seconds: 15);
  static const String _defaultBaseUrl = 'https://pos.cafe-bridge.org';

  static String defaultBaseUrl() {
    return _defaultBaseUrl;
  }

  static String normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return defaultBaseUrl();
    }

    final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
    final uri = Uri.parse(withScheme);

    // HTTPS URLs (e.g. Cloudflare tunnel) — don't append port.
    // Also strip any non-standard port that may have been wrongly stored previously.
    if (uri.scheme == 'https') {
      if (uri.hasPort && uri.port != 443) {
        return Uri(scheme: uri.scheme, host: uri.host, path: uri.path)
            .toString()
            .replaceAll(RegExp(r'/$'), '');
      }
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

  static Map<String, String> defaultRange([int days = 13]) {
    final now = DateTime.now();
    final past = now.subtract(Duration(days: days));
    return {
      'from_date': _formatDate(past),
      'to_date': _formatDate(now),
    };
  }

  static String formatDate(DateTime date) => _formatDate(date);

  static Future<ApiResponse<Map<String, dynamic>>> fetchJson(
    String baseUrl,
    String endpoint, {
    Map<String, Object?>? params,
    String? sessionCookie,
  }) async {
    final uri = buildUri(baseUrl, endpoint, params: params);
    try {
      final response = await _send(
        'GET',
        uri,
        sessionCookie: sessionCookie,
      );
      return ApiResponse(
        data: _decodeMap(response),
        sessionCookie: _extractSessionCookie(response),
      );
    } on SocketException catch (error) {
      throw ApiException('네트워크 연결 실패: $error');
    } on HttpException catch (error) {
      throw ApiException('HTTP 예외: $error');
    } on FormatException catch (error) {
      throw ApiException('응답 파싱 실패: $error');
    }
  }

  static Future<ApiResponse<List<dynamic>>> fetchJsonList(
    String baseUrl,
    String endpoint, {
    Map<String, Object?>? params,
    String? sessionCookie,
  }) async {
    final uri = buildUri(baseUrl, endpoint, params: params);
    try {
      final response = await _send(
        'GET',
        uri,
        sessionCookie: sessionCookie,
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          'HTTP ${response.statusCode}: ${_decodeErrorMessage(response)}',
          statusCode: response.statusCode,
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
    } on SocketException catch (error) {
      throw ApiException('네트워크 연결 실패: $error');
    } on HttpException catch (error) {
      throw ApiException('HTTP 예외: $error');
    } on FormatException catch (error) {
      throw ApiException('응답 파싱 실패: $error');
    }
  }

  static Future<ApiResponse<Map<String, dynamic>>> postJson(
    String baseUrl,
    String endpoint, {
    Map<String, dynamic>? body,
    String? sessionCookie,
    String? csrfToken,
    bool includeCsrfToken = true,
    String method = 'POST',
  }) async {
    final uri = buildUri(baseUrl, endpoint);
    try {
      final response = await _send(
        method,
        uri,
        body: body,
        sessionCookie: sessionCookie,
        csrfToken: includeCsrfToken ? csrfToken : null,
      );
      return ApiResponse(
        data: _decodeMap(response),
        sessionCookie: _extractSessionCookie(response),
      );
    } on SocketException catch (error) {
      throw ApiException('네트워크 연결 실패: $error');
    } on HttpException catch (error) {
      throw ApiException('HTTP 예외: $error');
    } on FormatException catch (error) {
      throw ApiException('응답 파싱 실패: $error');
    }
  }

  static Map<String, dynamic> _decodeMap(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'HTTP ${response.statusCode}: ${_decodeErrorMessage(response)}',
        statusCode: response.statusCode,
      );
    }

    final decoded = json.decode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const ApiException('예상과 다른 응답 형식입니다.');
  }

  static String _decodeErrorMessage(http.Response response) {
    try {
      final decoded = json.decode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        final detail = _normalizeErrorDetail(decoded['detail']);
        if (detail.isNotEmpty) {
          return detail;
        }
        final error = _normalizeErrorDetail(decoded['error']);
        if (error.isNotEmpty) {
          return error;
        }
        return response.reasonPhrase ?? '오류';
      }
    } catch (_) {
      // Ignore secondary parse failures and use the HTTP reason phrase.
    }
    return response.reasonPhrase ?? '오류';
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
      final message = _normalizeErrorDetail(nested['msg']);
      if (locationLabel.isNotEmpty && message.isNotEmpty) {
        return '$locationLabel: $message';
      }
      if (message.isNotEmpty) {
        return message;
      }
      return _normalizeErrorDetail(nested['detail']);
    }
    return detail.toString().trim();
  }

  static Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
    String? sessionCookie,
    String? csrfToken,
  }) async {
    final client = http.Client();
    try {
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

      final streamed = await client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(streamed);
      return response;
    } finally {
      client.close();
    }
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

  static String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}
