Map<String, dynamic> asMap(Object? source) {
  if (source is Map) return Map<String, dynamic>.from(source);
  return const {};
}

List<Map<String, dynamic>> asListOfMaps(Object? source) {
  if (source is! List) return const [];
  return source
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

Map<String, int> asIntMap(Object? source) {
  if (source is! Map) return const {};
  final result = <String, int>{};
  source.forEach((key, value) => result[key.toString()] = asInt(value));
  return result;
}

String asString(Object? value) => value?.toString() ?? '';

String? asNullableString(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

int asInt(Object? value) {
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is String) return int.tryParse(value.replaceAll(',', '')) ?? 0;
  return 0;
}

int? asNullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is String) {
    final parsed = int.tryParse(value.replaceAll(',', ''));
    return parsed;
  }
  return null;
}

double asDouble(Object? value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value.replaceAll(',', '')) ?? 0;
  return 0;
}

bool asBool(Object? value, {bool defaultValue = false}) {
  if (value == null) return defaultValue;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return defaultValue;
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') return true;
    if (normalized == 'false' || normalized == '0' || normalized == 'no') return false;
  }
  return defaultValue;
}

DateTime? asDateTime(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

String formatVersionDisplay(
  String version,
  int? build, {
  String fallback = '-',
}) {
  final normalizedVersion = version.trim();
  if (normalizedVersion.isEmpty) {
    return fallback;
  }
  final normalizedBuild = build ?? 0;
  if (normalizedBuild > 0) {
    return '$normalizedVersion (빌드 $normalizedBuild)';
  }
  return normalizedVersion;
}

class AppUpdateInfo {
  final String latestVersion;
  final int latestBuild;
  final bool updateAvailable;
  final String downloadUrl;
  final String releaseNotes;
  final String sha256;
  final int fileSize;
  final bool forceUpdate;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.latestBuild,
    required this.updateAvailable,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.sha256,
    required this.fileSize,
    required this.forceUpdate,
  });

  factory AppUpdateInfo.fromJson(
    Map<String, dynamic> json, {
    String fallbackVersion = '1.0.0',
  }) {
    final latestVersion = asString(json['latest_version']).trim();
    return AppUpdateInfo(
      latestVersion: latestVersion.isEmpty ? fallbackVersion : latestVersion,
      latestBuild: asInt(json['latest_build']),
      updateAvailable: asBool(json['update_available']),
      downloadUrl: asString(json['download_url']),
      releaseNotes: asString(json['release_notes']),
      sha256: asString(json['sha256']),
      fileSize: asInt(json['file_size']),
      forceUpdate: asBool(json['force_update']) || asBool(json['required_update']),
    );
  }

  bool get hasDownloadUrl => downloadUrl.trim().isNotEmpty;
  String get displayLabel => formatVersionDisplay(latestVersion, latestBuild);
}

class DeployNoticeInfo {
  final String noticeId;
  final String platform;
  final String latestVersion;
  final int latestBuild;
  final DateTime? publishedAt;
  final String requestedBy;
  final String reason;
  final String releaseNotes;
  final String downloadUrl;
  final bool downloadReady;
  final String deployTaskId;

  const DeployNoticeInfo({
    required this.noticeId,
    required this.platform,
    required this.latestVersion,
    required this.latestBuild,
    required this.publishedAt,
    required this.requestedBy,
    required this.reason,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.downloadReady,
    required this.deployTaskId,
  });

  factory DeployNoticeInfo.fromJson(Map<String, dynamic> json) {
    return DeployNoticeInfo(
      noticeId: asString(json['notice_id']),
      platform: asString(json['platform']),
      latestVersion: asString(json['latest_version']),
      latestBuild: asInt(json['latest_build']),
      publishedAt: asDateTime(json['published_at']),
      requestedBy: asString(json['requested_by']),
      reason: asString(json['reason']),
      releaseNotes: asString(json['release_notes']),
      downloadUrl: asString(json['download_url']),
      downloadReady: asBool(json['download_ready']),
      deployTaskId: asString(json['deploy_task_id']),
    );
  }

  bool get hasNoticeId => noticeId.trim().isNotEmpty;
  bool get hasVersion => latestVersion.trim().isNotEmpty;
  String get versionLabel => formatVersionDisplay(latestVersion, latestBuild, fallback: '-');
}

class AsyncTaskStartResponse {
  final String taskId;
  final String status;

  const AsyncTaskStartResponse({
    required this.taskId,
    required this.status,
  });

  factory AsyncTaskStartResponse.fromJson(Map<String, dynamic> json) {
    return AsyncTaskStartResponse(
      taskId: asString(json['task_id']),
      status: asString(json['status']),
    );
  }
}

