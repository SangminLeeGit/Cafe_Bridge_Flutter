enum AppUpdateErrorCode {
  invalidUpdate,
  metadataRefreshRequired,
  cancelled,
  timeout,
  downloadFailed,
  installerUnavailable,
  installerBlocked,
}

class AppUpdateException implements Exception {
  final AppUpdateErrorCode code;
  final String message;
  final int? httpStatus;

  const AppUpdateException(
    this.code,
    this.message, {
    this.httpStatus,
  });

  bool get requiresMetadataRefresh =>
      code == AppUpdateErrorCode.metadataRefreshRequired;

  @override
  String toString() => message;
}

class UpdateValidationException extends AppUpdateException {
  const UpdateValidationException(String message)
      : super(AppUpdateErrorCode.invalidUpdate, message);
}

class AppUpdateRefreshRequiredException extends AppUpdateException {
  const AppUpdateRefreshRequiredException(
    String message, {
    int? httpStatus,
  }) : super(
          AppUpdateErrorCode.metadataRefreshRequired,
          message,
          httpStatus: httpStatus,
        );
}

const int maxApkDownloadRedirects = 3;
const int maxApkDownloadBytes = 250 * 1024 * 1024;

void validateApkDownloadHttpStatus(int statusCode) {
  if (statusCode >= 200 && statusCode < 300) {
    return;
  }
  if (statusCode == 404 || statusCode == 409) {
    throw AppUpdateRefreshRequiredException(
      '업데이트 정보가 변경되었습니다. 최신 업데이트 정보를 다시 조회해 주세요.',
      httpStatus: statusCode,
    );
  }
  throw AppUpdateException(
    AppUpdateErrorCode.downloadFailed,
    '업데이트 파일 다운로드 실패 (HTTP $statusCode)',
    httpStatus: statusCode,
  );
}

bool isApkUpdateArtifactPath(String path) {
  final normalized = path.toLowerCase();
  return normalized.endsWith('.apk') || normalized.endsWith('.apk.part');
}

AppUpdateErrorCode appUpdateErrorCodeForInstallerPlatformCode(String code) {
  return switch (code) {
    'INSTALLER_NOT_FOUND' ||
    'INSTALL_PERMISSION_SETTINGS_NOT_FOUND' =>
      AppUpdateErrorCode.installerUnavailable,
    'INSTALLER_SECURITY_ERROR' ||
    'INSTALL_PERMISSION_SETTINGS_BLOCKED' =>
      AppUpdateErrorCode.installerBlocked,
    _ => AppUpdateErrorCode.invalidUpdate,
  };
}

void validateDownloadedApkSha256({
  required String expectedSha256,
  required String actualSha256,
}) {
  if (actualSha256.toLowerCase() != expectedSha256.trim().toLowerCase()) {
    throw const AppUpdateRefreshRequiredException(
      '업데이트 파일 해시가 변경되었습니다. 최신 업데이트 정보를 다시 조회해 주세요.',
    );
  }
}

void validateApkDownloadLengths({
  required int? expectedFileSize,
  required int? contentLength,
}) {
  if (expectedFileSize != null && expectedFileSize < 0) {
    throw const UpdateValidationException('업데이트 파일 크기가 올바르지 않습니다.');
  }
  if (expectedFileSize != null && expectedFileSize > maxApkDownloadBytes) {
    throw const UpdateValidationException('업데이트 파일이 최대 허용 크기를 초과합니다.');
  }
  if (contentLength != null && contentLength > maxApkDownloadBytes) {
    throw const UpdateValidationException('업데이트 파일이 최대 허용 크기를 초과합니다.');
  }
  if (expectedFileSize != null &&
      expectedFileSize > 0 &&
      contentLength != null &&
      contentLength > expectedFileSize) {
    throw const UpdateValidationException('업데이트 파일이 예상 크기를 초과합니다.');
  }
}

int validateApkDownloadChunk({
  required int bytesReceived,
  required int incomingBytes,
  required int? expectedFileSize,
}) {
  if (bytesReceived < 0 || incomingBytes < 0) {
    throw const UpdateValidationException('업데이트 파일 크기가 올바르지 않습니다.');
  }

  final nextTotal = bytesReceived + incomingBytes;
  if (nextTotal > maxApkDownloadBytes) {
    throw const UpdateValidationException('업데이트 파일이 최대 허용 크기를 초과합니다.');
  }
  if (expectedFileSize != null &&
      expectedFileSize > 0 &&
      nextTotal > expectedFileSize) {
    throw const UpdateValidationException('업데이트 파일이 예상 크기를 초과합니다.');
  }
  return nextTotal;
}

Uri validateApkDownloadUri(String rawUrl) {
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const UpdateValidationException(
        '업데이트 다운로드 주소는 유효한 HTTPS URL이어야 합니다.');
  }
  if (uri.hasFragment) {
    throw const UpdateValidationException('업데이트 다운로드 주소에 프래그먼트를 사용할 수 없습니다.');
  }
  return uri;
}

Uri resolveApkDownloadRedirect({
  required Uri currentUri,
  required String? location,
  required int redirectsFollowed,
  int maxRedirects = maxApkDownloadRedirects,
}) {
  if (redirectsFollowed >= maxRedirects) {
    throw const UpdateValidationException('업데이트 다운로드 리디렉션 횟수를 초과했습니다.');
  }
  if (location == null || location.trim().isEmpty) {
    throw const UpdateValidationException('업데이트 리디렉션 주소가 비어 있습니다.');
  }

  final reference = Uri.tryParse(location.trim());
  if (reference == null) {
    throw const UpdateValidationException('업데이트 리디렉션 주소가 올바르지 않습니다.');
  }
  return validateApkDownloadUri(currentUri.resolveUri(reference).toString());
}

Uri validateApkUpdate({
  required String downloadUrl,
  required String expectedSha256,
  required int latestBuild,
  required int currentBuild,
}) {
  final uri = validateApkDownloadUri(downloadUrl);

  final normalizedSha256 = expectedSha256.trim().toLowerCase();
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(normalizedSha256)) {
    throw const UpdateValidationException('업데이트에 유효한 SHA-256 해시가 필요합니다.');
  }
  if (latestBuild <= currentBuild) {
    throw const UpdateValidationException('현재 버전과 같거나 낮은 업데이트는 설치할 수 없습니다.');
  }
  return uri;
}
