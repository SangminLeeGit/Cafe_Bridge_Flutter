import 'dart:convert';

enum RuntimeSecretOperation { keep, replace, clear }

extension RuntimeSecretOperationApiValue on RuntimeSecretOperation {
  String get apiValue => switch (this) {
        RuntimeSecretOperation.keep => 'keep',
        RuntimeSecretOperation.replace => 'replace',
        RuntimeSecretOperation.clear => 'clear',
      };
}

class RuntimeSettingField {
  const RuntimeSettingField({
    required this.field,
    required this.label,
    required this.kind,
    required this.secret,
    required this.configured,
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.choices,
    required this.applyMode,
    required this.ownerPage,
  });

  final String field;
  final String label;
  final String kind;
  final bool secret;
  final bool? configured;
  final Object? value;
  final num? minimum;
  final num? maximum;
  final List<String> choices;
  final String applyMode;
  final String ownerPage;

  factory RuntimeSettingField.fromJson(Map<String, dynamic> json) {
    final field = _asString(json['field']);
    final kind = _asString(json['kind']);
    final secret = json['secret'] == true || kind == 'secret';
    final value = json['value'];
    if (secret && value != null) {
      throw const FormatException('Secret setting response was not redacted.');
    }
    return RuntimeSettingField(
      field: field,
      label: _asString(json['label'], fallback: field),
      kind: kind,
      secret: secret,
      configured: json['configured'] is bool ? json['configured'] as bool : null,
      value: secret ? null : value,
      minimum: _asNum(json['minimum']),
      maximum: _asNum(json['maximum']),
      choices: _asStringList(json['choices']),
      applyMode: _asString(json['apply_mode']),
      ownerPage: _asString(json['owner_page']),
    );
  }
}

class RuntimeSettingsGroup {
  const RuntimeSettingsGroup({
    required this.groupKey,
    required this.label,
    required this.adopted,
    required this.source,
    required this.activeVersion,
    required this.sessionEpoch,
    required this.pendingChangeId,
    required this.updatedAt,
    required this.config,
    required this.fields,
    required this.safeErrorCode,
  });

  final String groupKey;
  final String label;
  final bool adopted;
  final String source;
  final int activeVersion;
  final int sessionEpoch;
  final String? pendingChangeId;
  final String? updatedAt;

  /// Only values for declared non-secret fields are retained here.
  final Map<String, Object?> config;
  final List<RuntimeSettingField> fields;
  final String? safeErrorCode;

  factory RuntimeSettingsGroup.fromJson(Map<String, dynamic> json) {
    final fields = _asMapList(json['fields'])
        .map(RuntimeSettingField.fromJson)
        .toList(growable: false);
    final rawConfig = _asMap(json['config']);
    final safeConfig = <String, Object?>{};
    for (final field in fields.where((field) => !field.secret)) {
      if (rawConfig.containsKey(field.field)) {
        safeConfig[field.field] = rawConfig[field.field];
      } else if (field.value != null) {
        safeConfig[field.field] = field.value;
      }
    }
    return RuntimeSettingsGroup(
      groupKey: _asString(json['group_key']),
      label: _asString(json['label'], fallback: _asString(json['group_key'])),
      adopted: json['adopted'] == true,
      source: _asString(json['source']),
      activeVersion: _asInt(json['active_version']),
      sessionEpoch: _asInt(json['session_epoch']),
      pendingChangeId: _asNullableString(json['pending_change_id']),
      updatedAt: _asNullableString(json['updated_at']),
      config: Map<String, Object?>.unmodifiable(safeConfig),
      fields: fields,
      safeErrorCode: _safeCode(json['safe_error_code']),
    );
  }
}

class RuntimeSettingsChange {
  const RuntimeSettingsChange({
    required this.changeId,
    required this.groupKey,
    required this.baseVersion,
    required this.status,
    required this.actor,
    required this.requestId,
    required this.expiresAt,
    required this.appliedVersion,
    required this.safeErrorCode,
    required this.createdAt,
    required this.updatedAt,
    required this.probe,
  });

