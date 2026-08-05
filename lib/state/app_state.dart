import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/api_contracts.dart';
import '../services/active_task_store.dart';
import '../services/app_update_service.dart';
import '../services/api.dart';
import '../services/cache_store.dart';

class CachedDataResult<T> {
  final T data;
  final bool fromCache;
  final DateTime? cachedAt;

  const CachedDataResult({
    required this.data,
    required this.fromCache,
    required this.cachedAt,
  });
}

enum UserRole {
  unknown,
  viewer,
  operator,
  admin,
}

extension UserRoleAccess on UserRole {
  static UserRole fromString(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'admin':
        return UserRole.admin;
      case 'operator':
        return UserRole.operator;
      case 'viewer':
        return UserRole.viewer;
      default:
        return UserRole.unknown;
    }
  }

  int get rank {
    switch (this) {
      case UserRole.unknown:
        return -1;
      case UserRole.viewer:
        return 0;
      case UserRole.operator:
        return 1;
      case UserRole.admin:
        return 2;
    }
  }

  String get label {
    switch (this) {
      case UserRole.unknown:
        return 'unknown';
      case UserRole.viewer:
        return 'viewer';
      case UserRole.operator:
        return 'operator';
      case UserRole.admin:
        return 'admin';
    }
  }

  bool allows(UserRole required) =>
      this != UserRole.unknown &&
      required != UserRole.unknown &&
      rank >= required.rank;
}

class AppState extends ChangeNotifier {
  static const String _apiBaseUrlKey = 'api_base_url';
  static const String _setupRequiredKey = 'auth_setup_required';
  static const String _bootstrapConfiguredKey = 'auth_bootstrap_configured';
  static const String _sessionCookieKey = 'session_cookie';
  static const String _rememberMeKey = 'auth_remember_me';
  static const String _lastLoginIdKey = 'auth_last_login_id';
  static const String _lastRoleKey = 'auth_last_role';
  static const String _lastSeenDeployNoticeIdKey = 'last_seen_deploy_notice_id';
  static const Duration _keepAliveInterval = Duration(minutes: 4);

  AppState({
    ApiClient? apiClient,
    SharedPreferences? preferences,
    FlutterSecureStorage? secureStorage,
  })  : _apiBaseUrl = ApiService.defaultBaseUrl(),
        _apiClient = apiClient ?? ApiClient(),
        _providedPreferences = preferences,
        _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions:
                  IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  String _apiBaseUrl;
  final ApiClient _apiClient;
  final SharedPreferences? _providedPreferences;
  final FlutterSecureStorage _secureStorage;
  late SharedPreferences _prefs;
  late ApiCacheStore _cacheStore;
  late ActiveTaskStore _activeTaskStore;
  bool _isInitializing = true;
  bool _authenticated = false;
  bool _offlineMode = false;
  bool _setupRequired = false;
  bool _bootstrapConfigured = false;
  bool _rememberMe = false;
  String? _sessionCookie;
  String? _csrfToken;
  String? _loginId;
  String? _role;
  DateTime? _lastSessionSyncAt;
  int _cacheEntryCount = 0;
  AppUpdateInfo? _updateInfo;
  String _currentAppVersion = '1.0.0';
  int _currentAppBuild = 1;
  bool _isUpdateActionInProgress = false;
  double? _updateDownloadProgress;
  String _updateStatusMessage = '';
  DateTime? _lastUpdateCheckAt;
  bool? _lastUpdateCheckOk;
  String _lastUpdateCheckMessage = '';
  DeployNoticeInfo? _deployNotice;
  String _lastSeenDeployNoticeId = '';
  bool _updateCheckRetryScheduled = false;
  String? _downloadedUpdatePath;
  ApkDownloadCancellationToken? _updateCancellationToken;
  bool _installerAutoRetryPending = false;
  bool _retryingInstallerAfterResume = false;
  bool _resumeRefreshInFlight = false;
  Timer? _keepAliveTimer;
  bool _keepAliveInFlight = false;
  bool _localStateLoaded = false;
  bool _remoteStateLoaded = false;
  bool _cacheStoreReady = false;
  Future<void>? _localLoadInFlight;
  bool _disposed = false;
  int _sessionEpoch = 0;
  int _requestSequence = 0;
  int _lastCookieRequestSequence = 0;

