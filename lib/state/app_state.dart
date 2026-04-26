import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/api_contracts.dart';
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
      default:
        return UserRole.viewer;
    }
  }

  int get rank {
    switch (this) {
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
      case UserRole.viewer:
        return 'viewer';
      case UserRole.operator:
        return 'operator';
      case UserRole.admin:
        return 'admin';
    }
  }

  bool allows(UserRole required) => rank >= required.rank;
}

class AppState extends ChangeNotifier {
  AppState() : _apiBaseUrl = ApiService.defaultBaseUrl();

  static const String _apiBaseUrlKey = 'api_base_url';
  static const String _setupRequiredKey = 'auth_setup_required';
  static const String _bootstrapConfiguredKey = 'auth_bootstrap_configured';
  static const String _sessionCookieKey = 'session_cookie';
  static const String _rememberMeKey = 'auth_remember_me';
  static const String _lastSeenDeployNoticeIdKey = 'last_seen_deploy_notice_id';
  static const Duration _keepAliveInterval = Duration(minutes: 4);

  static const _secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  String _apiBaseUrl;
  late SharedPreferences _prefs;
  late ApiCacheStore _cacheStore;
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
  Timer? _keepAliveTimer;
  bool _keepAliveInFlight = false;

  String get apiBaseUrl => _apiBaseUrl;
  bool get isInitializing => _isInitializing;
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
    String get currentAppVersionLabel => formatVersionDisplay(_currentAppVersion, _currentAppBuild);
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
      (_downloadedUpdatePath?.isNotEmpty ?? false) && supportsInAppUpdateInstall;
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

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _cacheStore = ApiCacheStore(_prefs);

    final savedBaseUrl = _prefs.getString(_apiBaseUrlKey);
    if (savedBaseUrl != null && savedBaseUrl.trim().isNotEmpty) {
      _apiBaseUrl = ApiService.normalizeBaseUrl(savedBaseUrl);
    }

    _setupRequired = _prefs.getBool(_setupRequiredKey) ?? false;
    _bootstrapConfigured = _prefs.getBool(_bootstrapConfiguredKey) ?? false;
    _rememberMe = _prefs.getBool(_rememberMeKey) ?? false;
    _lastSeenDeployNoticeId = _prefs.getString(_lastSeenDeployNoticeIdKey) ?? '';
    _refreshCacheCount();

    await _loadCurrentAppVersion();
    final initialChecked = await checkForAppUpdate(notify: false);
    if (!initialChecked) {
      unawaited(_retryAppUpdateCheckWithBackoff());
    }

    // Restore persisted session cookie so the user doesn't need to log in again.
    final savedCookie = await _secureStorage.read(key: _sessionCookieKey);
    if (savedCookie != null && savedCookie.isNotEmpty) {
      _sessionCookie = savedCookie;
    }