  final String changeId;
  final String groupKey;
  final int baseVersion;
  final String status;
  final String actor;
  final String requestId;
  final String? expiresAt;
  final int? appliedVersion;
  final String? safeErrorCode;
  final String? createdAt;
  final String? updatedAt;
  final RuntimeSettingsProbe? probe;

  factory RuntimeSettingsChange.fromJson(Map<String, dynamic> json) {
    final rawProbes = _asMap(json['probes']);
    return RuntimeSettingsChange(
      changeId: _asString(json['change_id']),
      groupKey: _asString(json['group_key']),
      baseVersion: _asInt(json['base_version']),
      status: _knownStatus(json['status']),
      actor: _asString(json['actor']),
      requestId: _asString(json['request_id']),
      expiresAt: _asNullableString(json['expires_at']),
      appliedVersion: _asNullableInt(json['applied_version']),
      safeErrorCode: _safeCode(json['safe_error_code']),
      createdAt: _asNullableString(json['created_at']),
      updatedAt: _asNullableString(json['updated_at']),
      probe: rawProbes.isEmpty ? null : RuntimeSettingsProbe.fromJson(rawProbes),
    );
  }
}

class RuntimeSettingsProbe {
  const RuntimeSettingsProbe({
    required this.status,
    required this.scope,
    required this.unchecked,
    required this.safeErrorCode,
    required this.latencyMs,
  });

  final String status;
  final List<String> scope;
  final List<String> unchecked;
  final String? safeErrorCode;
  final num? latencyMs;

  factory RuntimeSettingsProbe.fromJson(Map<String, dynamic> json) {
    return RuntimeSettingsProbe(
      status: _knownProbeStatus(json['status']),
      scope: _asStringList(json['scope']),
      unchecked: _asStringList(json['unchecked']),
      safeErrorCode: _safeCode(json['safe_error_code']),
      latencyMs: _asNum(json['latency_ms']),
    );
  }
}

class RuntimeSettingsHistoryItem {
  const RuntimeSettingsHistoryItem({
    required this.auditId,
    required this.changeId,
    required this.actor,
    required this.action,
    required this.version,
    required this.changedFields,
    required this.createdAt,
  });

  final String auditId;
  final String? changeId;
  final String actor;
  final String action;
  final int? version;
  final List<String> changedFields;
  final String? createdAt;

  factory RuntimeSettingsHistoryItem.fromJson(Map<String, dynamic> json) {
    return RuntimeSettingsHistoryItem(
      auditId: _asString(json['audit_id']),
      changeId: _asNullableString(json['change_id']),
      actor: _asString(json['actor']),
      action: _asString(json['action']),
      version: _asNullableInt(json['version']),
      changedFields: _asStringList(json['changed_fields']),
      createdAt: _asNullableString(json['created_at']),
    );
  }
}

class RuntimeSettingsWorker {
  const RuntimeSettingsWorker({
    required this.workerId,
    required this.role,
    required this.releaseSha,
    required this.freshness,
    required this.ageSeconds,
    required this.converged,
    required this.supportedSchemaVersion,
  });

  final String workerId;
  final String role;
  final String releaseSha;
  final String freshness;
  final num ageSeconds;
  final bool converged;
  final int supportedSchemaVersion;

  factory RuntimeSettingsWorker.fromJson(Map<String, dynamic> json) {
    return RuntimeSettingsWorker(
      workerId: _asString(json['worker_id']),
      role: _asString(json['role']),
      releaseSha: _asString(json['release_sha']),
      freshness: _knownFreshness(json['freshness']),
      ageSeconds: _asNum(json['age_seconds']) ?? 0,
      converged: json['converged'] == true,
      supportedSchemaVersion: _asInt(json['supported_schema_version']),
    );
  }
}

class RuntimeSettingsDiagnostics {
  const RuntimeSettingsDiagnostics({
    required this.environment,
    required this.checkedAt,
    required this.ok,
    required this.schemaCurrentVersion,
    required this.schemaExpectedVersion,
    required this.schemaCurrent,
    required this.normalWorkers,
    required this.convergedNormalWorkers,
    required this.allNormalWorkersConverged,
    required this.pendingGroups,
    required this.workers,
  });