  String get apiBaseUrl => _apiBaseUrl;
  bool get isInitializing => _isInitializing;
  bool get isRestoringSession => !_remoteStateLoaded;
  bool get isAuthenticated => _authenticated;
  bool get offlineMode => _offlineMode;
  bool get setupRequired => _setupRequired;
  bool get bootstrapConfigured => _bootstrapConfigured;
  bool get rememberMe => _rememberMe;
  String? get loginId => _loginId;
  String? get role => _role;
  UserRole get userRole => UserRoleAccess.fromString(_role);
  DateTime? get lastSessionSyncAt => _lastSessionSyncAt;
  int get cacheEntryCount => _cacheEntryCount;
  AppUpdateInfo? get updateInfo => _updateInfo;
  String get currentAppVersion => _currentAppVersion;
  int get currentAppBuild => _currentAppBuild;
  String get currentAppVersionLabel =>
      formatVersionDisplay(_currentAppVersion, _currentAppBuild);
  bool get hasRecommendedUpdate => _updateInfo?.updateAvailable == true;
  bool get supportsInAppUpdateInstall =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      AppUpdateService.supported;
  bool get canStartAppUpdate =>
      hasRecommendedUpdate &&
      (_updateInfo?.hasDownloadUrl ?? false) &&
      supportsInAppUpdateInstall;
  bool get canInstallDownloadedUpdate =>
      (_downloadedUpdatePath?.isNotEmpty ?? false) &&
      supportsInAppUpdateInstall;
  bool get isUpdateActionInProgress => _isUpdateActionInProgress;
  double? get updateDownloadProgress => _updateDownloadProgress;
  String get updateStatusMessage => _updateStatusMessage;
  DateTime? get lastUpdateCheckAt => _lastUpdateCheckAt;
  bool? get lastUpdateCheckOk => _lastUpdateCheckOk;
  String get lastUpdateCheckMessage => _lastUpdateCheckMessage;
  DeployNoticeInfo? get deployNotice => _deployNotice;
  String get lastSeenDeployNoticeId => _lastSeenDeployNoticeId;
  bool get hasUnreadDeployNotice =>
      _deployNotice != null &&
      _deployNotice!.hasNoticeId &&
      _deployNotice!.noticeId != _lastSeenDeployNoticeId;
  bool get hasOperatorAccess => canAccess(UserRole.operator);
  bool get hasAdminAccess => canAccess(UserRole.admin);

  bool canAccess(UserRole requiredRole) {
    if (!_authenticated) {
      return false;
    }
    return userRole.allows(requiredRole);
  }

  Future<void> loadLocal({bool notify = true}) async {
    if (_localStateLoaded) {
      return;
    }
    final activeLoad = _localLoadInFlight;
    if (activeLoad != null) {
      await activeLoad;
      return;
    }

    final load = _loadLocalInternal();
    _localLoadInFlight = load;
    try {
      await load;
    } finally {
      if (identical(_localLoadInFlight, load)) {
        _localLoadInFlight = null;
      }
    }
    if (notify) {
      _notifySafely();
    }
  }

  Future<void> _loadLocalInternal() async {
    _prefs = _providedPreferences ?? await SharedPreferences.getInstance();
    _cacheStore = ApiCacheStore(_prefs);
    _activeTaskStore = ActiveTaskStore(_prefs);
    _cacheStoreReady = true;

    final savedBaseUrl = _prefs.getString(_apiBaseUrlKey);
    if (savedBaseUrl != null && savedBaseUrl.trim().isNotEmpty) {
      try {
        _apiBaseUrl = ApiService.normalizeBaseUrl(savedBaseUrl);
      } on FormatException {
        _apiBaseUrl = ApiService.defaultBaseUrl();
        await _prefs.remove(_apiBaseUrlKey);
      }
    }

    _setupRequired = _prefs.getBool(_setupRequiredKey) ?? false;
    _bootstrapConfigured = _prefs.getBool(_bootstrapConfiguredKey) ?? false;
    _rememberMe = _prefs.getBool(_rememberMeKey) ?? false;
    _lastSeenDeployNoticeId =
        _prefs.getString(_lastSeenDeployNoticeIdKey) ?? '';
    await _cacheStore.prune();
    _refreshCacheCount();

    await _loadCurrentAppVersion();
    if (_rememberMe) {
      _loginId = _prefs.getString(_lastLoginIdKey);
      _role = _prefs.getString(_lastRoleKey);
      final savedCookie = await _secureStorage.read(key: _sessionCookieKey);
      if (savedCookie != null && savedCookie.isNotEmpty) {
        _sessionCookie = savedCookie;
      }
    } else {
      await _secureStorage.delete(key: _sessionCookieKey);
      _loginId = null;
      _role = null;
    }
    _localStateLoaded = true;
    _isInitializing = false;
  }

  Future<void> loadRemote({
    bool notify = true,
    bool checkForUpdate = true,
  }) async {
    if (_disposed) {
      return;
    }
    if (!_localStateLoaded) {
      await loadLocal(notify: false);
    }
    if (_disposed) {
      return;
    }
    if (checkForUpdate) {
      unawaited(
        checkForAppUpdate(notify: false).then((initialChecked) {
          if (!initialChecked && !_disposed) {
            return _retryAppUpdateCheckWithBackoff();
          }
        }),
      );
    }

    try {
      await refreshSession(notify: false);
    } catch (error) {
      if (error is ApiException && error.isTransportError) {
        _restoreOfflineSession();
      }
      // Keep setup hints when the backend is unavailable.
    } finally {
      if (!_disposed) {
        _remoteStateLoaded = true;
        if (_authenticated && !_offlineMode) {
          _startKeepAlive();
        }
        if (notify) {
          _notifySafely();
        }
      }
    }
  }

