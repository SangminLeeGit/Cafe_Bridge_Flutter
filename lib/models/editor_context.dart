import 'api_contracts.dart';

class EditorCapabilityDecision {
  final bool enabled;
  final String reasonCode;
  final String message;
  final List<String> supportedColumns;

  const EditorCapabilityDecision({
    required this.enabled,
    required this.reasonCode,
    required this.message,
    required this.supportedColumns,
  });

  factory EditorCapabilityDecision.fromJson(Map<String, dynamic> json) {
    final rawColumns = json['supported_columns'];
    return EditorCapabilityDecision(
      enabled: asBool(json['enabled']),
      reasonCode: asString(json['reason_code']),
      message: asString(json['message']),
      supportedColumns: rawColumns is List
          ? rawColumns
              .map((column) => column.toString().trim())
              .where((column) => column.isNotEmpty)
              .toList(growable: false)
          : const <String>[],
    );
  }

  bool allowsColumn(String column) =>
      enabled && supportedColumns.contains(column);
}

class EditorContext {
  final String? scopeId;
  final String scopeStatus;
  final String role;
  final bool sourceReady;
  final Map<String, EditorCapabilityDecision> capabilities;

  const EditorContext({
    required this.scopeId,
    required this.scopeStatus,
    required this.role,
    required this.sourceReady,
    required this.capabilities,
  });

  factory EditorContext.fromJson(Map<String, dynamic> json) {
    final rawCapabilities = json['capabilities'];
    final capabilities = <String, EditorCapabilityDecision>{};
    if (rawCapabilities is Map) {
      rawCapabilities.forEach((name, value) {
        if (value is Map) {
          capabilities[name.toString()] =
              EditorCapabilityDecision.fromJson(asMap(value));
        }
      });
    }
    return EditorContext(
      scopeId: asNullableString(json['scope_id']),
      scopeStatus: asString(json['scope_status']),
      role: asString(json['role']),
      sourceReady: asBool(json['source_ready']),
      capabilities: Map.unmodifiable(capabilities),
    );
  }

  EditorCapabilityDecision? capability(String name) => capabilities[name];

  bool canApplyPrice(String column) =>
      capability('apply_price')?.allowsColumn(column) ?? false;

  String priceApplyBlockReason(String column) {
    final decision = capability('apply_price');
    if (decision == null) {
      return '서버에서 가격 반영 기능 상태를 확인할 수 없습니다. 실제 반영은 차단되었습니다.';
    }
    if (!decision.enabled) {
      if (decision.reasonCode == 'capability_disabled') {
        return '서버가 가격 실제 반영을 허용하지 않습니다. 현재는 미리보기만 사용할 수 있습니다.';
      }
      if (decision.message.trim().isNotEmpty) return decision.message;
      return '서버에서 가격 실제 반영을 사용할 수 없습니다. (${decision.reasonCode})';
    }
    if (!decision.supportedColumns.contains(column)) {
      return '서버가 이 가격 항목의 실제 반영을 지원하지 않습니다. 미리보기만 사용할 수 있습니다.';
    }
    return '';
  }
}
