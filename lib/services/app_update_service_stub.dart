import 'app_update_service_models.dart';

class ApkDownloadResult {
  final String filePath;
  final int bytesReceived;

  const ApkDownloadResult({
    required this.filePath,
    required this.bytesReceived,
  });
}

class AppUpdateService {
  static const bool supported = false;

  static Future<ApkDownloadResult> downloadApk({
    required String downloadUrl,
    required String version,
    required int buildNumber,
    required int currentBuildNumber,
    required String expectedSha256,
    int? expectedFileSize,
    void Function(int received, int total)? onProgress,
    ApkDownloadCancellationToken? cancellationToken,
  }) {
    throw UnsupportedError('이 플랫폼에서는 APK 다운로드를 지원하지 않습니다.');
  }

  static Future<AppInstallerResult> requestInstaller(
    String filePath, {
    required int expectedBuildNumber,
  }) {
    throw UnsupportedError('이 플랫폼에서는 APK 설치를 지원하지 않습니다.');
  }
}
