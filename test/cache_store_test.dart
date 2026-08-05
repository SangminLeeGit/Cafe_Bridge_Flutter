import 'package:cafe_bridge_flutter/services/cache_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const scope = 'guest@https://example.com';
  const baseUrl = 'https://example.com';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('sensitive endpoints never read or write disk cache', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ApiCacheStore(prefs);
    const endpoints = [
      '/api/costing/summary',
      '/api/workforce/employees',
      '/api/auth/users',
      '/api/auth/audit-logs?limit=10',
      '/api/deploy-history',
      '/api/ci/flutter-apk/jobs/1',
      '/api/app-update/metrics',
      '/api/admin/daily-reports/2026-07-24',
      '/api/menu-workspace/tasks/1',
      '/api/price/browser-apply/123',
      '/api/price/browser-apply-history',
      '/api/signage/menu',
      '/api/sync/123',
    ];

    for (final endpoint in endpoints) {
      expect(ApiCachePolicy.forEndpoint(endpoint), ApiCachePolicy.none);
      await store.write(
        scope: scope,
        baseUrl: baseUrl,
        endpoint: endpoint,
        data: const {'secret': true},
        policy: ApiCachePolicy.disk,
      );
      expect(
        store.read(scope: scope, baseUrl: baseUrl, endpoint: endpoint),
        isNull,
      );
    }
    expect(store.countAll(), 0);
  });

  test('prunes entries by maximum count and age', () async {
    final prefs = await SharedPreferences.getInstance();
    var now = DateTime.utc(2026, 7, 1);
    final store = ApiCacheStore(
      prefs,
      maxEntries: 2,
      maxAge: const Duration(days: 7),
      now: () => now,
    );

    for (var index = 0; index < 3; index += 1) {
      await store.write(
        scope: scope,
        baseUrl: baseUrl,
        endpoint: '/api/report/$index',
        data: {'index': index},
      );
      now = now.add(const Duration(minutes: 1));
    }
    expect(store.countAll(), 2);
    expect(
      store.read(scope: scope, baseUrl: baseUrl, endpoint: '/api/report/0'),
      isNull,
    );

    now = now.add(const Duration(days: 8));
    expect(await store.prune(), 2);
    expect(store.countAll(), 0);
  });

  test('normalizes parameter order into one cache key', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ApiCacheStore(prefs);
    await store.write(
      scope: scope,
      baseUrl: baseUrl,
      endpoint: '/api/report',
      params: const {'b': 2, 'a': 1},
      data: const {'ok': true},
    );

    final entry = store.read(
      scope: scope,
      baseUrl: baseUrl,
      endpoint: '/api/report',
      params: const {'a': 1, 'b': 2},
    );
    expect(entry?.data, {'ok': true});
    expect(store.countAll(), 1);
  });
}