  void _restoreOfflineSession() {
    if (_rememberMe &&
        _sessionCookie?.isNotEmpty == true &&
        _loginId?.trim().isNotEmpty == true) {
      _authenticated = true;
      _offlineMode = true;
    }
  }

  Future<bool> checkForAppUpdate({
    bool notify = true,
    bool ignoreErrors = true,
  }) async {
    if (_disposed) {
      return false;
    }
    try {
      await _loadCurrentAppVersion();
      final requestContext = _captureRequestContext();
      final previousTarget = _updateInfo == null
          ? null
          : '${_updateInfo!.latestVersion}+${_updateInfo!.latestBuild}';

      final response = await _apiClient.fetchJson(
        requestContext.baseUrl,
        '/api/app-update/check',
        params: {
          'platform': _updatePlatform,
          'channel': 'prod',
          'version': _currentAppVersion,
          'build': _currentAppBuild,
        },
      );
      if (!_isCurrentRequest(requestContext)) {
        return true;
      }
      final payload = response.data;
      final parsedUpdate = AppUpdateInfo.fromJson(
        payload,
        fallbackVersion: _currentAppVersion,
      );
      _updateInfo = AppUpdateInfo(
        latestVersion: parsedUpdate.latestVersion,
        latestBuild: parsedUpdate.latestBuild,
        updateAvailable: parsedUpdate.updateAvailable &&
            parsedUpdate.latestBuild > _currentAppBuild,
        downloadUrl: parsedUpdate.downloadUrl,
        releaseNotes: parsedUpdate.releaseNotes,
        sha256: parsedUpdate.sha256,
        fileSize: parsedUpdate.fileSize,
        forceUpdate: parsedUpdate.forceUpdate,
      );
      final deployNoticePayload = payload['deploy_notice'];
      if (deployNoticePayload is Map<String, dynamic>) {
        final parsed = DeployNoticeInfo.fromJson(deployNoticePayload);
        _deployNotice = parsed.hasNoticeId ? parsed : null;
      } else if (deployNoticePayload is Map) {
        final parsed = DeployNoticeInfo.fromJson(
            Map<String, dynamic>.from(deployNoticePayload));
        _deployNotice = parsed.hasNoticeId ? parsed : null;
      } else {
        _deployNotice = null;
      }
      _lastUpdateCheckAt = DateTime.now();
      _lastUpdateCheckOk = true;
      _updateCheckRetryScheduled = false;

      final policyWarning = payload['policy_warning']?.toString().trim() ?? '';
      if (_updateInfo!.updateAvailable) {
        if (_updateInfo!.hasDownloadUrl) {
          _lastUpdateCheckMessage = '새 업데이트를 확인했습니다.';
        } else {
          _lastUpdateCheckMessage = '업데이트는 감지되었지만 다운로드 주소가 비어 있습니다.';
        }
      } else {
        _lastUpdateCheckMessage = '현재 최신 버전입니다.';
      }
      if (policyWarning.isNotEmpty) {
        _lastUpdateCheckMessage = '$_lastUpdateCheckMessage ($policyWarning)';
      }

      final nextTarget =
          '${_updateInfo!.latestVersion}+${_updateInfo!.latestBuild}';
      if (previousTarget != nextTarget) {
        _downloadedUpdatePath = null;
        _updateDownloadProgress = null;
        _updateStatusMessage = '';
      }

      if (!_updateInfo!.updateAvailable) {
        _downloadedUpdatePath = null;
        _updateDownloadProgress = null;
        _updateStatusMessage = '';
      }
      return true;
    } catch (error) {
      _lastUpdateCheckAt = DateTime.now();
      _lastUpdateCheckOk = false;
      _lastUpdateCheckMessage = '업데이트 확인 실패: ${_normalizeUpdateError(error)}';
      // Keep app usable even when update metadata cannot be fetched.
      if (!ignoreErrors) {
        rethrow;
      }
      return false;
    } finally {
      if (notify) {
        _notifySafely();
      }
    }
  }

  Future<void> markDeployNoticeSeen() async {
    final notice = _deployNotice;
    if (notice == null || !notice.hasNoticeId) {
      return;
    }
    _lastSeenDeployNoticeId = notice.noticeId;
    await _prefs.setString(_lastSeenDeployNoticeIdKey, _lastSeenDeployNoticeId);
    _notifySafely();
  }