class BrowserPriceApplyTaskResult {
  final String productCode;
  final String itemName;
  final int? currentPrice;
  final int targetPrice;
  final String status;
  final String message;
  final bool execute;
  final String reason;
  final String actor;
  final Map<String, dynamic> detail;

  const BrowserPriceApplyTaskResult({
    required this.productCode,
    required this.itemName,
    required this.currentPrice,
    required this.targetPrice,
    required this.status,
    required this.message,
    required this.execute,
    required this.reason,
    required this.actor,
    required this.detail,
  });

  factory BrowserPriceApplyTaskResult.fromJson(Map<String, dynamic> json) {
    return BrowserPriceApplyTaskResult(
      productCode: asString(json['product_code']),
      itemName: asString(json['item_name']),
      currentPrice: json['current_price'] == null ? null : asInt(json['current_price']),
      targetPrice: asInt(json['target_price']),
      status: asString(json['status']),
      message: asString(json['message']),
      execute: asBool(json['execute']),
      reason: asString(json['reason']),
      actor: asString(json['actor']),
      detail: asMap(json['_detail']),
    );
  }
}

class BrowserPriceApplyTask {
  final String taskId;
  final String productCode;
  final int targetPrice;
  final String targetColumn;
  final bool execute;
  final String reason;
  final String actor;
  final String status;
  final BrowserPriceApplyTaskResult? result;
  final String? startedAt;
  final String? finishedAt;
  final String errorMessage;

  const BrowserPriceApplyTask({
    required this.taskId,
    required this.productCode,
    required this.targetPrice,
    required this.targetColumn,
    required this.execute,
    required this.reason,
    required this.actor,
    required this.status,
    required this.result,
    required this.startedAt,
    required this.finishedAt,
    required this.errorMessage,
  });

  factory BrowserPriceApplyTask.fromJson(Map<String, dynamic> json) {
    final rawResult = json['result'];
    return BrowserPriceApplyTask(
      taskId: asString(json['task_id']),
      productCode: asString(json['product_code']),
      targetPrice: asInt(json['target_price']),
      targetColumn: asString(json['target_column']),
      execute: asBool(json['execute']),
      reason: asString(json['reason']),
      actor: asString(json['actor']),
      status: asString(json['status']),
      result: rawResult is Map ? BrowserPriceApplyTaskResult.fromJson(Map<String, dynamic>.from(rawResult)) : null,
      startedAt: asNullableString(json['started_at']),
      finishedAt: asNullableString(json['finished_at']),
      errorMessage: asString(json['error_message']),
    );
  }

  bool get isActive => status == 'pending' || status == 'running';
  bool get isFinished => status == 'succeeded' || status == 'failed';
}

class AdminUserContract {
  final String id;
  final String loginId;
  final String role;
  final bool isActive;
  final String? lastLogin;

  const AdminUserContract({
    required this.id,
    required this.loginId,
    required this.role,
    required this.isActive,
    this.lastLogin,
  });

  factory AdminUserContract.fromJson(Map<String, dynamic> json) {
    return AdminUserContract(
      id: asString(json['id']),
      loginId: asString(json['login_id']),
      role: asString(json['role']),
      isActive: asBool(json['is_active']),
      lastLogin: asNullableString(json['last_login']),
    );
  }
}

class AuditLogEntryContract {
  final String id;
  final String loginId;
  final String action;
  final String? detail;
  final String? createdAt;

  const AuditLogEntryContract({
    required this.id,
    required this.loginId,
    required this.action,
    this.detail,
    this.createdAt,
  });

  factory AuditLogEntryContract.fromJson(Map<String, dynamic> json) {
    return AuditLogEntryContract(
      id: asString(json['id']),
      loginId: asString(json['login_id']),
      action: asString(json['action']),
      detail: asNullableString(json['detail']),
      createdAt: asNullableString(json['created_at']),
    );
  }
}

class DeployPubspecInfo {
  final String versionRaw;
  final String version;
  final int build;
  final String pubspecPath;

  const DeployPubspecInfo({
    required this.versionRaw,
    required this.version,
    required this.build,
    required this.pubspecPath,
  });

  factory DeployPubspecInfo.fromJson(Map<String, dynamic> json) {
    return DeployPubspecInfo(
      versionRaw: asString(json['version_raw']),
      version: asString(json['version']),
      build: asInt(json['build']),
      pubspecPath: asString(json['pubspec_path']),
    );
  }
}

class DeployUpdatePolicyInfo {
  final String latestVersion;
  final int latestBuild;
  final String downloadUrl;
  final String sha256;
  final String releaseNotes;
  final String publishedAt;
  final int fileSize;
  final String? policySource;
  final String? policyWarning;
  final bool? downloadReady;

