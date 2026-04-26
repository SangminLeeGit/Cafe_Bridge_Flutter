import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

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

  static Future<ApkDownloadResult> downloadApk({
    required String downloadUrl,
    required String version,
    required int buildNumber,
    String? expectedSha256,
    int? expectedFileSize,
    void Function(int received, int total)? onProgress,
  }) async {
    final uri = Uri.parse(downloadUrl);
    final client = http.Client();
    IOSink? sink;
    File? tempFile;

    try {
      final request = http.Request('GET', uri);
      final response = await client.send(request).timeout(_downloadTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('업데이트 파일 다운로드 실패 (HTTP ${response.statusCode})');
      }

      final supportDirectory = await getApplicationSupportDirectory();
      final updateDirectory = Directory('${supportDirectory.path}/updates');
      await updateDirectory.create(recursive: true);

      final fileName = _resolveFileName(uri, version, buildNumber);
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
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, response.contentLength ?? 0);
      }

      await sink.flush();
      await sink.close();
      sink = null;

      final expectedSize = expectedFileSize ?? 0;
      if (expectedSize > 0 && received != expectedSize) {
        throw Exception(
          '파일 크기 검증 실패: 수신 $received bytes, 기대 $expectedSize bytes',
        );
      }

      final normalizedSha = (expectedSha256 ?? '').trim().toLowerCase();
      if (normalizedSha.isNotEmpty) {
        final digest = await _calculateSha256(tempFile.path);
        if (digest.toLowerCase() != normalizedSha) {
          throw Exception('무결성 검증 실패: SHA-256 해시가 일치하지 않습니다.');
        }
      }

      await tempFile.rename(targetFile.path);
      await _deleteStalePackages(updateDirectory, keepPath: targetFile.path);
      return ApkDownloadResult(
        filePath: targetFile.path,
        bytesReceived: received,
      );
    } on TimeoutException {
      throw Exception('업데이트 파일 다운로드 시간이 초과되었습니다.');
    } finally {
      if (sink != null) {
        await sink.close();
      }
      if (tempFile != null && await tempFile.exists()) {
        await tempFile.delete();
      }
      client.close();
    }
  }

  static Future<String> openInstaller(String filePath) async {
    final result = await OpenFilex.open(
      filePath,
      type: 'application/vnd.android.package-archive',
    );

    switch (result.type) {
      case ResultType.done:
        return '설치 화면을 열었습니다. 차단되면 이 앱의 알 수 없는 앱 설치를 허용해 주세요.';
      case ResultType.fileNotFound:
        throw Exception('다운로드한 APK 파일을 찾을 수 없습니다. 다시 다운로드해 주세요.');
      case ResultType.noAppToOpen:
        throw Exception('APK 설치 프로그램을 열 수 없습니다. 기기 정책을 확인해 주세요.');
      case ResultType.permissionDenied:
        throw Exception('설치 권한이 거부되었습니다. 이 앱의 알 수 없는 앱 설치를 허용해 주세요.');
      case ResultType.error:
        if (result.message.trim().isNotEmpty) {
          throw Exception('APK 설치를 시작하지 못했습니다: ${result.message}');
        }
        throw Exception('APK 설치를 시작하지 못했습니다.');
    }
  }

  static String _resolveFileName(Uri uri, String version, int buildNumber) {
    final candidate = uri.pathSegments.isEmpty
        ? 'easypos-$version+$buildNumber.apk'
        : uri.pathSegments.last;
    final normalized = candidate.toLowerCase().endsWith('.apk')
        ? candidate
        : 'easypos-$version+$buildNumber.apk';
    return normalized.replaceAll(RegExp(r'[^A-Za-z0-9._+-]'), '_');
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
      if (entity.path.endsWith('.apk') || entity.path.endsWith('.apk.part')) {
        await entity.delete();
      }
    }
  }

  static Future<String> _calculateSha256(String filePath) async {
    final digest = await sha256.bind(File(filePath).openRead()).first;
    return digest.toString();
  }
}