    try {
      await refreshSession(notify: false);
    } catch (_) {
      // Keep setup hints and require a fresh login if the backend is unavailable.
    } finally {
      if (_authenticated) {
        _startKeepAlive();
      }
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<bool> checkForAppUpdate({
    bool notify = true,
    bool ignoreErrors = true,
  }) async {
    try {
      await _loadCurrentAppVersion();
      final previousTarget = _updateInfo == null
          ? null
          : '${_updateInfo!.latestVersion}+${_updateInfo!.latestBuild}';

      final response = await ApiService.fetchJson(
        _apiBaseUrl,
        '/api/app-update/check',
        params: {
          'platform': _updatePlatform,
          'channel': 'prod',
          'version': _currentAppVersion,
          'build': _currentAppBuild,
        },
      );
      final payload = response.data;
      _updateInfo = AppUpdateInfo.fromJson(
        payload,
        fallbackVersion: _currentAppVersion,
      );
      final deployNoticePayload = payload['deploy_notice'];
      if (deployNoticePayload is Map<String, dynamic>) {
        final parsed = DeployNoticeInfo.fromJson(deployNoticePayload);
        _deployNotice = parsed.hasNoticeId ? parsed : null;
      } else if (deployNoticePayload is Map) {
        final parsed = DeployNoticeInfo.fromJson(Map<String, dynamic>.from(deployNoticePayload));
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
          _lastUpdateCheckMessage =
              '업데이트는 감지되었지만 다운로드 주소가 비어 있습니다.';
        }
      } else {
        _lastUpdateCheckMessage = '현재 최신 버전입니다.';
      }
      if (policyWarning.isNotEmpty) {
        _lastUpdateCheckMessage =
            '${_lastUpdateCheckMessage} ($policyWarning)';
      }

      final nextTarget = '${_updateInfo!.latestVersion}+${_updateInfo!.latestBuild}';
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
      _lastUpdateCheckMessage =
          '업데이트 확인 실패: ${_normalizeUpdateError(error)}';
      // Keep app usable even when update metadata cannot be fetched.
      if (!ignoreErrors) {
        rethrow;
      }
      return false;
    } finally {
      if (notify) {
        notifyListeners();
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
    notifyListeners();
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
      final ok = await checkForAppUpdate(ignoreErrors: true);
      if (ok) {
        _updateCheckRetryScheduled = false;
        return;
      }
    }
    _updateCheckRetryScheduled = false;
  }

  Future<void> downloadAndInstallAppUpdate() async {
    final info = _updateInfo;
    if (info == null || !info.updateAvailable) {
      throw const ApiException('설치 가능한 업데이트 정보가 없습니다.');
    }
    if (!supportsInAppUpdateInstall) {
      throw const ApiException('이 기기에서는 인앱 APK 설치를 지원하지 않습니다.');
    }
    if (!info.hasDownloadUrl) {
      throw const ApiException('업데이트 다운로드 주소가 비어 있습니다.');
    }

    _isUpdateActionInProgress = true;
    _updateDownloadProgress = 0;
    _updateStatusMessage = '업데이트 패키지를 다운로드하는 중입니다.';
    notifyListeners();

    try {
      final result = await AppUpdateService.downloadApk(
        downloadUrl: info.downloadUrl,
        version: info.latestVersion,
        buildNumber: info.latestBuild,
        expectedSha256: info.sha256,
        expectedFileSize: info.fileSize,
        onProgress: (received, total) {
          _updateDownloadProgress = total > 0 ? received / total : null;
          notifyListeners();
        },
      );

      _downloadedUpdatePath = result.filePath;
      _updateDownloadProgress = 1;
      _updateStatusMessage = '다운로드를 완료했습니다. 설치 화면을 여는 중입니다.';
      notifyListeners();

      _updateStatusMessage =
          await AppUpdateService.openInstaller(result.filePath);
    } catch (error) {
      _updateStatusMessage = _normalizeUpdateError(error);
      rethrow;
    } finally {
      _isUpdateActionInProgress = false;
      notifyListeners();
    }
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
    notifyListeners();

    try {
      _updateStatusMessage =
          await AppUpdateService.openInstaller(_downloadedUpdatePath!);
    } catch (error) {
      _updateStatusMessage = _normalizeUpdateError(error);
      rethrow;
    } finally {
      _isUpdateActionInProgress = false;
      notifyListeners();
    }
  }

  Future<void> refreshSession({bool notify = true}) async {
    try {
      final response = await ApiService.fetchJson(
        _apiBaseUrl,
        '/api/auth/session',
        sessionCookie: _sessionCookie,
      );
      final payload = response.data;
      _setupRequired = payload['setup_required'] == true;
      _bootstrapConfigured = payload['bootstrap_configured'] == true;
      _lastSessionSyncAt = DateTime.now();

      if (response.sessionCookie != null &&
          response.sessionCookie!.isNotEmpty) {
        _sessionCookie = response.sessionCookie;
        await _secureStorage.write(
          key: _sessionCookieKey,
          value: _sessionCookie,
        );
      }

      final user = payload['user'];
      if (payload['authenticated'] == true && user is Map) {
        _authenticated = true;
        _offlineMode = false;
        _loginId = user['login_id']?.toString();
        _role = user['role']?.toString();
        _csrfToken = payload['csrf_token']?.toString();
        _startKeepAlive();
      } else {
        await _clearAuthState(preserveSetupFlags: true);
      }
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _clearAuthState(preserveSetupFlags: true);
      }
      rethrow;
    } finally {
      await _persistSetupState();
      _refreshCacheCount();
      if (notify) {
        notifyListeners();
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

    final response = await ApiService.postJson(
      _apiBaseUrl,
      '/api/auth/login',
      body: {
        'login_id': trimmedId,
        'password': password,
        'remember_me': useRememberMe,
      },
      includeCsrfToken: false,
    );

    final user = response.data['user'];
    if (user is! Map ||
        response.sessionCookie == null ||
        response.sessionCookie!.isEmpty) {
      throw const ApiException('로그인 응답이 올바르지 않습니다.');
    }

    _authenticated = true;
    _offlineMode = false;
    _rememberMe = useRememberMe;
    await _prefs.setBool(_rememberMeKey, _rememberMe);
    _sessionCookie = response.sessionCookie;
    await _secureStorage.write(key: _sessionCookieKey, value: _sessionCookie);
    _csrfToken = response.data['csrf_token']?.toString();
    _loginId = user['login_id']?.toString();
    _role = user['role']?.toString();
    _setupRequired = false;
    _lastSessionSyncAt = DateTime.now();
    _startKeepAlive();
    await _persistSetupState();
    _refreshCacheCount();
    notifyListeners();
  }

  Future<void> setRememberMe(bool value) async {
    if (_rememberMe == value) {
      return;
    }
    _rememberMe = value;
    await _prefs.setBool(_rememberMeKey, value);
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await _postJsonWithAuth('/api/auth/logout');
    } catch (_) {
      // Clear the local session even if the server is unreachable.
    }

    final scope = _cacheScope;
    await _clearAuthState();
    await _cacheStore.clearScope(scope);
    _refreshCacheCount();
    notifyListeners();
  }

  Future<void> updateApiBaseUrl(String value) async {
    _apiBaseUrl = ApiService.normalizeBaseUrl(value);
    await _prefs.setString(_apiBaseUrlKey, _apiBaseUrl);
    await _clearAuthState(preserveSetupFlags: false);
    _refreshCacheCount();
    notifyListeners();
  }

  Future<void> resetApiBaseUrl() async {
    _apiBaseUrl = ApiService.defaultBaseUrl();
    await _prefs.remove(_apiBaseUrlKey);
    await _clearAuthState(preserveSetupFlags: false);
    _refreshCacheCount();
    notifyListeners();
  }

  Future<void> _loadCurrentAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _currentAppVersion =
          packageInfo.version.trim().isEmpty ? '1.0.0' : packageInfo.version.trim();
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
    notifyListeners();
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

    final scope = _cacheScope;
    await _postJsonWithAuth(
      '/api/auth/change-password',
      body: {
        'current_password': trimmedCurrent,
        'new_password': trimmedNext,
      },
    );
    await _clearAuthState();
    await _cacheStore.clearScope(scope);
    _refreshCacheCount();
    notifyListeners();
  }