  Future<void> _retryAppUpdateCheckWithBackoff() async {
    if (_updateCheckRetryScheduled) {
      return;
    }
    _updateCheckRetryScheduled = true;
    const retryDelays = [
      Duration(seconds: 5),
      Duration(seconds: 30),
    ];

    for (final delay in retryDelays) {
      await Future<void>.delayed(delay);
      if (_disposed) {
        return;
      }
      final ok = await checkForAppUpdate(ignoreErrors: true);
      if (ok) {
        _updateCheckRetryScheduled = false;
        return;
      }
    }
    _updateCheckRetryScheduled = false;
  }

  Future<void> downloadAndInstallAppUpdate() async {
    if (_updateInfo == null || !_updateInfo!.updateAvailable) {
      throw const ApiException('설치 가능한 업데이트 정보가 없습니다.');
    }
    if (!supportsInAppUpdateInstall) {
      throw const ApiException('이 기기에서는 인앱 APK 설치를 지원하지 않습니다.');
    }
    if (!_updateInfo!.hasDownloadUrl) {
      throw const ApiException('업데이트 다운로드 주소가 비어 있습니다.');
    }

    _isUpdateActionInProgress = true;
    _updateDownloadProgress = 0;
    _updateStatusMessage = '업데이트 패키지를 다운로드하는 중입니다.';
    _notifySafely();

    try {
      ApkDownloadResult? result;
      for (var attempt = 0; attempt < 2; attempt += 1) {
        final info = _updateInfo!;
        final cancellationToken = ApkDownloadCancellationToken();
        _updateCancellationToken = cancellationToken;
        try {
          result = await AppUpdateService.downloadApk(
            downloadUrl: info.downloadUrl,
            version: info.latestVersion,
            buildNumber: info.latestBuild,
            currentBuildNumber: _currentAppBuild,
            expectedSha256: info.sha256,
            expectedFileSize: info.fileSize,
            cancellationToken: cancellationToken,
            onProgress: (received, total) {
              _updateDownloadProgress = total > 0 ? received / total : null;
              _notifySafely();
            },
          );
          break;
        } on AppUpdateException catch (error) {
          if (!error.requiresMetadataRefresh || attempt > 0) {
            rethrow;
          }
          _updateStatusMessage = '배포 정보가 변경되어 최신 업데이트를 다시 확인합니다.';
          _updateDownloadProgress = 0;
          _notifySafely();
          await checkForAppUpdate(notify: false, ignoreErrors: false);
          final refreshed = _updateInfo;
          if (refreshed == null ||
              !refreshed.updateAvailable ||
              !refreshed.hasDownloadUrl) {
            throw const ApiException('새로 설치할 수 있는 업데이트가 없습니다.');
          }
        } finally {
          _updateCancellationToken = null;
        }
      }
      if (result == null) {
        throw const ApiException('업데이트 파일을 다운로드하지 못했습니다.');
      }

      _downloadedUpdatePath = result.filePath;
      _updateDownloadProgress = 1;
      _updateStatusMessage = '다운로드를 완료했습니다. 설치 화면을 여는 중입니다.';
      _notifySafely();

      await _requestInstaller(
        result.filePath,
        expectedBuildNumber: _updateInfo!.latestBuild,
      );
    } catch (error) {
      _updateStatusMessage = _normalizeUpdateError(error);
      rethrow;
    } finally {
      _isUpdateActionInProgress = false;
      _notifySafely();
    }
  }

  void cancelAppUpdateDownload() {
    final token = _updateCancellationToken;
    if (token == null) {
      return;
    }
    _updateStatusMessage = '업데이트 다운로드를 취소하는 중입니다.';
    token.cancel();
    _notifySafely();
  }

  Future<void> installDownloadedAppUpdate() async {
    if (!supportsInAppUpdateInstall) {
      throw const ApiException('이 기기에서는 인앱 APK 설치를 지원하지 않습니다.');
    }
    if (!canInstallDownloadedUpdate) {
      await downloadAndInstallAppUpdate();
      return;
    }

    _isUpdateActionInProgress = true;
    _updateStatusMessage = '설치 화면을 다시 여는 중입니다.';
    _notifySafely();

    try {
      await _requestInstaller(
        _downloadedUpdatePath!,
        expectedBuildNumber: _updateInfo!.latestBuild,
      );
    } catch (error) {
      _updateStatusMessage = _normalizeUpdateError(error);
      rethrow;
    } finally {
      _isUpdateActionInProgress = false;
      _notifySafely();
    }
  }

  Future<void> _requestInstaller(
    String filePath, {
    required int expectedBuildNumber,
  }) async {
    final result = await AppUpdateService.requestInstaller(
      filePath,
      expectedBuildNumber: expectedBuildNumber,
    );
    _updateStatusMessage = result.message;
    if (result.status == AppInstallerStatus.permissionRequired &&
        !_retryingInstallerAfterResume) {
      _installerAutoRetryPending = true;
    }
  }

