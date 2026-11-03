import 'package:cafe_bridge_flutter/screens/settings.dart';
import 'package:cafe_bridge_flutter/services/api.dart';
import 'package:cafe_bridge_flutter/services/cache_store.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _AdminMonitorAppState extends AppState {
  _AdminMonitorAppState({this.forbiddenEndpoints = const <String>{}});

  final Set<String> forbiddenEndpoints;
  final List<String> endpoints = <String>[];
  final Map<String, Map<String, Object?>?> paramsSeen =
      <String, Map<String, Object?>?>{};

  @override
  bool get hasAdminAccess => true;

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
    paramsSeen[endpoint] =
        params == null ? null : Map<String, Object?>.of(params);
    if (forbiddenEndpoints.contains(endpoint)) {
      throw const ApiException('forbidden', statusCode: 403);
    }
    final Map<String, dynamic> json;
    if (endpoint == '/api/deploy-history') {
      json = {'tasks': <dynamic>[]};
    } else if (endpoint == '/api/deploy/flutter-apk/version-info') {
      json = {
        'pubspec': <String, dynamic>{},
        'update_policy': <String, dynamic>{},
        'latest_release': <String, dynamic>{},
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
        'status': 'drifted',
        'observed_at': '2026-11-03T12:30:00Z',
        'runtime': {
          'commit_sha': 'aaaaaaaa11111111',
          'short_commit_sha': 'aaaaaaaa',
          'release_id': 'runtime-release-7',
          'started_at': '2026-11-03T10:00:00Z',
          'uptime_seconds': 9000,
        },
        'deployment': {
          'status': 'succeeded',
          'commit_sha': 'bbbbbbbb22222222',
          'short_commit_sha': 'bbbbbbbb',
          'release_id': 'deployed-release-8',
          'deployed_at': '2026-11-03T11:00:00Z',
          'deploy_started_at': '2026-11-03T10:55:00Z',
          'source': 'gitlab-pipeline',
          'commit_match': false,
        },
      };
    } else if (endpoint == '/api/ci/flutter-apk/jobs') {
      json = {
        'jobs': [_jobJson],
      };
    } else if (endpoint == '/api/ci/flutter-apk/jobs/job-123') {
      json = {'job': _jobJson};
    } else {
      throw ApiException('unexpected endpoint: $endpoint');
    }

    return CachedDataResult<T>(
      data: parser(json),
      fromCache: false,
      cachedAt: DateTime.utc(2026, 11, 3),
    );
  }
}

const Map<String, dynamic> _jobJson = {
  'job_id': 'job-123',
  'event_name': 'push',
  'repo_full_name': 'cafe-bridge/mobile',
  'branch': 'release/ci-monitor',
  'ref': 'refs/heads/release/ci-monitor',
  'commit_sha': '12345678abcdef0123456789abcdef0123456789',
  'pusher': 'ci-user',
  'requested_by': 'qa-admin',
  'deploy_task_id': 'deploy-456',
  'source': 'gitlab-pipeline',
  'status': 'registered',
  'version_name': '1.2.3',
  'build_number': 42,
  'file_name': 'cafe-bridge-1.2.3.apk',
  'sha256': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'file_size': 2 * 1024 * 1024,
  'artifact_path': '/not-rendered/artifact.apk',
  'download_url': 'https://downloads.example.test/app.apk',
  'release_notes': 'CI monitor release notes',
  'error_message': '',
  'created_at': '2026-11-03T10:00:00Z',
  'updated_at': '2026-11-03T11:00:00Z',
  'registered_at': '2026-11-03T11:05:00Z',
};

void main() {
  testWidgets('admin monitor shows runtime drift and APK CI job details',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final appState = _AdminMonitorAppState();
    addTearDown(appState.dispose);

    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scrollController,
              child: const AdminDeployMonitor(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(appState.endpoints, contains('/api/admin/runtime-status'));
    expect(appState.endpoints, contains('/api/ci/flutter-apk/jobs'));
    expect(appState.paramsSeen['/api/ci/flutter-apk/jobs'], {'limit': 20});
    expect(find.text('런타임 불일치'), findsOneWidget);
    expect(find.text('불일치'), findsOneWidget);
    expect(find.textContaining('마지막 배포 manifest'), findsOneWidget);
    expect(find.text('release/ci-monitor'), findsOneWidget);
    expect(find.text('12345678'), findsOneWidget);
    expect(find.textContaining('1.2.3 (빌드 42)'), findsOneWidget);
    expect(find.textContaining('qa-admin'), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('release/ci-monitor'),
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.tap(find.text('release/ci-monitor'));
    await tester.pumpAndSettle();

    expect(
      appState.endpoints,
      contains('/api/ci/flutter-apk/jobs/job-123'),
    );
    expect(find.text('APK CI 작업 상세'), findsOneWidget);
    expect(find.text('cafe-bridge-1.2.3.apk'), findsOneWidget);
    expect(find.text('deploy-456'), findsOneWidget);
    expect(find.text('cafe-bridge/mobile'), findsOneWidget);
    expect(find.text('CI monitor release notes'), findsOneWidget);
    expect(find.text('https://downloads.example.test/app.apk'), findsOneWidget);
    expect(find.textContaining('not-rendered'), findsNothing);
  });

  testWidgets('runtime 403 is explicit and does not hide CI jobs or retry',
      (tester) async {
    final appState = _AdminMonitorAppState(
      forbiddenEndpoints: const <String>{'/api/admin/runtime-status'},
    );
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

    expect(find.text('권한 없음: 관리자 권한이 필요합니다.'), findsOneWidget);
    expect(find.text('release/ci-monitor'), findsOneWidget);
    expect(
      appState.endpoints
          .where((endpoint) => endpoint == '/api/admin/runtime-status'),
      hasLength(1),
    );

    await tester.pump(const Duration(seconds: 30));
    expect(
      appState.endpoints
          .where((endpoint) => endpoint == '/api/admin/runtime-status'),
      hasLength(1),
    );
  });
}
