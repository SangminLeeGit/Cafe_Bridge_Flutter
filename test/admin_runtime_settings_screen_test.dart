import 'package:cafe_bridge_flutter/models/admin_runtime_settings.dart';
import 'package:cafe_bridge_flutter/screens/admin_runtime_settings.dart';
import 'package:cafe_bridge_flutter/services/api.dart';
import 'package:cafe_bridge_flutter/services/cache_store.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const String _secretValue = 'BOT_TOKEN_MUST_NEVER_BE_RENDERED';
const String _passwordValue = 'admin-current-password';

Map<String, dynamic> _field({
  required String field,
  required String kind,
  required Object? value,
  bool secret = false,
  bool? configured,
  num? minimum,
  num? maximum,
  List<String> choices = const <String>[],
}) {
  return <String, dynamic>{
    'field': field,
    'label': field,
    'kind': kind,
    'secret': secret,
    'configured': configured,
    'value': value,
    'minimum': minimum,
    'maximum': maximum,
    'choices': choices,
    'apply_mode': 'next_operation',
    'owner_page': '/admin/system-settings',
  };
}

Map<String, dynamic> _groupJson({
  int activeVersion = 2,
  String? pendingChangeId,
}) {
  return <String, dynamic>{
    'group_key': 'telegram',
    'label': 'Telegram',
    'adopted': true,
    'source': 'managed',
    'active_version': activeVersion,
    'session_epoch': 3,
    'pending_change_id': pendingChangeId,
    'updated_at': '2026-11-20T10:00:00Z',
    'config': <String, dynamic>{
      'endpoint': 'https://api.example.test/bot',
      'enabled': true,
      'timeout': 15,
      'mode': 'poll',
      'metadata': <String, dynamic>{'region': 'seoul'},
    },
    'fields': <Map<String, dynamic>>[
      _field(
        field: 'endpoint',
        kind: 'url',
        value: 'https://api.example.test/bot',
      ),
      _field(field: 'enabled', kind: 'boolean', value: true),
      _field(
        field: 'timeout',
        kind: 'integer',
        value: 15,
        minimum: 1,
        maximum: 120,
      ),
      _field(
        field: 'mode',
        kind: 'enum',
        value: 'poll',
        choices: const <String>['poll', 'push'],
      ),
      _field(
        field: 'metadata',
        kind: 'object',
        value: <String, dynamic>{'region': 'seoul'},
      ),
      _field(
        field: 'bot_token',
        kind: 'secret',
        value: null,
        secret: true,
        configured: true,
      ),
    ],
  };
}

Map<String, dynamic> _changeJson({
  String id = 'change-1',
  String status = 'prepared',
  String groupKey = 'telegram',
  int baseVersion = 2,
  Map<String, dynamic>? probes,
}) {
  return <String, dynamic>{
    'change_id': id,
    'environment': 'dev',
    'group_key': groupKey,
    'base_version': baseVersion,
    'status': status,
    'proposed_config': <String, dynamic>{},
    'proposed_secrets': <String, dynamic>{
      'bot_token': <String, dynamic>{
        'operation': 'replace',
        'configured': true,
        'value': null,
      },
    },
    'probes': probes ?? <String, dynamic>{},
    'actor': 'qa-admin',
    'reason': 'rotated integration credential',
    'request_id': 'request-1',
    'expires_at': '2026-11-22T12:00:00Z',
    'applied_version': null,
    'safe_error_code': null,
    'created_at': '2026-11-22T10:00:00Z',
    'updated_at': '2026-11-22T10:00:00Z',
  };
}

Map<String, dynamic> _historyJson() {
  return <String, dynamic>{
    'environment': 'dev',
    'group_key': 'telegram',
    'items': <Map<String, dynamic>>[
      <String, dynamic>{
        'audit_id': 'audit-1',
        'change_id': 'change-old',
        'actor': 'qa-admin',
        'action': 'apply',
        'version': 1,
        'changed_fields': <String>['endpoint', 'bot_token'],
        'redacted_diff': <String, dynamic>{},
        'created_at': '2026-11-19T10:00:00Z',
      },
    ],
  };
}