  Future<void> handleAppResumed() async {
    if (_disposed || _resumeRefreshInFlight || !_localStateLoaded) {
      return;
    }
    _resumeRefreshInFlight = true;
    try {
      await Future.wait<void>([
        checkForAppUpdate(notify: false),
        if (_sessionCookie?.isNotEmpty == true) refreshSession(notify: false),
      ]);
      if (_installerAutoRetryPending && canInstallDownloadedUpdate) {
        _installerAutoRetryPending = false;
        _retryingInstallerAfterResume = true;
        try {
          await installDownloadedAppUpdate();
        } finally {
          _retryingInstallerAfterResume = false;
        }
      }
    } catch (_) {
      // Resume refresh is best-effort; individual states retain their errors.
    } finally {
      _resumeRefreshInFlight = false;
      _notifySafely();
    }
  }

  Future<void> refreshSession({bool notify = true}) async {
    if (_disposed) {
      return;
    }
    final requestContext = _captureRequestContext();
    final previousAuthenticated = _authenticated;
    final previousRole = _role;
    var identityChanged = false;
    try {
      final response = await _apiClient.fetchJson(
        requestContext.baseUrl,
        '/api/auth/session',
        sessionCookie: requestContext.sessionCookie,
      );
      if (!_isCurrentRequest(requestContext)) {
        return;
      }
      final payload = response.data;
      _setupRequired = payload['setup_required'] == true;
      _bootstrapConfigured = payload['bootstrap_configured'] == true;
      _lastSessionSyncAt = DateTime.now();

      if (response.sessionCookie != null &&
          response.sessionCookie!.isNotEmpty) {
        await _acceptSessionCookie(
          response.sessionCookie!,
          requestSequence: requestContext.sequence,
        );
      }

      final user = payload['user'];
      if (payload['authenticated'] == true && user is Map) {
        final nextLoginId = user['login_id']?.toString();
        final nextRole = user['role']?.toString();
        identityChanged = _loginId != nextLoginId || _role != nextRole;
        if (identityChanged) {
          await _cacheStore.clearScope(requestContext.scope);
          await _activeTaskStore.removeScope(requestContext.scope);
          _sessionEpoch += 1;
        }
        _authenticated = true;
        _offlineMode = false;
        _loginId = nextLoginId;
        _role = nextRole;
        _csrfToken = payload['csrf_token']?.toString();
        await _persistAuthIdentity();
        _startKeepAlive();
      } else {
        await _clearAuthState(preserveSetupFlags: true);
        if (notify) {
          _notifySafely();
        }
      }
    } on ApiException catch (error) {
      if (_isCurrentRequest(requestContext) && error.statusCode == 401) {
        await _clearAuthState(preserveSetupFlags: true);
        if (notify) {
          _notifySafely();
        }
      }
      rethrow;
    } finally {
      if (_isCurrentRequest(requestContext) || identityChanged) {
        await _persistSetupState();
        _refreshCacheCount();
        if (notify ||
            previousAuthenticated != _authenticated ||
            previousRole != _role) {
          _notifySafely();
        }
      }
    }
  }

  Future<void> login(
    String loginId,
    String password, {
    bool? rememberMe,
  }) async {
    final trimmedId = loginId.trim();
    final useRememberMe = rememberMe ?? _rememberMe;
    if (trimmedId.isEmpty || password.isEmpty) {
      throw const ApiException('아이디와 비밀번호를 입력하세요.');
    }

    final previousScope = _cacheScope;
    final requestEpoch = ++_sessionEpoch;
    final requestContext = _captureRequestContext();
    final response = await _apiClient.postJson(
      requestContext.baseUrl,
      '/api/auth/login',
      body: {
        'login_id': trimmedId,
        'password': password,
        'remember_me': useRememberMe,
      },
      includeCsrfToken: false,
    );

    if (_disposed ||
        requestEpoch != _sessionEpoch ||
        requestContext.baseUrl != _apiBaseUrl) {
      throw const ApiException('로그인 요청이 만료되었습니다. 다시 시도해 주세요.');
    }

    final user = response.data['user'];
    if (user is! Map ||
        response.sessionCookie == null ||
        response.sessionCookie!.isEmpty) {
      throw const ApiException('로그인 응답이 올바르지 않습니다.');
    }

    final nextLoginId = user['login_id']?.toString();
    final nextScope =
        '${nextLoginId?.trim().isNotEmpty == true ? nextLoginId!.trim() : 'guest'}@${requestContext.baseUrl}';
    if (previousScope != nextScope) {
      await _activeTaskStore.removeScope(previousScope);
      await _cacheStore.clearScope(previousScope);
    }
    _authenticated = true;
    _offlineMode = false;
    _rememberMe = useRememberMe;
    await _prefs.setBool(_rememberMeKey, _rememberMe);
    await _acceptSessionCookie(
      response.sessionCookie!,
      requestSequence: requestContext.sequence,
    );
    _csrfToken = response.data['csrf_token']?.toString();
    _loginId = nextLoginId;
    _role = user['role']?.toString();
    await _persistAuthIdentity();
    _setupRequired = false;
    _lastSessionSyncAt = DateTime.now();
    _startKeepAlive();
    await _persistSetupState();
    _refreshCacheCount();
    _notifySafely();
  }

