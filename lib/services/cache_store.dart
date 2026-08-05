import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CacheEntry {
  final Object data;
  final DateTime cachedAt;

  const CacheEntry({
    required this.data,
    required this.cachedAt,
  });
}

enum ApiCachePolicy {
  disk,
  none;

  static const List<String> _sensitiveEndpointPrefixes = [
    '/api/costing',
    '/api/workforce',
    '/api/auth/users',
    '/api/auth/audit-logs',
    '/api/deploy',
    '/api/ci',
    '/api/app-update/metrics',
    '/api/admin/daily-reports',
    '/api/menu-workspace',
    '/api/price/browser-apply',
    '/api/price/browser-apply-history',
    '/api/signage',
    '/api/sync',
  ];

  static ApiCachePolicy forEndpoint(String endpoint) {
    final path = Uri.tryParse(endpoint)?.path ?? endpoint;
    for (final prefix in _sensitiveEndpointPrefixes) {
      if (path.startsWith(prefix)) {
        return ApiCachePolicy.none;
      }
    }
    return ApiCachePolicy.disk;
  }
}

class ApiCacheStore {
  ApiCacheStore(
    this._prefs, {
    this.maxEntries = 100,
    this.maxAge = const Duration(days: 7),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const String _prefix = 'api_cache_v1_';

  final SharedPreferences _prefs;
  final int maxEntries;
  final Duration maxAge;
  final DateTime Function() _now;

  CacheEntry? read({
    required String scope,
    required String baseUrl,
    required String endpoint,
    Map<String, Object?>? params,
    ApiCachePolicy? policy,
  }) {
    if (ApiCachePolicy.forEndpoint(endpoint) == ApiCachePolicy.none ||
        policy == ApiCachePolicy.none) {
      return null;
    }
    final raw = _prefs.getString(
      _cacheKey(
        scope: scope,
        baseUrl: baseUrl,
        endpoint: endpoint,
        params: params,
      ),
    );
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) {
        return null;
      }

      final cachedAtRaw = decoded['cached_at']?.toString();
      final cachedAt =
          cachedAtRaw == null ? null : DateTime.tryParse(cachedAtRaw);
      final data = decoded['data'];
      if (cachedAt == null || (data is! Map && data is! List)) {
        return null;
      }
      if (_now().difference(cachedAt) > maxAge) {
        return null;
      }

      return CacheEntry(
        data: data as Object,
        cachedAt: cachedAt,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write({
    required String scope,
    required String baseUrl,
    required String endpoint,
    Map<String, Object?>? params,
    required Object data,
    ApiCachePolicy? policy,
  }) async {
    if (ApiCachePolicy.forEndpoint(endpoint) == ApiCachePolicy.none ||
        policy == ApiCachePolicy.none) {
      return;
    }
    if (data is! Map && data is! List) {
      return;
    }

    await _prefs.setString(
      _cacheKey(
        scope: scope,
        baseUrl: baseUrl,
        endpoint: endpoint,
        params: params,
      ),
      json.encode({
        'cached_at': _now().toIso8601String(),
        'data': data,
      }),
    );
    await prune();
  }

  Future<int> prune() async {
    final now = _now();
    final validEntries = <MapEntry<String, DateTime>>[];
    final keys = _prefs
        .getKeys()
        .where((key) => key.startsWith(_prefix))
        .toList(growable: false);
    var removed = 0;

    for (final key in keys) {
      final endpoint = _endpointFromKey(key);
      final raw = _prefs.getString(key);
      DateTime? cachedAt;
      if (raw != null) {
        try {
          final decoded = json.decode(raw);
          if (decoded is Map) {
            cachedAt =
                DateTime.tryParse(decoded['cached_at']?.toString() ?? '');
          }
        } catch (_) {
          // Invalid entries are removed below.
        }
      }
      if (endpoint == null ||
          ApiCachePolicy.forEndpoint(endpoint) == ApiCachePolicy.none ||
          cachedAt == null ||
          now.difference(cachedAt) > maxAge) {
        await _prefs.remove(key);
        removed += 1;
      } else {
        validEntries.add(MapEntry(key, cachedAt));
      }
    }

    validEntries.sort((a, b) => b.value.compareTo(a.value));
    for (final entry in validEntries.skip(maxEntries)) {
      await _prefs.remove(entry.key);
      removed += 1;
    }
    return removed;
  }

  Future<int> clearScope(String scope) async {
    final keys = _prefs
        .getKeys()
        .where((key) => key.startsWith(_scopePrefix(scope)))
        .toList(growable: false);
    for (final key in keys) {
      await _prefs.remove(key);
    }
    return keys.length;
  }

  Future<int> clearAll() async {
    final keys = _prefs
        .getKeys()
        .where((key) => key.startsWith(_prefix))
        .toList(growable: false);
    for (final key in keys) {
      await _prefs.remove(key);
    }
    return keys.length;
  }

  int countScope(String scope) {
    return _prefs
        .getKeys()
        .where((key) => key.startsWith(_scopePrefix(scope)))
        .length;
  }

  int countAll() {
    return _prefs.getKeys().where((key) => key.startsWith(_prefix)).length;
  }

  String _cacheKey({
    required String scope,
    required String baseUrl,
    required String endpoint,
    Map<String, Object?>? params,
  }) {
    final descriptor = json.encode({
      'base_url': baseUrl,
      'endpoint': endpoint,
      'params': _normalizeParams(params),
    });
    return '${_scopePrefix(scope)}${base64Url.encode(utf8.encode(descriptor))}';
  }

  String _scopePrefix(String scope) {
    return '$_prefix${base64Url.encode(utf8.encode(scope))}::';
  }

  String? _endpointFromKey(String key) {
    final separator = key.indexOf('::');
    if (separator < 0 || separator + 2 >= key.length) {
      return null;
    }
    try {
      final descriptor = json.decode(
        utf8.decode(base64Url.decode(key.substring(separator + 2))),
      );
      if (descriptor is Map) {
        return descriptor['endpoint']?.toString();
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Map<String, String> _normalizeParams(Map<String, Object?>? params) {
    if (params == null || params.isEmpty) {
      return const {};
    }

    final entries = params.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));

    final normalized = <String, String>{};
    for (final entry in entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }
      final text = value.toString();
      if (text.isNotEmpty) {
        normalized[entry.key] = text;
      }
    }
    return normalized;
  }
}