Map<String, dynamic> _diagnosticsJson() {
  return <String, dynamic>{
    'environment': 'dev',
    'checked_at': '2026-11-22T10:00:00Z',
    'ok': true,
    'schema': <String, dynamic>{
      'current_version': 7,
      'expected_version': 7,
      'current': true,
    },
    'groups': <dynamic>[],
    'workers': <Map<String, dynamic>>[
      <String, dynamic>{
        'worker_id': 'worker-a',
        'boot_id': 'boot-1',
        'role': 'web',
        'release_sha': '0123456789abcdef0123456789abcdef01234567',
        'supported_schema_version': 7,
        'last_seen_at': '2026-11-22T10:00:00Z',
        'age_seconds': 5,
        'freshness': 'normal',
        'observed_versions': <String, int>{'telegram': 2},
        'revision_lag': <String, int>{},
        'converged': true,
      },
    ],
    'summary': <String, dynamic>{
      'worker_freshness': <String, int>{
        'normal': 1,
        'stale': 0,
        'excluded': 0,
      },
      'normal_workers': 1,
      'converged_normal_workers': 1,
      'all_normal_workers_converged': true,
      'pending_groups': 0,
      'change_status': <String, int>{},
      'operation_state': <String, int>{},
    },
  };
}

class _RuntimeSettingsAppState extends AppState {
  _RuntimeSettingsAppState({
    this.admin = true,
    this.listedVersion = 2,
    this.detailVersion = 2,
    String? initialChangeStatus,
    this.failMutationAt,
  }) : _openChange = initialChangeStatus == null
            ? null
            : _changeJson(status: initialChangeStatus);

  final bool admin;
  int listedVersion;
  int detailVersion;
  final String? failMutationAt;

  final List<String> getEndpoints = <String>[];
  final List<Map<String, Object?>?> getParams =
      <Map<String, Object?>?>[];
  final List<ApiCachePolicy?> cachePolicies = <ApiCachePolicy?>[];
  final List<String> postEndpoints = <String>[];
  final List<Map<String, dynamic>> postBodies = <Map<String, dynamic>>[];

  Map<String, dynamic>? _openChange;

  @override
  bool get hasAdminAccess => admin;