  Future<void> setRememberMe(bool value) async {
    if (_rememberMe == value) {
      if (value && _sessionCookie?.isNotEmpty == true) {
        await _secureStorage.write(
          key: _sessionCookieKey,
          value: _sessionCookie,
        );
      } else if (!value) {
        await _secureStorage.delete(key: _sessionCookieKey);
      }
      if (value && _loginId?.isNotEmpty == true) {
        await _persistAuthIdentity();
      }
      return;
    }
    _rememberMe = value;
    await _prefs.setBool(_rememberMeKey, value);
    if (value && _sessionCookie?.isNotEmpty == true) {
      await _secureStorage.write(
        key: _sessionCookieKey,
        value: _sessionCookie,
      );
    } else if (!value) {
      await _secureStorage.delete(key: _sessionCookieKey);
      await _prefs.remove(_lastLoginIdKey);
      await _prefs.remove(_lastRoleKey);
    }
    if (value && _loginId?.isNotEmpty == true) {
      await _persistAuthIdentity();
    }
    _notifySafely();
  }

  Future<void> logout() async {
    final previousScope = _cacheScope;
    _sessionEpoch += 1;
    _stopKeepAlive();
    try {
      await _postJsonWithAuth('/api/auth/logout');
    } catch (_) {
      // Clear the local session even if the server is unreachable.
    }

    await _clearAuthState(scopeToClear: previousScope);
    _refreshCacheCount();
    _notifySafely();
  }

  Future<void> updateApiBaseUrl(String value) async {
    final previousScope = _cacheScope;
    _sessionEpoch += 1;
    _apiBaseUrl = ApiService.normalizeBaseUrl(value);
    await _prefs.setString(_apiBaseUrlKey, _apiBaseUrl);
    await _clearAuthState(
      preserveSetupFlags: false,
      scopeToClear: previousScope,
    );
    _refreshCacheCount();
    _notifySafely();
  }

  Future<void> resetApiBaseUrl() async {
    final previousScope = _cacheScope;
    _sessionEpoch += 1;
    _apiBaseUrl = ApiService.defaultBaseUrl();
    await _prefs.remove(_apiBaseUrlKey);
    await _clearAuthState(
      preserveSetupFlags: false,
      scopeToClear: previousScope,
    );
    _refreshCacheCount();
    _notifySafely();
  }

  Future<bool> checkConnection(String rawBaseUrl) async {
    final baseUrl = ApiService.normalizeBaseUrl(rawBaseUrl);
    final response = await _apiClient.fetchJson(baseUrl, '/healthz');
    return response.data['ok'] == true;
  }

