import 'package:cafe_bridge_flutter/services/api.dart';
import 'package:cafe_bridge_flutter/services/app_update_service_models.dart';
import 'package:cafe_bridge_flutter/services/app_update_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('API base URL validation', () {
    test('requires HTTPS when requested', () {
      expect(
        () => ApiService.normalizeBaseUrl(
          'http://pos.cafe-bridge.org',
          requireHttps: true,
        ),
        throwsFormatException,
      );
      expect(
        ApiService.normalizeBaseUrl(
          'pos.cafe-bridge.org',
          requireHttps: true,
        ),
        'https://pos.cafe-bridge.org',
      );
    });

    test('allows HTTP only for scoped debug development hosts', () {
      for (final host in ['localhost', '127.0.0.1', '10.0.2.2']) {
        expect(
          ApiService.normalizeBaseUrl(host, requireHttps: false),
          'http://$host:8087',
        );
      }
      expect(
        () => ApiService.normalizeBaseUrl(
          'http://dev.example.com',
          requireHttps: false,
        ),
        throwsFormatException,
      );
      expect(
        ApiService.normalizeBaseUrl(
          'dev.example.com',
          requireHttps: false,
        ),
        'https://dev.example.com',
      );
    });

    test('profile-style policy requires HTTPS for local hosts', () {
      expect(
        () => ApiService.normalizeBaseUrl(
          'http://10.0.2.2',
          requireHttps: true,
        ),
        throwsFormatException,
      );
    });

    test('rejects credentials and non-HTTP schemes', () {
      expect(
        () => ApiService.normalizeBaseUrl('https://user:pass@example.com'),
        throwsFormatException,
      );
      expect(
        () => ApiService.normalizeBaseUrl('file:///tmp/server'),
        throwsFormatException,
      );
    });
  });

  group('APK update validation', () {
    const sha256 =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

    test('accepts a newer HTTPS update with a SHA-256 digest', () {
      final uri = validateApkUpdate(
        downloadUrl: 'https://releases.example.com/cafe-bridge.apk',
        expectedSha256: sha256,
        latestBuild: 4,
        currentBuild: 3,
      );
      expect(uri.scheme, 'https');
    });

    test('rejects insecure URLs and malformed hashes', () {
      expect(
        () => validateApkUpdate(
          downloadUrl: 'http://releases.example.com/cafe-bridge.apk',
          expectedSha256: sha256,
          latestBuild: 4,
          currentBuild: 3,
        ),
        throwsA(isA<UpdateValidationException>()),
      );
      expect(
        () => validateApkUpdate(
          downloadUrl: 'https://releases.example.com/cafe-bridge.apk',
          expectedSha256: 'missing',
          latestBuild: 4,
          currentBuild: 3,
        ),
        throwsA(isA<UpdateValidationException>()),
      );
    });

    test('rejects equal and lower build numbers', () {
      for (final build in [3, 2]) {
        expect(
          () => validateApkUpdate(
            downloadUrl: 'https://releases.example.com/cafe-bridge.apk',
            expectedSha256: sha256,
            latestBuild: build,
            currentBuild: 3,
          ),
          throwsA(isA<UpdateValidationException>()),
        );
      }
    });

    test('accepts relative and HTTPS redirects', () {
      final initial = Uri.parse('https://releases.example.com/app/latest');
      expect(
        resolveApkDownloadRedirect(
          currentUri: initial,
          location: '/files/cafe-bridge.apk',
          redirectsFollowed: 0,
        ),
        Uri.parse('https://releases.example.com/files/cafe-bridge.apk'),
      );
      expect(
        resolveApkDownloadRedirect(
          currentUri: initial,
          location: 'https://cdn.example.com/cafe-bridge.apk',
          redirectsFollowed: 1,
        ).host,
        'cdn.example.com',
      );
    });

    test('rejects insecure, missing, and excessive redirects', () {
      final initial = Uri.parse('https://releases.example.com/app/latest');
      for (final location in [null, '', 'http://cdn.example.com/app.apk']) {
        expect(
          () => resolveApkDownloadRedirect(
            currentUri: initial,
            location: location,
            redirectsFollowed: 0,
          ),
          throwsA(isA<UpdateValidationException>()),
        );
      }
      expect(
        () => resolveApkDownloadRedirect(
          currentUri: initial,
          location: '/app.apk',
          redirectsFollowed: maxApkDownloadRedirects,
        ),
        throwsA(isA<UpdateValidationException>()),
      );
    });

    test('enforces the 250 MiB declared size limit', () {
      expect(maxApkDownloadBytes, 250 * 1024 * 1024);
      expect(
        () => validateApkDownloadLengths(
          expectedFileSize: maxApkDownloadBytes + 1,
          contentLength: null,
        ),
        throwsA(isA<UpdateValidationException>()),
      );
      expect(
        () => validateApkDownloadLengths(
          expectedFileSize: null,
          contentLength: maxApkDownloadBytes + 1,
        ),
        throwsA(isA<UpdateValidationException>()),
      );
      expect(
        () => validateApkDownloadLengths(
          expectedFileSize: 100,
          contentLength: 101,
        ),
        throwsA(isA<UpdateValidationException>()),
      );
    });

    test('rejects a chunk before it crosses either size bound', () {
      expect(
        validateApkDownloadChunk(
          bytesReceived: 60,
          incomingBytes: 40,
          expectedFileSize: 100,
        ),
        100,
      );
      expect(
        () => validateApkDownloadChunk(
          bytesReceived: 100,
          incomingBytes: 1,
          expectedFileSize: 100,
        ),
        throwsA(isA<UpdateValidationException>()),
      );
      expect(
        () => validateApkDownloadChunk(
          bytesReceived: maxApkDownloadBytes,
          incomingBytes: 1,
          expectedFileSize: null,
        ),
        throwsA(isA<UpdateValidationException>()),
      );
    });

    test('marks stale download responses for metadata refresh', () {
      for (final status in [404, 409]) {
        expect(
          () => validateApkDownloadHttpStatus(status),
          throwsA(
            isA<AppUpdateRefreshRequiredException>()
                .having(
                  (error) => error.requiresMetadataRefresh,
                  'requiresMetadataRefresh',
                  isTrue,
                )
                .having(
                  (error) => error.httpStatus,
                  'httpStatus',
                  status,
                ),
          ),
        );
      }
      expect(() => validateApkDownloadHttpStatus(204), returnsNormally);
      expect(
        () => validateApkDownloadHttpStatus(500),
        throwsA(
          isA<AppUpdateException>()
              .having(
                (error) => error.code,
                'code',
                AppUpdateErrorCode.downloadFailed,
              )
              .having(
                (error) => error.requiresMetadataRefresh,
                'requiresMetadataRefresh',
                isFalse,
              ),
        ),
      );
    });

    test('marks a downloaded hash mismatch for metadata refresh', () {
      expect(
        () => validateDownloadedApkSha256(
          expectedSha256: sha256,
          actualSha256:
              'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
        ),
        throwsA(
          isA<AppUpdateRefreshRequiredException>().having(
            (error) => error.requiresMetadataRefresh,
            'requiresMetadataRefresh',
            isTrue,
          ),
        ),
      );
      expect(
        () => validateDownloadedApkSha256(
          expectedSha256: sha256.toUpperCase(),
          actualSha256: sha256,
        ),
        returnsNormally,
      );
    });

    test('identifies update artifacts without deleting unrelated files', () {
      expect(isApkUpdateArtifactPath('/updates/release.apk'), isTrue);
      expect(isApkUpdateArtifactPath('/updates/RELEASE.APK.PART'), isTrue);
      expect(isApkUpdateArtifactPath('/updates/release.apk.json'), isFalse);
      expect(isApkUpdateArtifactPath('/updates/notes.txt'), isFalse);
    });

    test('classifies installer launch failures', () {
      expect(
        appUpdateErrorCodeForInstallerPlatformCode('INSTALLER_NOT_FOUND'),
        AppUpdateErrorCode.installerUnavailable,
      );
      expect(
        appUpdateErrorCodeForInstallerPlatformCode(
          'INSTALL_PERMISSION_SETTINGS_BLOCKED',
        ),
        AppUpdateErrorCode.installerBlocked,
      );
      expect(
        appUpdateErrorCodeForInstallerPlatformCode('INVALID_APK_UPDATE'),
        AppUpdateErrorCode.invalidUpdate,
      );
    });
  });

  group('APK update service models', () {
    test('parses retryable unknown-sources permission status', () {
      final result = AppInstallerResult.fromChannel({
        'status': 'permissionRequired',
        'message': '설치 권한을 허용해 주세요.',
        'canRetry': true,
      });

      expect(result.status, AppInstallerStatus.permissionRequired);
      expect(result.canRetry, isTrue);
      expect(result.message, '설치 권한을 허용해 주세요.');
    });

    test('rejects malformed installer status responses', () {
      expect(
        () => AppInstallerResult.fromChannel({
          'status': 'unknown',
          'message': 'message',
          'canRetry': false,
        }),
        throwsFormatException,
      );
      expect(
        () => AppInstallerResult.fromChannel({
          'status': 'installerOpened',
          'message': 'message',
          'canRetry': 'no',
        }),
        throwsFormatException,
      );
    });

    test('cancellation token cancels active and future downloads once', () {
      final activeToken = ApkDownloadCancellationToken();
      var activeCancellationCount = 0;
      activeToken.attach(() => activeCancellationCount += 1);
      activeToken.cancel();
      activeToken.cancel();
      expect(activeToken.isCancelled, isTrue);
      expect(activeCancellationCount, 1);

      final cancelledToken = ApkDownloadCancellationToken()..cancel();
      var futureCancellationCount = 0;
      cancelledToken.attach(() => futureCancellationCount += 1);
      expect(futureCancellationCount, 1);
    });
  });
}