  @override
  Future<CachedDataResult<T>> fetchMapParsed<T>(
    String endpoint, {
    Map<String, Object?>? params,
    required T Function(Map<String, dynamic> json) parser,
    Duration cacheTtl = const Duration(minutes: 30),
    bool allowStaleOnError = true,
    ApiCachePolicy? cachePolicy,
  }) async {
    getEndpoints.add(endpoint);
    getParams.add(params == null ? null : Map<String, Object?>.of(params));
    cachePolicies.add(cachePolicy);
    final Map<String, dynamic> response;
    if (endpoint == '/api/admin/runtime-settings/groups') {
      response = <String, dynamic>{
        'environment': 'dev',
        'groups': <Map<String, dynamic>>[
          _groupJson(activeVersion: listedVersion),
        ],
      };
    } else if (endpoint == '/api/admin/runtime-settings/diagnostics') {
      response = _diagnosticsJson();
    } else if (endpoint == '/api/admin/runtime-settings/groups/telegram') {
      response = <String, dynamic>{
        'environment': 'dev',
        'group': _groupJson(
          activeVersion: detailVersion,
          pendingChangeId: _openChange == null ? null : 'change-1',
        ),
        'open_change': _openChange,
      };
    } else if (endpoint ==
        '/api/admin/runtime-settings/groups/telegram/history') {
      response = _historyJson();
    } else if (endpoint == '/api/admin/runtime-settings/changes/change-1') {
      response = <String, dynamic>{'change': _openChange ?? _changeJson()};
    } else {
      throw ApiException('Unexpected read endpoint: $endpoint');
    }
    return CachedDataResult<T>(
      data: parser(response),
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
    final requestBody =
        body == null ? <String, dynamic>{} : Map<String, dynamic>.of(body);
    postEndpoints.add(endpoint);
    postBodies.add(requestBody);
    if (endpoint == failMutationAt) {
      throw ApiException(
        'unsafe server detail echoed $_secretValue and $_passwordValue',
        statusCode: 500,
      );
    }
    if (endpoint.endsWith('/validate')) {
      return <String, dynamic>{
        'valid': true,
        'group_key': 'telegram',
        'config': requestBody['config'],
        'secrets': <String, dynamic>{},
      };
    }
    if (endpoint.endsWith('/prepare')) {
      _openChange = _changeJson();
      return <String, dynamic>{
        'adopted': false,
        'change': _openChange,
      };
    }
    if (endpoint.endsWith('/test')) {
      _openChange = _changeJson(
        status: 'ready',
        probes: <String, dynamic>{
          'status': 'passed',
          'scope': <String>['getMe'],
          'unchecked': <String>[],
          'safe_error_code': null,
          'latency_ms': 4,
        },
      );
      return <String, dynamic>{
        'change': _openChange,
        'probe': <String, dynamic>{
          'status': 'passed',
          'scope': <String>['getMe'],
          'unchecked': <String>[],
          'safe_error_code': null,
          'latency_ms': 4,
        },
      };
    }
    if (endpoint.endsWith('/apply')) {
      _openChange = null;
      detailVersion += 1;
      listedVersion = detailVersion;
      return <String, dynamic>{
        'status': 'applied',
        'change': _changeJson(status: 'applied'),
      };
    }
    if (endpoint.endsWith('/cancel')) {
      _openChange = null;
      return <String, dynamic>{
        'status': 'cancelled',
        'change': _changeJson(status: 'cancelled'),
      };
    }
    if (endpoint.endsWith('/rollback')) {
      detailVersion += 1;
      listedVersion = detailVersion;
      return <String, dynamic>{
        'status': 'applied',
        'change': _changeJson(status: 'applied'),
      };
    }
    throw ApiException('Unexpected write endpoint: $endpoint');
  }

}

Future<void> _mountScreen(
  WidgetTester tester,
  _RuntimeSettingsAppState state,
) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(state.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const MaterialApp(home: AdminRuntimeSettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _confirmWithPassword(
  WidgetTester tester, {
  String password = _passwordValue,
}) async {
  await tester.ensureVisible(find.byKey(const Key('runtime-settings-password')));
  await tester.enterText(
    find.byKey(const Key('runtime-settings-password')),
    password,
  );
  await tester.pump();
  await tester.tap(
    find.byKey(const Key('runtime-settings-confirm-action')),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('runtime settings model redacts secrets and validates typed values', () {
    final unsafeGroupJson = _groupJson();
    (unsafeGroupJson['config'] as Map<String, dynamic>)['bot_token'] =
        _secretValue;
    final group = RuntimeSettingsGroup.fromJson(unsafeGroupJson);
    expect(group.config.containsKey('bot_token'), isFalse);
    expect(
      group.fields.singleWhere((field) => field.secret).value,
      isNull,
    );
    expect(
      validateRuntimeSettingsDraft(
        fields: group.fields,
        config: group.config,
        secretOperations: const <String, RuntimeSecretOperation>{},
        secretValues: const <String, String>{},
      ).isValid,
      isTrue,
    );
    expect(
      () => RuntimeSettingField.fromJson(
        _field(
          field: 'bot_token',
          kind: 'secret',
          value: _secretValue,
          secret: true,
          configured: true,
        ),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.toString(),
          'message',
          isNot(contains(_secretValue)),
        ),
      ),
    );

    final validation = validateRuntimeSettingsDraft(
      fields: group.fields,
      config: <String, Object?>{
        'endpoint': 'http://not-secure.example.test',
        'enabled': 'true',
        'timeout': 500,
        'mode': 'invalid',
        'metadata': <String>['not', 'an object'],
      },
      secretOperations: <String, RuntimeSecretOperation>{
        'bot_token': RuntimeSecretOperation.replace,
      },
      secretValues: const <String, String>{'bot_token': ''},
    );
    expect(validation.isValid, isFalse);
    expect(
      validation.errors.keys,
      containsAll(<String>[
        'endpoint',
        'enabled',
        'timeout',
        'mode',
        'metadata',
        'bot_token',
      ]),
    );
    expect(
      runtimeSettingsDraftChanged(
        config: group.config,
        baseline: group.config,
        secretOperations: const <String, RuntimeSecretOperation>{
          'bot_token': RuntimeSecretOperation.clear,
        },
      ),
      isTrue,
    );
  });

  testWidgets('non-admin is denied without issuing runtime-settings requests',
      (tester) async {
    final state = _RuntimeSettingsAppState(admin: false);
    await _mountScreen(tester, state);

    expect(
      find.textContaining('시스템 런타임 설정은 관리자 전용입니다.'),
      findsOneWidget,
    );
    expect(state.getEndpoints, isEmpty);
    expect(state.postEndpoints, isEmpty);
  });

  testWidgets('admin loads diagnostics, detail and history without showing secrets',
      (tester) async {
    final state = _RuntimeSettingsAppState();
    await _mountScreen(tester, state);

    expect(
      state.getEndpoints,
      containsAll(<String>[
        '/api/admin/runtime-settings/groups',
        '/api/admin/runtime-settings/diagnostics',
        '/api/admin/runtime-settings/groups/telegram',
        '/api/admin/runtime-settings/groups/telegram/history',
      ]),
    );
    expect(
      state.getParams[state.getEndpoints.indexOf(
        '/api/admin/runtime-settings/groups/telegram/history',
      )],
      <String, Object?>{'limit': 50},
    );
    expect(
      state.cachePolicies,
      everyElement(ApiCachePolicy.none),
    );
    expect(find.text('Worker 수렴 상태'), findsOneWidget);
    expect(find.text('v7 / v7'), findsOneWidget);
    expect(find.text('변경 이력'), findsOneWidget);
    expect(find.textContaining('bot_token'), findsAtLeastNWidgets(1));
    expect(find.text(_secretValue), findsNothing);
  });

  testWidgets('prepare validates, reauthenticates, and sends write-only secret',
      (tester) async {
    final state = _RuntimeSettingsAppState();
    await _mountScreen(tester, state);

    final operation = find.byKey(
      const Key('runtime-secret-operation-bot_token'),
    );
    await tester.ensureVisible(operation);
    await tester.tap(operation);
    await tester.pumpAndSettle();
    await tester.tap(find.text('교체').last);
    await tester.pumpAndSettle();

    final replacement = find.byType(TextField).last;
    await tester.ensureVisible(replacement);
    await tester.enterText(replacement, _secretValue);
    await tester.pump();
    final prepare = find.byKey(const Key('runtime-settings-prepare'));
    await tester.ensureVisible(prepare);
    await tester.tap(prepare);
    await tester.pumpAndSettle();
    await _confirmWithPassword(tester);

    expect(
      state.postEndpoints,
      containsAll(<String>[
        '/api/admin/runtime-settings/groups/telegram/validate',
        '/api/admin/runtime-settings/groups/telegram/prepare',
      ]),
    );
    final validateBody = state.postBodies[0];
    final prepareBody = state.postBodies[1];
    expect(validateBody['reauth_password'], _passwordValue);
    expect(prepareBody['reauth_password'], _passwordValue);
    expect(prepareBody['base_version'], 2);
    expect(
      (prepareBody['secrets'] as Map)['bot_token'],
      <String, Object?>{
        'operation': 'replace',
        'value': _secretValue,
      },
    );
    expect(
      prepareBody['request_id'],
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(find.text(_secretValue), findsNothing);
    expect(find.byKey(const Key('runtime-settings-password')), findsNothing);
    expect(find.text('설정 변경 준비를 완료했습니다.'), findsOneWidget);
  });

  testWidgets('secret clear sends an operation marker and no value',
      (tester) async {
    final state = _RuntimeSettingsAppState();
    await _mountScreen(tester, state);

    final operation = find.byKey(
      const Key('runtime-secret-operation-bot_token'),
    );
    await tester.ensureVisible(operation);
    await tester.tap(operation);
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제').last);
    await tester.pumpAndSettle();

    final prepare = find.byKey(const Key('runtime-settings-prepare'));
    await tester.ensureVisible(prepare);
    await tester.tap(prepare);
    await tester.pumpAndSettle();
    await _confirmWithPassword(tester);

    expect(
      (state.postBodies[1]['secrets'] as Map)['bot_token'],
      <String, Object?>{'operation': 'clear'},
    );
  });

  testWidgets('test and apply each require reauthentication',
      (tester) async {
    final state = _RuntimeSettingsAppState(
      initialChangeStatus: 'prepared',
    );
    await _mountScreen(tester, state);

    final testButton = find.widgetWithText(OutlinedButton, '연결 테스트');
    await tester.ensureVisible(testButton);
    await tester.tap(testButton);
    await tester.pumpAndSettle();
    await _confirmWithPassword(tester);
    expect(state.postEndpoints, contains('/api/admin/runtime-settings/changes/change-1/test'));
    expect(state.postBodies.last['reauth_password'], _passwordValue);
    expect(find.text('연결 검증을 완료했습니다.'), findsOneWidget);

    final applyButton = find.widgetWithText(FilledButton, '적용');
    await tester.ensureVisible(applyButton);
    await tester.tap(applyButton);
    await tester.pumpAndSettle();
    await _confirmWithPassword(tester);
    expect(state.postEndpoints, contains('/api/admin/runtime-settings/changes/change-1/apply'));
    expect(state.postBodies.last['reauth_password'], _passwordValue);
    expect(find.text('설정을 적용했습니다.'), findsOneWidget);
  });

  testWidgets('cancel and rollback use reauth and historical target version',
      (tester) async {
    final state = _RuntimeSettingsAppState(
      initialChangeStatus: 'prepared',
    );
    await _mountScreen(tester, state);

    final cancelButton = find.widgetWithText(OutlinedButton, '취소');
    await tester.ensureVisible(cancelButton);
    await tester.tap(cancelButton);
    await tester.pumpAndSettle();
    await _confirmWithPassword(tester);
    expect(state.postEndpoints, contains('/api/admin/runtime-settings/changes/change-1/cancel'));
    expect(state.postBodies.last['reauth_password'], _passwordValue);

    final rollbackButton = find.byKey(
      const Key('runtime-settings-rollback-1'),
    );
    await tester.ensureVisible(rollbackButton);
    await tester.tap(rollbackButton);
    await tester.pumpAndSettle();
    await _confirmWithPassword(tester);
    expect(
      state.postEndpoints,
      contains('/api/admin/runtime-settings/groups/telegram/rollback'),
    );
    expect(state.postBodies.last['target_version'], 1);
    expect(state.postBodies.last['reauth_password'], _passwordValue);
  });

  testWidgets('stale group version blocks prepare without a write',
      (tester) async {
    final state = _RuntimeSettingsAppState(
      listedVersion: 3,
      detailVersion: 2,
    );
    await _mountScreen(tester, state);

    expect(
      find.textContaining('다른 변경으로 활성 버전이 v3로 바뀌었습니다'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('runtime-settings-prepare')), findsNothing);
    expect(state.postEndpoints, isEmpty);
  });

  testWidgets('raw secret-bearing mutation errors are replaced with safe text',
      (tester) async {
    final state = _RuntimeSettingsAppState(
      failMutationAt: '/api/admin/runtime-settings/groups/telegram/validate',
    );
    await _mountScreen(tester, state);

    final operation = find.byKey(
      const Key('runtime-secret-operation-bot_token'),
    );
    await tester.ensureVisible(operation);
    await tester.tap(operation);
    await tester.pumpAndSettle();
    await tester.tap(find.text('교체').last);
    await tester.pumpAndSettle();
    final replacement = find.byType(TextField).last;
    await tester.ensureVisible(replacement);
    await tester.enterText(replacement, _secretValue);
    await tester.pump();

    final prepare = find.byKey(const Key('runtime-settings-prepare'));
    await tester.ensureVisible(prepare);
    await tester.tap(prepare);
    await tester.pumpAndSettle();
    await _confirmWithPassword(tester);

    expect(find.text(_secretValue), findsNothing);
    expect(find.text(_passwordValue), findsNothing);
    expect(find.textContaining('unsafe server detail'), findsNothing);
    expect(
      find.text('설정 변경을 준비하지 못했습니다. 설정 상태를 새로고침하세요.'),
      findsOneWidget,
    );
  });

  testWidgets('change status refresh uses the change detail endpoint',
      (tester) async {
    final state = _RuntimeSettingsAppState(
      initialChangeStatus: 'prepared',
    );
    await _mountScreen(tester, state);

    final refresh = find.widgetWithText(OutlinedButton, '상태 새로고침');
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await tester.pumpAndSettle();

    expect(
      state.getEndpoints,
      contains('/api/admin/runtime-settings/changes/change-1'),
    );
  });
}
