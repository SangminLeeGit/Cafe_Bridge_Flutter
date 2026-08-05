import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'app_update_service_models.dart';
import 'app_update_validation.dart';

class ApkDownloadResult {
  final String filePath;
  final int bytesReceived;

  const ApkDownloadResult({
    required this.filePath,
    required this.bytesReceived,
  });
}

class AppUpdateService {
  static const bool supported = true;
  static const Duration _downloadTimeout = Duration(minutes: 3);
  static const MethodChannel _updateChannel = MethodChannel(
    'org.cafe.bridge.mobile/app_update',
  );

  static Future<ApkDownloadResult> downloadApk({
    required String downloadUrl,
    required String version,
    required int buildNumber,
    required int currentBuildNumber,
    required String expectedSha256,
    int? expectedFileSize,
    void Function(int received, int total)? onProgress,
    ApkDownloadCancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled ?? false) {
      throw const AppUpdateException(
        AppUpdateErrorCode.cancelled,
        '업데이트 다운로드가 취소되었습니다.',
      );
    }
    var requestUri = validateApkUpdate(
      downloadUrl: downloadUrl,
      expectedSha256: expectedSha256,
      latestBuild: buildNumber,
      currentBuild: currentBuildNumber,
    );
    final client = http.Client();
    cancellationToken?.attach(client.close);
    IOSink? sink;
    File? tempFile;

    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final updateDirectory = Directory('${supportDirectory.path}/updates');
      await updateDirectory.create(recursive: true);
      await _deleteStalePackages(updateDirectory, keepPath: '');

      var redirectsFollowed = 0;
      late http.StreamedResponse response;
      while (true) {
        final request = http.Request('GET', requestUri)
          ..followRedirects = false;
        response = await client.send(request).timeout(_downloadTimeout);
        if (!_isRedirect(response.statusCode)) {
          break;
        }

        final nextUri = resolveApkDownloadRedirect(
          currentUri: requestUri,
          location: response.headers['location'],
          redirectsFollowed: redirectsFollowed,
        );
        await response.stream.listen((_) {}).cancel();
        requestUri = nextUri;
        redirectsFollowed += 1;
      }

      validateApkDownloadHttpStatus(response.statusCode);
      validateApkDownloadLengths(
        expectedFileSize: expectedFileSize,
        contentLength: response.contentLength,
      );
      final bodyStopwatch = Stopwatch()..start();

      final fileName = _resolveFileName(requestUri, version, buildNumber);
      final targetFile = File('${updateDirectory.path}/$fileName');
      tempFile = File('${updateDirectory.path}/$fileName.part');

      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      sink = tempFile.openWrite();
      var received = 0;
      await for (final chunk in response.stream.timeout(_downloadTimeout)) {
        if (cancellationToken?.isCancelled ?? false) {
          throw const AppUpdateException(
            AppUpdateErrorCode.cancelled,
            '업데이트 다운로드가 취소되었습니다.',
          );
        }
        if (bodyStopwatch.elapsed >= _downloadTimeout) {
          throw TimeoutException('APK response body deadline exceeded');
        }
        received = validateApkDownloadChunk(
          bytesReceived: received,
          incomingBytes: chunk.length,
          expectedFileSize: expectedFileSize,
        );
        sink.add(chunk);
        onProgress?.call(received, response.contentLength ?? 0);
      }
      if (bodyStopwatch.elapsed >= _downloadTimeout) {
        throw TimeoutException('APK response body deadline exceeded');
      }

      await sink.flush();
      await sink.close();
      sink = null;

      final expectedSize = expectedFileSize ?? 0;
      if (expectedSize > 0 && received != expectedSize) {
        throw AppUpdateRefreshRequiredException(
          '업데이트 파일 크기가 변경되었습니다. 최신 업데이트 정보를 다시 조회해 주세요. '
          '(수신 $received bytes, 기대 $expectedSize bytes)',
        );
      }

      final digest = await _calculateSha256(tempFile.path);
      validateDownloadedApkSha256(
        expectedSha256: expectedSha256,
        actualSha256: digest,
      );
      if (cancellationToken?.isCancelled ?? false) {
        throw const AppUpdateException(
          AppUpdateErrorCode.cancelled,
          '업데이트 다운로드가 취소되었습니다.',
        );
      }

      await tempFile.rename(targetFile.path);
      await _deleteStalePackages(updateDirectory, keepPath: targetFile.path);
      return ApkDownloadResult(
        filePath: targetFile.path,
        bytesReceived: received,
      );
    } on TimeoutException {
      if (cancellationToken?.isCancelled ?? false) {
        throw const AppUpdateException(
          AppUpdateErrorCode.cancelled,
          '업데이트 다운로드가 취소되었습니다.',
        );
      }
      throw const AppUpdateException(
        AppUpdateErrorCode.timeout,
        '업데이트 파일 다운로드 시간이 초과되었습니다.',
      );
    } on http.ClientException catch (error) {
      if (cancellationToken?.isCancelled ?? false) {
        throw const AppUpdateException(
          AppUpdateErrorCode.cancelled,
          '업데이트 다운로드가 취소되었습니다.',
        );
      }
      throw AppUpdateException(
        AppUpdateErrorCode.downloadFailed,
        '업데이트 파일 다운로드 연결에 실패했습니다: ${error.message}',
      );
    } catch (_) {
      if (cancellationToken?.isCancelled ?? false) {
        throw const AppUpdateException(
          AppUpdateErrorCode.cancelled,
          '업데이트 다운로드가 취소되었습니다.',
        );
      }
      rethrow;
    } finally {
      try {
        if (sink != null) {
          await sink.close();
        }
      } finally {
        try {
          if (tempFile != null && await tempFile.exists()) {
            await tempFile.delete();
          }
        } finally {
          cancellationToken?.detach();
          client.close();
        }
      }
    }
  }

  static Future<AppInstallerResult> requestInstaller(
    String filePath, {
    required int expectedBuildNumber,
  }) async {
    try {
      final response = await _updateChannel.invokeMethod<Object?>(
        'verifyAndInstallApk',
        {
          'filePath': filePath,
          'expectedBuild': expectedBuildNumber,
        },
      );
      if (response is! Map) {
        throw const FormatException('APK 설치 상태 응답이 비어 있습니다.');
      }
      return AppInstallerResult.fromChannel(
        Map<Object?, Object?>.from(response),
      );
    } on PlatformException catch (error) {
      final message = error.message ?? 'APK 설치를 시작하지 못했습니다.';
      final code = appUpdateErrorCodeForInstallerPlatformCode(error.code);
      throw AppUpdateException(code, message);
    } on FormatException catch (error) {
      throw AppUpdateException(
        AppUpdateErrorCode.invalidUpdate,
        error.message,
      );
    }
  }

  static String _resolveFileName(Uri uri, String version, int buildNumber) {
    final candidate = uri.pathSegments.isEmpty
        ? 'cafe-bridge-$version+$buildNumber.apk'
        : uri.pathSegments.last;
    final normalized = candidate.toLowerCase().endsWith('.apk')
        ? candidate
        : 'cafe-bridge-$version+$buildNumber.apk';
    return normalized.replaceAll(RegExp(r'[^A-Za-z0-9._+-]'), '_');
  }

  static bool _isRedirect(int statusCode) {
    return statusCode == HttpStatus.movedPermanently ||
        statusCode == HttpStatus.found ||
        statusCode == HttpStatus.seeOther ||
        statusCode == HttpStatus.temporaryRedirect ||
        statusCode == HttpStatus.permanentRedirect;
  }

  static Future<void> _deleteStalePackages(
    Directory directory, {
    required String keepPath,
  }) async {
    if (!await directory.exists()) {
      return;
    }

    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      if (entity.path == keepPath) {
        continue;
      }
      if (isApkUpdateArtifactPath(entity.path)) {
        await entity.delete();
      }
    }
  }

  static Future<String> _calculateSha256(String filePath) async {
    final digest = await sha256.bind(File(filePath).openRead()).first;
    return digest.toString();
  }
}