  Future<CachedDataResult<T>> fetchMapParsed<T>(
    String endpoint, {
    Map<String, Object?>? params,
    required T Function(Map<String, dynamic> json) parser,
    Duration cacheTtl = const Duration(minutes: 30),
    bool allowStaleOnError = true,
  }) async {
    final cacheEntry = _cacheStore.read(
      scope: _cacheScope,
      baseUrl: _apiBaseUrl,
      endpoint: endpoint,
      params: params,
    );
    final canUseCache = _isCacheFresh(cacheEntry, cacheTtl);
    final wasOffline = _offlineMode;

    try {
      final response = await ApiService.fetchJson(
        _apiBaseUrl,
        endpoint,
        params: params,
        sessionCookie: _sessionCookie,
      );
      _offlineMode = false;
      if (response.sessionCookie != null &&
          response.sessionCookie!.isNotEmpty) {
        _sessionCookie = response.sessionCookie;
      }
      await _cacheStore.write(
        scope: _cacheScope,
        baseUrl: _apiBaseUrl,
        endpoint: endpoint,
        params: params,
        data: response.data,
      );
      _refreshCacheCount();
      return CachedDataResult<T>(
        data: parser(response.data),
        fromCache: false,
        cachedAt: DateTime.now(),
      );
    } on ApiException catch (error) {
      await _handleAuthError(error);
      if (allowStaleOnError &&
          canUseCache &&
          cacheEntry != null &&
          cacheEntry.data is Map) {
        final changed = !_offlineMode;
        _offlineMode = true;
        if (changed) {
          notifyListeners();
        }
        return CachedDataResult<T>(
          data: parser(Map<String, dynamic>.from(cacheEntry.data as Map)),
          fromCache: true,
          cachedAt: cacheEntry.cachedAt,
        );
      }
      rethrow;
    } finally {
      if (!_offlineMode && wasOffline) {
        notifyListeners();
      }
    }
  }