  final String environment;
  final String checkedAt;
  final bool ok;
  final int schemaCurrentVersion;
  final int schemaExpectedVersion;
  final bool schemaCurrent;
  final int normalWorkers;
  final int convergedNormalWorkers;
  final bool allNormalWorkersConverged;
  final int pendingGroups;
  final List<RuntimeSettingsWorker> workers;

  factory RuntimeSettingsDiagnostics.fromJson(Map<String, dynamic> json) {
    final schema = _asMap(json['schema']);
    final summary = _asMap(json['summary']);
    return RuntimeSettingsDiagnostics(
      environment: _asString(json['environment']),
      checkedAt: _asString(json['checked_at']),
      ok: json['ok'] == true,
      schemaCurrentVersion: _asInt(schema['current_version']),
      schemaExpectedVersion: _asInt(schema['expected_version']),
      schemaCurrent: schema['current'] == true,
      normalWorkers: _asInt(summary['normal_workers']),
      convergedNormalWorkers: _asInt(summary['converged_normal_workers']),
      allNormalWorkersConverged:
          summary['all_normal_workers_converged'] == true,
      pendingGroups: _asInt(summary['pending_groups']),
      workers: _asMapList(json['workers'])
          .map(RuntimeSettingsWorker.fromJson)
          .toList(growable: false),
    );
  }
}

class RuntimeSettingsNotice {
  const RuntimeSettingsNotice({required this.text, required this.isError});

  final String text;
  final bool isError;
}

class RuntimeSettingsValidation {
  const RuntimeSettingsValidation(this.errors);

  final Map<String, String> errors;
  bool get isValid => errors.isEmpty;
}

RuntimeSettingsValidation validateRuntimeSettingsDraft({
  required List<RuntimeSettingField> fields,
  required Map<String, Object?> config,
  required Map<String, RuntimeSecretOperation> secretOperations,
  required Map<String, String> secretValues,
}) {
  final errors = <String, String>{};
  for (final field in fields) {
    if (field.secret) {
      if (secretOperations[field.field] == RuntimeSecretOperation.replace &&
          (secretValues[field.field] ?? '').isEmpty) {
        errors[field.field] = '새 보안 값을 입력하세요.';
      }
      continue;
    }

    final value = config[field.field];
    final invalid = switch (field.kind) {
      'boolean' => value is! bool,
      'integer' =>
        value is! int ||
            (field.minimum != null && value < field.minimum!) ||
            (field.maximum != null && value > field.maximum!),
      'string' => value is! String,
      'url' => !_isHttpsUrl(value),
      'enum' => !field.choices.contains(value?.toString() ?? ''),
      'object' => value is! Map,
      _ => true,
    };
    if (invalid) {
      errors[field.field] = _validationMessage(field);
    }
  }
  return RuntimeSettingsValidation(Map<String, String>.unmodifiable(errors));
}

bool runtimeSettingsDraftChanged({
  required Map<String, Object?> config,
  required Map<String, Object?> baseline,
  required Map<String, RuntimeSecretOperation> secretOperations,
}) {
  if (jsonEncode(config) != jsonEncode(baseline)) return true;
  return secretOperations.values
      .any((operation) => operation != RuntimeSecretOperation.keep);
}