  const DeployUpdatePolicyInfo({
    required this.latestVersion,
    required this.latestBuild,
    required this.downloadUrl,
    required this.sha256,
    required this.releaseNotes,
    required this.publishedAt,
    required this.fileSize,
    required this.policySource,
    required this.policyWarning,
    required this.downloadReady,
  });

  factory DeployUpdatePolicyInfo.fromJson(Map<String, dynamic> json) {
    return DeployUpdatePolicyInfo(
      latestVersion: asString(json['latest_version']),
      latestBuild: asInt(json['latest_build']),
      downloadUrl: asString(json['download_url']),
      sha256: asString(json['sha256']),
      releaseNotes: asString(json['release_notes']),
      publishedAt: asString(json['published_at']),
      fileSize: asInt(json['file_size']),
      policySource: asNullableString(json['policy_source']),
      policyWarning: asNullableString(json['policy_warning']),
      downloadReady: json.containsKey('download_ready') ? asBool(json['download_ready']) : null,
    );
  }
}

class DeployLatestReleaseArtifact {
  final String? latestVersion;
  final int? latestBuild;
  final String? fileName;
  final String? publishedAt;
  final String? artifactPath;
  final String? downloadUrl;
  final String? sha256;
  final int? fileSize;

  const DeployLatestReleaseArtifact({
    required this.latestVersion,
    required this.latestBuild,
    required this.fileName,
    required this.publishedAt,
    required this.artifactPath,
    required this.downloadUrl,
    required this.sha256,
    required this.fileSize,
  });

  factory DeployLatestReleaseArtifact.fromJson(Map<String, dynamic> json) {
    return DeployLatestReleaseArtifact(
      latestVersion: asNullableString(json['latest_version']),
      latestBuild: json['latest_build'] == null ? null : asInt(json['latest_build']),
      fileName: asNullableString(json['file_name']),
      publishedAt: asNullableString(json['published_at']),
      artifactPath: asNullableString(json['artifact_path']),
      downloadUrl: asNullableString(json['download_url']),
      sha256: asNullableString(json['sha256']),
      fileSize: json['file_size'] == null ? null : asInt(json['file_size']),
    );
  }
}

class DeployLatestReleaseInfo {
  final String releaseDir;
  final String latestJsonPath;
  final bool exists;
  final String? readError;
  final DeployLatestReleaseArtifact? latest;

  const DeployLatestReleaseInfo({
    required this.releaseDir,
    required this.latestJsonPath,
    required this.exists,
    required this.readError,
    required this.latest,
  });

  factory DeployLatestReleaseInfo.fromJson(Map<String, dynamic> json) {
    final rawLatest = json['latest'];
    return DeployLatestReleaseInfo(
      releaseDir: asString(json['release_dir']),
      latestJsonPath: asString(json['latest_json_path']),
      exists: asBool(json['exists']),
      readError: asNullableString(json['read_error']),
      latest: rawLatest is Map ? DeployLatestReleaseArtifact.fromJson(Map<String, dynamic>.from(rawLatest)) : null,
    );
  }
}

class DeployVersionInfo {
  final DeployPubspecInfo pubspec;
  final DeployUpdatePolicyInfo updatePolicy;
  final DeployLatestReleaseInfo latestRelease;

  const DeployVersionInfo({
    required this.pubspec,
    required this.updatePolicy,
    required this.latestRelease,
  });

  factory DeployVersionInfo.fromJson(Map<String, dynamic> json) {
    return DeployVersionInfo(
      pubspec: DeployPubspecInfo.fromJson(asMap(json['pubspec'])),
      updatePolicy: DeployUpdatePolicyInfo.fromJson(asMap(json['update_policy'])),
      latestRelease: DeployLatestReleaseInfo.fromJson(asMap(json['latest_release'])),
    );
  }
}

class AppUpdateMetrics {
  final int appUpdateCheckTotal;
  final int appUpdateCheckFailedTotal;
  final int downloadUrlEmptyTotal;
  final Map<String, int> policySourceTotal;

  const AppUpdateMetrics({
    required this.appUpdateCheckTotal,
    required this.appUpdateCheckFailedTotal,
    required this.downloadUrlEmptyTotal,
    required this.policySourceTotal,
  });

  factory AppUpdateMetrics.fromJson(Map<String, dynamic> json) {
    return AppUpdateMetrics(
      appUpdateCheckTotal: asInt(json['app_update_check_total']),
      appUpdateCheckFailedTotal: asInt(json['app_update_check_failed_total']),
      downloadUrlEmptyTotal: asInt(json['download_url_empty_total']),
      policySourceTotal: asIntMap(json['policy_source_total']),
    );
  }
}