  Future<CachedDataResult<T>> fetchListParsed<T>(
    String endpoint, {
    Map<String, Object?>? params,
    required T Function(List<dynamic> json) parser,
    Duration cacheTtl = const Duration(minutes: 30),
    bool allowStaleOnError = true,
  }) async {
    final cacheEntry = _cacheStore.read(
      scope: _cacheScope,
      baseUrl: _apiBaseUrl,
      endpoint: endpoint,
      params: params,
    );
    final canUseCache = _isCacheFresh(cacheEntry, cacheTtl);
    final wasOffline = _offlineMode;

    try {
      final response = await ApiService.fetchJsonList(
        _apiBaseUrl,
        endpoint,
        params: params,
        sessionCookie: _sessionCookie,
      );
      _offlineMode = false;
      if (response.sessionCookie != null &&
          response.sessionCookie!.isNotEmpty) {
        _sessionCookie = response.sessionCookie;
      }
      await _cacheStore.write(
        scope: _cacheScope,
        baseUrl: _apiBaseUrl,
        endpoint: endpoint,
        params: params,
        data: response.data,
      );
      _refreshCacheCount();
      return CachedDataResult<T>(
        data: parser(response.data),
        fromCache: false,
        cachedAt: DateTime.now(),
      );
    } on ApiException catch (error) {
      await _handleAuthError(error);
      if (allowStaleOnError &&
          canUseCache &&
          cacheEntry != null &&
          cacheEntry.data is List) {
        final changed = !_offlineMode;
        _offlineMode = true;
        if (changed) {
          notifyListeners();
        }
        return CachedDataResult<T>(
          data: parser(List<dynamic>.from(cacheEntry.data as List)),
          fromCache: true,
          cachedAt: cacheEntry.cachedAt,
        );
      }
      rethrow;
    } finally {
      if (!_offlineMode && wasOffline) {
        notifyListeners();
      }
    }
  }

  Future<Map<String, dynamic>> postJson(
    String endpoint, {
    Map<String, dynamic>? body,
    String method = 'POST',
  }) async {
    final response = await _postJsonWithAuth(endpoint, body: body, method: method);
    final changed = _offlineMode;
    _offlineMode = false;
    if (changed) {
      notifyListeners();
    }
    return response.data;
  }

  Future<ApiResponse<Map<String, dynamic>>> _postJsonWithAuth(
    String endpoint, {
    Map<String, dynamic>? body,
    bool allowRetry = true,
    String method = 'POST',
  }) async {
    try {
      final response = await ApiService.postJson(
        _apiBaseUrl,
        endpoint,
        body: body,
        sessionCookie: _sessionCookie,
        csrfToken: _csrfToken,
        method: method,
      );
      if (response.sessionCookie != null &&
          response.sessionCookie!.isNotEmpty) {
        _sessionCookie = response.sessionCookie;
        await _secureStorage.write(
          key: _sessionCookieKey,
          value: _sessionCookie,
        );
      }
      return response;
    } on ApiException catch (error) {
      if (error.statusCode == 403 &&
          allowRetry &&
          error.message.contains('CSRF')) {
        await refreshSession();
        return _postJsonWithAuth(
          endpoint,
          body: body,
          allowRetry: false,
          method: method,
        );
      }
      await _handleAuthError(error);
      rethrow;
    }
  }

  Future<void> _handleAuthError(ApiException error) async {
    if (error.statusCode == 401) {
      await _clearAuthState(preserveSetupFlags: true);
      notifyListeners();
    }
  }

  Future<void> _persistSetupState() async {
    await _prefs.setBool(_setupRequiredKey, _setupRequired);
    await _prefs.setBool(_bootstrapConfiguredKey, _bootstrapConfigured);
  }

  Future<void> _clearAuthState({bool preserveSetupFlags = false}) async {
    _stopKeepAlive();
    _authenticated = false;
    _offlineMode = false;
    _sessionCookie = null;
    _csrfToken = null;
    _loginId = null;
    _role = null;
    _lastSessionSyncAt = null;
    await _secureStorage.delete(key: _sessionCookieKey);

    if (!preserveSetupFlags) {
      _setupRequired = false;
      _bootstrapConfigured = false;
      await _prefs.remove(_setupRequiredKey);
      await _prefs.remove(_bootstrapConfiguredKey);
    }
  }

  void _startKeepAlive() {
    if (!_authenticated) {
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
    if (!_authenticated || _keepAliveInFlight) {
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
    _stopKeepAlive();
    super.dispose();
  }

  void _refreshCacheCount() {
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
}