  Future<void> _loadCurrentAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _currentAppVersion = packageInfo.version.trim().isEmpty
          ? '1.0.0'
          : packageInfo.version.trim();
      _currentAppBuild = int.tryParse(packageInfo.buildNumber.trim()) ?? 1;
      return;
    } catch (_) {
      const versionText = String.fromEnvironment(
        'APP_VERSION',
        defaultValue: '1.0.0+1',
      );
      final split = versionText.split('+');
      _currentAppVersion =
          split.first.trim().isEmpty ? '1.0.0' : split.first.trim();
      _currentAppBuild =
          split.length > 1 ? int.tryParse(split[1].trim()) ?? 1 : 1;
    }
  }

  String get _updatePlatform {
    if (kIsWeb) {
      return 'web';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  String _normalizeUpdateError(Object error) {
    final message = error.toString();
    if (message.startsWith('Exception: ')) {
      return message.substring('Exception: '.length);
    }
    return message;
  }

  Future<int> clearCache() async {
    final removed = await _cacheStore.clearAll();
    _refreshCacheCount();
    _notifySafely();
    return removed;
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final trimmedCurrent = currentPassword.trim();
    final trimmedNext = newPassword.trim();
    if (trimmedCurrent.isEmpty || trimmedNext.isEmpty) {
      throw const ApiException('현재 비밀번호와 새 비밀번호를 모두 입력하세요.');
    }
    if (trimmedNext.length < 12) {
      throw const ApiException('새 비밀번호는 최소 12자 이상이어야 합니다.');
    }

    await _postJsonWithAuth(
      '/api/auth/change-password',
      body: {
        'current_password': trimmedCurrent,
        'new_password': trimmedNext,
      },
    );
    await _clearAuthState();
    _refreshCacheCount();
    _notifySafely();
  }

  Future<CachedDataResult<T>> fetchMapParsed<T>(
    String endpoint, {
    Map<String, Object?>? params,
    required T Function(Map<String, dynamic> json) parser,
    Duration cacheTtl = const Duration(minutes: 30),
    bool allowStaleOnError = true,
    ApiCachePolicy? cachePolicy,
  }) {
    return _fetchParsed<T>(
      endpoint: endpoint,
      params: params,
      parser: (value) => parser(Map<String, dynamic>.from(value as Map)),
      cacheTtl: cacheTtl,
      allowStaleOnError: allowStaleOnError,
      cachePolicy: cachePolicy,
    );
  }

  Future<CachedDataResult<T>> _fetchParsed<T>({
    required String endpoint,
    Map<String, Object?>? params,
    required T Function(Object value) parser,
    required Duration cacheTtl,
    required bool allowStaleOnError,
    ApiCachePolicy? cachePolicy,
  }) async {
    final effectiveCachePolicy =
        cachePolicy ?? ApiCachePolicy.forEndpoint(endpoint);
    final requestContext = _captureRequestContext();
    final cacheEntry = _cacheStore.read(
      scope: requestContext.scope,
      baseUrl: requestContext.baseUrl,
      endpoint: endpoint,
      params: params,
      policy: effectiveCachePolicy,
    );
    final canUseCache = _isCacheFresh(cacheEntry, cacheTtl);
    final wasOffline = _offlineMode;

    try {
      final response = await _apiClient.fetchJson(
        requestContext.baseUrl,
        endpoint,
        params: params,
        sessionCookie: requestContext.sessionCookie,
      );
      final parsed = parser(response.data);
      if (_isCurrentRequest(requestContext)) {
        _offlineMode = false;
        if (response.sessionCookie != null &&
            response.sessionCookie!.isNotEmpty) {
          await _acceptSessionCookie(
            response.sessionCookie!,
            requestSequence: requestContext.sequence,
          );
        }
        await _cacheStore.write(
          scope: requestContext.scope,
          baseUrl: requestContext.baseUrl,
          endpoint: endpoint,
          params: params,
          data: response.data,
          policy: effectiveCachePolicy,
        );
        _refreshCacheCount();
      }
      return CachedDataResult<T>(
        data: parsed,
        fromCache: false,
        cachedAt: DateTime.now(),
      );
    } on ApiException catch (error) {
      await _handleAuthError(error, requestContext);
      if (_isCurrentRequest(requestContext) &&
          error.isTransportError &&
          allowStaleOnError &&
          canUseCache &&
          cacheEntry != null &&
          cacheEntry.data is Map) {
        final changed = !_offlineMode;
        _offlineMode = true;
        if (changed) {
          _notifySafely();
        }
        return CachedDataResult<T>(
          data: parser(Map<String, dynamic>.from(cacheEntry.data as Map)),
          fromCache: true,
          cachedAt: cacheEntry.cachedAt,
        );
      }
      rethrow;
    } finally {
      if (_isCurrentRequest(requestContext) && !_offlineMode && wasOffline) {
        _notifySafely();
      }
    }
  }

  Future<Map<String, dynamic>> postJson(
    String endpoint, {
    Map<String, dynamic>? body,
    String method = 'POST',
  }) async {
    final response =
        await _postJsonWithAuth(endpoint, body: body, method: method);
    if (!_disposed) {
      final changed = _offlineMode;
      _offlineMode = false;
      if (changed) {
        _notifySafely();
      }
    }
    return response.data;
  }

  Future<ApiResponse<Map<String, dynamic>>> _postJsonWithAuth(
    String endpoint, {
    Map<String, dynamic>? body,
    bool allowRetry = true,
    String method = 'POST',
  }) async {
    final requestContext = _captureRequestContext();
    try {
      final response = await _apiClient.postJson(
        requestContext.baseUrl,
        endpoint,
        body: body,
        sessionCookie: requestContext.sessionCookie,
        csrfToken: requestContext.csrfToken,
        method: method,
      );
      if (_isCurrentRequest(requestContext) &&
          response.sessionCookie != null &&
          response.sessionCookie!.isNotEmpty) {
        await _acceptSessionCookie(
          response.sessionCookie!,
          requestSequence: requestContext.sequence,
        );
      }
      return response;
    } on ApiException catch (error) {
      if (error.statusCode == 403 &&
          allowRetry &&
          _isCurrentRequest(requestContext) &&
          error.message.toLowerCase().contains('csrf')) {
        await refreshSession();
        return _postJsonWithAuth(
          endpoint,
          body: body,
          allowRetry: false,
          method: method,
        );
      }
      await _handleAuthError(error, requestContext);
      rethrow;
    }
  }

  Future<void> _handleAuthError(
    ApiException error,
    _RequestContext requestContext,
  ) async {
    if (_isCurrentRequest(requestContext) && error.statusCode == 401) {
      await _clearAuthState(preserveSetupFlags: true);
      _notifySafely();
    }
  }

  Future<void> _persistSetupState() async {
    await _prefs.setBool(_setupRequiredKey, _setupRequired);
    await _prefs.setBool(_bootstrapConfiguredKey, _bootstrapConfigured);
  }

  Future<void> _persistAuthIdentity() async {
    if (_rememberMe && _loginId?.trim().isNotEmpty == true) {
      await _prefs.setString(_lastLoginIdKey, _loginId!.trim());
      if (_role?.trim().isNotEmpty == true) {
        await _prefs.setString(_lastRoleKey, _role!.trim());
      }
    } else {
      await _prefs.remove(_lastLoginIdKey);
      await _prefs.remove(_lastRoleKey);
    }
  }

  Future<void> _acceptSessionCookie(
    String cookie, {
    required int requestSequence,
  }) async {
    if (requestSequence < _lastCookieRequestSequence || _disposed) {
      return;
    }
    _lastCookieRequestSequence = requestSequence;
    _sessionCookie = cookie;
    if (_rememberMe) {
      await _secureStorage.write(key: _sessionCookieKey, value: cookie);
    } else {
      await _secureStorage.delete(key: _sessionCookieKey);
    }
  }

  Future<void> _clearAuthState({
    bool preserveSetupFlags = false,
    String? scopeToClear,
  }) async {
    final previousScope = scopeToClear ?? _cacheScope;
    _sessionEpoch += 1;
    _stopKeepAlive();
    _authenticated = false;
    _offlineMode = false;
    _sessionCookie = null;
    _csrfToken = null;
    _loginId = null;
    _role = null;
    _lastSessionSyncAt = null;
    await _secureStorage.delete(key: _sessionCookieKey);
    await _prefs.remove(_lastLoginIdKey);
    await _prefs.remove(_lastRoleKey);
    if (_localStateLoaded) {
      await _cacheStore.clearScope(previousScope);
      await _activeTaskStore.removeScope(previousScope);
      _refreshCacheCount();
    }

    if (!preserveSetupFlags) {
      _setupRequired = false;
      _bootstrapConfigured = false;
      await _prefs.remove(_setupRequiredKey);
      await _prefs.remove(_bootstrapConfiguredKey);
    }
  }

  void _startKeepAlive() {
    if (_disposed || !_authenticated || _offlineMode) {
      _stopKeepAlive();
      return;
    }
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(_keepAliveInterval, (_) {
      _runKeepAliveTick();
    });
  }

  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  Future<void> _runKeepAliveTick() async {
    if (_disposed || !_authenticated || _offlineMode || _keepAliveInFlight) {
      return;
    }
    _keepAliveInFlight = true;
    try {
      await refreshSession(notify: false);
    } catch (_) {
      // Ignore transient keepalive errors.
    } finally {
      _keepAliveInFlight = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stopKeepAlive();
    _updateCancellationToken?.cancel();
    _apiClient.close();
    super.dispose();
  }

  void _refreshCacheCount() {
    if (!_cacheStoreReady) {
      return;
    }
    _cacheEntryCount = _cacheStore.countAll();
  }

  bool _isCacheFresh(CacheEntry? entry, Duration ttl) {
    if (entry == null) {
      return false;
    }
    return DateTime.now().difference(entry.cachedAt) <= ttl;
  }

  String get _cacheScope {
    final userScope =
        _loginId?.trim().isNotEmpty == true ? _loginId!.trim() : 'guest';
    return '$userScope@$_apiBaseUrl';
  }

  _RequestContext _captureRequestContext() {
    return _RequestContext(
      epoch: _sessionEpoch,
      sequence: ++_requestSequence,
      baseUrl: _apiBaseUrl,
      scope: _cacheScope,
      sessionCookie: _sessionCookie,
      csrfToken: _csrfToken,
    );
  }

  bool _isCurrentRequest(_RequestContext requestContext) {
    return !_disposed &&
        requestContext.epoch == _sessionEpoch &&
        requestContext.baseUrl == _apiBaseUrl &&
        requestContext.scope == _cacheScope;
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<String?> readActiveTask(String taskPrefix) async {
    await loadLocal(notify: false);
    return _activeTaskStore.read(prefix: taskPrefix, scope: _cacheScope);
  }

  Future<void> saveActiveTask(String taskPrefix, String taskId) async {
    await loadLocal(notify: false);
    await _activeTaskStore.write(
      prefix: taskPrefix,
      scope: _cacheScope,
      taskId: taskId,
    );
  }

  Future<void> clearActiveTask(String taskPrefix) async {
    await loadLocal(notify: false);
    await _activeTaskStore.remove(prefix: taskPrefix, scope: _cacheScope);
  }
}

class _RequestContext {
  const _RequestContext({
    required this.epoch,
    required this.sequence,
    required this.baseUrl,
    required this.scope,
    required this.sessionCookie,
    required this.csrfToken,
  });

  final int epoch;
  final int sequence;
  final String baseUrl;
  final String scope;
  final String? sessionCookie;
  final String? csrfToken;
}
