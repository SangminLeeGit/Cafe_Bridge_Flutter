import 'api_contracts.dart';

class ServiceHealthSetting {
  final String key;
  final String label;
  final bool enabled;
  final String endpoint;
  final int timeoutMs;
  final int intervalSeconds;
  final String? componentKey;
  final String source;

  const ServiceHealthSetting({
    required this.key,
    required this.label,
    required this.enabled,
    required this.endpoint,
    required this.timeoutMs,
    required this.intervalSeconds,
    required this.componentKey,
    required this.source,
  });

  factory ServiceHealthSetting.fromJson(Map<String, dynamic> json) {
    return ServiceHealthSetting(
      key: asString(json['key']),
      label: asString(json['label']),
      enabled: asBool(json['enabled']),
      endpoint: asString(json['endpoint']),
      timeoutMs: asInt(json['timeout_ms']),
      intervalSeconds: asInt(json['interval_seconds']),
      componentKey: asNullableString(json['component_key']),
      source: asString(json['source']),
    );
  }

  ServiceHealthSetting copyWith({
    bool? enabled,
    String? endpoint,
    int? timeoutMs,
    int? intervalSeconds,
  }) {
    return ServiceHealthSetting(
      key: key,
      label: label,
      enabled: enabled ?? this.enabled,
      endpoint: endpoint ?? this.endpoint,
      timeoutMs: timeoutMs ?? this.timeoutMs,
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      componentKey: componentKey,
      source: source,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'label': label,
      'enabled': enabled,
      'endpoint': endpoint,
      'timeout_ms': timeoutMs,
      'interval_seconds': intervalSeconds,
      'component_key': componentKey,
      'source': source,
    };
  }
}

class ServiceHealthTarget {
  final String key;
  final String label;
  final bool enabled;
  final String endpoint;
  final String? componentKey;
  final String state;
  final String reason;
  final String? healthStatus;
  final String? lastCheckedAt;
  final double? responseTimeMs;
  final int? httpStatus;
  final Map<String, dynamic> checks;
  final String message;

  const ServiceHealthTarget({
    required this.key,
    required this.label,
    required this.enabled,
    required this.endpoint,
    required this.componentKey,
    required this.state,
    required this.reason,
    required this.healthStatus,
    required this.lastCheckedAt,
    required this.responseTimeMs,
    required this.httpStatus,
    required this.checks,
    required this.message,
  });

  factory ServiceHealthTarget.fromJson(Map<String, dynamic> json) {
    return ServiceHealthTarget(
      key: asString(json['key']),
      label: asString(json['label']),
      enabled: asBool(json['enabled']),
      endpoint: asString(json['endpoint']),
      componentKey: asNullableString(json['component_key']),
      state: asString(json['state']),
      reason: asString(json['reason']),
      healthStatus: asNullableString(json['health_status']),
      lastCheckedAt: asNullableString(json['last_checked_at']),
      responseTimeMs: json['response_time_ms'] == null
          ? null
          : asDouble(json['response_time_ms']),
      httpStatus:
          json['http_status'] == null ? null : asInt(json['http_status']),
      checks: asMap(json['checks']),
      message: asString(json['message']),
    );
  }
}

class ServiceHealthSnapshot {
  final String version;
  final String generatedAt;
  final List<ServiceHealthSetting> settings;
  final List<ServiceHealthTarget> targets;

  const ServiceHealthSnapshot({
    required this.version,
    required this.generatedAt,
    required this.settings,
    required this.targets,
  });

  factory ServiceHealthSnapshot.fromJson(Map<String, dynamic> json) {
    return ServiceHealthSnapshot(
      version: asString(json['version']),
      generatedAt: asString(json['generated_at']),
      settings: requireListOfMaps(json, 'settings')
          .map(ServiceHealthSetting.fromJson)
          .toList(growable: false),
      targets: requireListOfMaps(json, 'targets')
          .map(ServiceHealthTarget.fromJson)
          .toList(growable: false),
    );
  }
}