RuntimeSettingsNotice runtimeSettingsActionNotice(
  String action,
  Map<String, dynamic> result,
) {
  if (action == 'prepare') {
    return RuntimeSettingsNotice(
      text: result['adopted'] == true
          ? '현재 설정을 관리형 ledger로 도입했습니다.'
          : '설정 변경 준비를 완료했습니다.',
      isError: false,
    );
  }
  if (action == 'test') {
    final probe = _asMap(result['probe']);
    switch (_knownProbeStatus(probe['status'])) {
      case 'passed':
        return const RuntimeSettingsNotice(
          text: '연결 검증을 완료했습니다.',
          isError: false,
        );
      case 'partial':
        return const RuntimeSettingsNotice(
          text: '지원되는 범위의 연결 검증을 완료했습니다.',
          isError: false,
        );
      case 'deferred':
        return const RuntimeSettingsNotice(
          text: '연결 검증이 안전한 적용 시점까지 보류되었습니다.',
          isError: false,
        );
      default:
        return const RuntimeSettingsNotice(
          text: '연결 검증에 실패했습니다. 설정 상태를 확인하세요.',
          isError: true,
        );
    }
  }

  switch (_knownActionStatus(result['status'])) {
    case 'applied':
      return RuntimeSettingsNotice(
        text: action == 'rollback' ? '롤백을 적용했습니다.' : '설정을 적용했습니다.',
        isError: false,
      );
    case 'cancelled':
      return const RuntimeSettingsNotice(
        text: '설정 변경을 취소했습니다.',
        isError: false,
      );
    case 'queued_drain':
      return const RuntimeSettingsNotice(
        text: 'EasyPOS 변경을 대기열에 넣었습니다. POS drain 후 적용됩니다.',
        isError: false,
      );
    case 'busy':
      return const RuntimeSettingsNotice(
        text: '진행 중인 POS 작업이 있어 적용을 기다리고 있습니다.',
        isError: false,
      );
    case 'blocked_uncertain':
      return const RuntimeSettingsNotice(
        text: '결과가 불확실한 POS 작업이 있어 적용을 차단했습니다.',
        isError: true,
      );
    default:
      return const RuntimeSettingsNotice(
        text: '설정 작업을 완료하지 못했습니다. 변경 상태를 확인하세요.',
        isError: true,
      );
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _asMapList(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

List<String> _asStringList(Object? value) {
  if (value is! List) return const <String>[];
  return value.map((item) => item.toString()).toList(growable: false);
}

String _asString(Object? value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

String? _asNullableString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int _asInt(Object? value) {
  return _asNullableInt(value) ?? 0;
}

int? _asNullableInt(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  if (value is String) return int.tryParse(value);
  return null;
}

num? _asNum(Object? value) {
  if (value is num && value.isFinite) return value;
  if (value is String) return num.tryParse(value);
  return null;
}

String? _safeCode(Object? value) {
  final code = value?.toString().trim();
  if (code == null || !RegExp(r'^[a-z0-9_]{1,80}$').hasMatch(code)) {
    return null;
  }
  return code;
}

String _knownStatus(Object? value) {
  const statuses = <String>{
    'prepared',
    'testing',
    'ready',
    'queued_drain',
    'applied',
    'cancelled',
    'expired',
    'test_failed',
    'activation_failed',
  };
  final status = value?.toString() ?? '';
  return statuses.contains(status) ? status : 'unknown';
}

String _knownProbeStatus(Object? value) {
  const statuses = <String>{'passed', 'partial', 'failed', 'deferred'};
  final status = value?.toString() ?? '';
  return statuses.contains(status) ? status : 'unknown';
}

String _knownFreshness(Object? value) {
  const values = <String>{'normal', 'stale', 'excluded'};
  final freshness = value?.toString() ?? '';
  return values.contains(freshness) ? freshness : 'unknown';
}

String _knownActionStatus(Object? value) {
  const statuses = <String>{
    'applied',
    'queued_drain',
    'busy',
    'blocked_uncertain',
    'failed',
    'cancelled',
  };
  final status = value?.toString() ?? '';
  return statuses.contains(status) ? status : 'unknown';
}

bool _isHttpsUrl(Object? value) {
  if (value is! String) return false;
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}

String _validationMessage(RuntimeSettingField field) {
  return switch (field.kind) {
    'boolean' => '${field.label}: 참/거짓 값을 선택하세요.',
    'integer' => '${field.label}: 정수 범위를 확인하세요.',
    'string' => '${field.label}: 문자열을 입력하세요.',
    'url' => '${field.label}: HTTPS URL 형식을 확인하세요.',
    'enum' => '${field.label}: 목록에서 선택하세요.',
    'object' => '${field.label}: JSON 객체를 입력하세요.',
    _ => '${field.label}: 지원하지 않는 설정 형식입니다.',
  };
}
