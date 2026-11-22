import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/access_gate.dart';
import '../widgets/app_screen.dart';
import '../widgets/panel.dart';

typedef DailyReportsAdminRequest = Future<Map<String, dynamic>> Function(
  String endpoint, {
  required String method,
  Map<String, Object?>? params,
  Map<String, dynamic>? body,
});

/// An isolated, admin-only counterpart to `/admin/daily-reports`.
///
/// [requestJson] is intended for focused widget tests. Production requests use
/// AppState so session cookies and CSRF tokens stay inside the authenticated
/// API boundary.
class AdminDailyReportsScreen extends StatefulWidget {
  final DailyReportsAdminRequest? requestJson;
  final Duration runPollingInterval;
  final Duration codexPollingInterval;

  const AdminDailyReportsScreen({
    super.key,
    this.requestJson,
    this.runPollingInterval = const Duration(seconds: 3),
    this.codexPollingInterval = const Duration(seconds: 2),
  });

  @override
  State<AdminDailyReportsScreen> createState() =>
      _AdminDailyReportsScreenState();
}

class _AdminDailyReportsScreenState extends State<AdminDailyReportsScreen>
    with WidgetsBindingObserver {
  static const _manualRunRequestPrefix =
      'active_daily_report_manual_run_request';
  static const _regenerateRequestPrefix =
      'active_daily_report_regenerate_request';
  static const _resendRequestPrefix = 'active_daily_report_resend_request';
  static const _weekdayOptions = <(String, String)>[
    ('mon', '월'),
    ('tue', '화'),
    ('wed', '수'),
    ('thu', '목'),
    ('fri', '금'),
    ('sat', '토'),
    ('sun', '일'),
  ];
  static const _thresholdFields = <(String, String, bool, double, double?)>[
    ('sales_change_pct', '매출 변화 임계값 (%)', false, 0, 1000),
    ('order_change_pct', '주문 변화 임계값 (%)', false, 0, 1000),
    ('customer_change_pct', '고객 수 변화 임계값 (%)', false, 0, 1000),
    ('avg_ticket_change_pct', '객단가 변화 임계값 (%)', false, 0, 1000),
    ('cancellation_rate_pct', '취소율 임계값 (%)', false, 0, 100),
    ('item_concentration_pct', '상품 편중 임계값 (%)', false, 0, 100),
    ('no_sale_hours', '영업시간 무매출 기준 (시간)', true, 1, 24),
    ('peak_shift_hours', '피크 시간 이동 기준 (시간)', true, 1, 24),
    ('repeated_pattern_days', '반복 패턴 기준 (일)', true, 2, 30),
    ('min_comparison_samples', '비교 최소 표본', true, 1, 30),
    ('min_cancel_count', '최소 취소 건수', true, 1, 1000),
    ('stock_cover_days', '재고 커버 기준 (일)', true, 0, 365),
  ];

  final _settingsFormKey = GlobalKey<FormState>();
  final _random = Random.secure();

  Map<String, dynamic>? _settings;
  int _settingsVersion = 0;
  int _settingsRevision = 0;
  bool _settingsDirty = false;
  bool _initialLoading = true;
  bool _adminAllowed = false;
  bool _appForeground = true;
  bool _overviewLoading = false;
  String? _settingsError;
  String? _runsError;
  String? _detailError;
  String? _auditsError;
  String? _providersError;
  String? _profileJsonError;
  String? _notice;
  bool _noticeIsError = false;
  Map<String, dynamic>? _validation;
  Map<String, dynamic> _secretStatus = {};
  Map<String, dynamic>? _codexAuth;
  Map<String, dynamic>? _codexLogin;
  String? _codexLoginError;
  String? _codexLoginAction;
  String? _testingRecipientId;
  String? _busyAction;
  List<Map<String, dynamic>> _providers = const [];
  List<Map<String, dynamic>> _runs = const [];
  List<Map<String, dynamic>> _audits = const [];
  Map<String, dynamic>? _selectedRun;
  String? _selectedRunId;

  Timer? _runPollingTimer;
  Timer? _codexPollingTimer;
  bool _runsInFlight = false;
  bool _auditsInFlight = false;
  bool _settingsInFlight = false;
  bool _providersInFlight = false;
  bool _detailInFlight = false;
  bool _codexPollInFlight = false;
  int _authorizationGeneration = 0;
  int _detailGeneration = 0;
  int _codexGeneration = 0;
  int _codexPollCount = 0;
  DateTime? _codexPollingDeadline;
  final Map<String, String> _recipientOriginalChatIds = {};
  final Set<String> _rotatedRecipientIds = {};
  final Map<String, String> _recipientLocalKeys = {};
  final Map<String, Map<String, String>> _pendingRequestIds = {};
  String? _ambiguousTelegramTestTarget;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final allowed = context.watch<AppState>().canAccess(UserRole.admin);
    if (allowed == _adminAllowed) return;

    _adminAllowed = allowed;
    _authorizationGeneration += 1;
    if (!allowed) {
      _runPollingTimer?.cancel();
      _runPollingTimer = null;
      _codexPollingTimer?.cancel();
      _codexPollingTimer = null;
      _detailGeneration += 1;
      _codexGeneration += 1;
      _codexLoginAction = null;
      return;
    }

    final generation = _authorizationGeneration;
    unawaited(_refreshOverview(generation: generation));
    unawaited(_restoreCodexLogin(generation));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_adminAllowed) return;
    if (state == AppLifecycleState.resumed) {
      _appForeground = true;
      final generation = _authorizationGeneration;
      unawaited(_refreshOverview(generation: generation));
      unawaited(_restoreCodexLogin(generation));
    } else {
      _appForeground = false;
      _runPollingTimer?.cancel();
      _runPollingTimer = null;
      _codexPollingTimer?.cancel();
      _codexPollingTimer = null;
      _codexGeneration += 1;
      if (_codexLoginAction != null) {
        setState(() => _codexLoginAction = null);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authorizationGeneration += 1;
    _detailGeneration += 1;
    _codexGeneration += 1;
    _runPollingTimer?.cancel();
    _codexPollingTimer?.cancel();
    super.dispose();
  }

  bool _isCurrent(int generation) =>
      mounted && _adminAllowed && generation == _authorizationGeneration;

  Future<Map<String, dynamic>> _request(
    String endpoint, {
    String method = 'GET',
    Map<String, Object?>? params,
    Map<String, dynamic>? body,
  }) async {
    if (!_adminAllowed) {
      throw const ApiException('관리자 권한이 필요합니다.');
    }
    final injected = widget.requestJson;
    if (injected != null) {
      return injected(
        endpoint,
        method: method,
        params: params,
        body: body,
      );
    }

    final appState = context.read<AppState>();
    if (method.toUpperCase() == 'GET') {
      final result = await appState.fetchMapParsed<Map<String, dynamic>>(
        endpoint,
        params: params,
        parser: (json) => json,
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      return result.data;
    }
    if (method.toUpperCase() == 'POST' &&
        endpoint == '/api/admin/daily-reports/tests/telegram') {
      final configuredTimeout =
          _intValue(_settings?['request_timeout_seconds']) ?? 45;
      final perRequestSeconds = configuredTimeout < 1
          ? 1
          : configuredTimeout > 120
              ? 120
              : configuredTimeout;
      // Username resolution is optional; when used, it adds another Telegram
      // request before the endpoint's getMe + sendMessage sequence.
      return appState.postJsonWithTimeout(
        endpoint,
        body: body,
        method: method,
        timeout: Duration(seconds: perRequestSeconds * 3 + 15),
      );
    }
    return appState.postJson(endpoint, body: body, method: method);
  }

  Future<void> _refreshOverview({
    required int generation,
    bool includeSettings = true,
  }) async {
    if (!_isCurrent(generation)) return;
    setState(() => _overviewLoading = true);
    try {
      if (includeSettings && !_settingsDirty) {
        await _loadSettings(generation);
      }
      await Future.wait<void>([
        _loadRuns(generation),
        _loadAudits(generation),
        _loadProviders(generation),
      ]);
    } finally {
      if (_isCurrent(generation)) {
        setState(() {
          _overviewLoading = false;
          _initialLoading = false;
        });
      }
    }
  }

  Future<void> _loadSettings(int generation) async {
    if (_settingsInFlight || !_isCurrent(generation)) return;
    _settingsInFlight = true;
    try {
      final response = await _request('/api/admin/daily-reports/settings');
      if (!_isCurrent(generation)) return;
      final settings = _asMap(response['settings']);
      setState(() {
        _settings = settings;
        _settingsVersion = _intValue(response['version']) ?? 0;
        _secretStatus = _asMap(response['secret_status']);
        _settingsDirty = false;
        _settingsError = null;
        _profileJsonError = null;
        _settingsRevision += 1;
        _recipientOriginalChatIds
          ..clear()
          ..addEntries(_recipients(settings).map(
            (recipient) => MapEntry(
              _string(recipient['recipient_id']),
              _string(recipient['chat_id']),
            ),
          ));
        _recipientLocalKeys
          ..clear()
          ..addEntries(_recipients(settings).map(
            (recipient) => MapEntry(
              _string(recipient['recipient_id']),
              _newUuid(),
            ),
          ));
        _rotatedRecipientIds.clear();
      });
    } catch (error) {
      if (!_isCurrent(generation)) return;
      setState(() => _settingsError =
          _safeRequestError(error, '일일보고서 설정을 불러오지 못했습니다.'));
    } finally {
      _settingsInFlight = false;
    }
  }

  Future<void> _loadRuns(int generation) async {
    if (_runsInFlight || !_isCurrent(generation)) return;
    _runsInFlight = true;
    final previouslySelectedWasActive =
        _selectedRun != null && _isRunActive(_selectedRun!);
    try {
      final response = await _request(
        '/api/admin/daily-reports/runs',
        params: const {'limit': 30},
      );
      if (!_isCurrent(generation)) return;
      final runs = _mapList(response['runs']);
      Map<String, dynamic>? selectedSummary;
      for (final run in runs) {
        if (_runId(run) == _selectedRunId) {
          selectedSummary = run;
          break;
        }
      }
      setState(() {
        _runs = runs;
        _runsError = null;
        _detailError = null;
      });
      _syncRunPolling();
      if (selectedSummary != null &&
          (_isRunActive(selectedSummary) || previouslySelectedWasActive)) {
        unawaited(_loadRunDetail(_selectedRunId!, generation: generation));
      }
    } catch (error) {
      if (!_isCurrent(generation)) return;
      setState(() => _runsError =
          _safeRequestError(error, '실행 이력을 불러오지 못했습니다.'));
    } finally {
      _runsInFlight = false;
    }
  }

  Future<void> _loadAudits(int generation) async {
    if (_auditsInFlight || !_isCurrent(generation)) return;
    _auditsInFlight = true;
    try {
      final response = await _request(
        '/api/admin/daily-reports/audits',
        params: const {'limit': 30},
      );
      if (!_isCurrent(generation)) return;
      setState(() {
        _audits = _mapList(response['audits']);
        _auditsError = null;
      });
    } catch (error) {
      if (!_isCurrent(generation)) return;
      setState(() => _auditsError =
          _safeRequestError(error, '감사 로그를 불러오지 못했습니다.'));
    } finally {
      _auditsInFlight = false;
    }
  }

  Future<void> _loadProviders(int generation) async {
    if (_providersInFlight || !_isCurrent(generation)) return;
    _providersInFlight = true;
    try {
      final response =
          await _request('/api/admin/daily-reports/providers');
      if (!_isCurrent(generation)) return;
      setState(() {
        _providers = _mapList(response['providers']);
        _codexAuth = _asMap(response['codex_auth']);
        _providersError = null;
      });
    } catch (error) {
      if (!_isCurrent(generation)) return;
      setState(() => _providersError =
          _safeRequestError(error, 'LLM 프로바이더 상태를 불러오지 못했습니다.'));
    } finally {
      _providersInFlight = false;
    }
  }

  void _syncRunPolling() {
    if (!_adminAllowed || !_appForeground || !_runs.any(_isRunActive)) {
      _runPollingTimer?.cancel();
      _runPollingTimer = null;
      return;
    }
    _runPollingTimer ??= Timer.periodic(widget.runPollingInterval, (_) {
      unawaited(_loadRuns(_authorizationGeneration));
    });
  }

  Future<void> _loadRunDetail(
    String id, {
    required int generation,
    bool select = false,
  }) async {
    if (!_isCurrent(generation)) return;
    if (_detailInFlight && id == _selectedRunId) return;
    final request = ++_detailGeneration;
    if (select) {
      setState(() {
        _selectedRunId = id;
        _selectedRun = null;
        _detailError = null;
      });
    }
    _detailInFlight = true;
    try {
      final response = await _request(
        '/api/admin/daily-reports/runs/${Uri.encodeComponent(id)}',
      );
      if (!_isCurrent(generation) || request != _detailGeneration) return;
      final run = _asMap(response['run']);
      if (run.isEmpty) throw const FormatException('실행 상세 응답이 비어 있습니다.');
      setState(() {
        _selectedRunId = id;
        _selectedRun = run;
        _detailError = null;
      });
    } catch (error) {
      if (!_isCurrent(generation) || request != _detailGeneration) return;
      setState(() => _detailError =
          _safeRequestError(error, '실행 상세를 불러오지 못했습니다.'));
    } finally {
      if (request == _detailGeneration) _detailInFlight = false;
    }
  }

  void _updateSetting(String key, Object? value) {
    final current = _settings;
    if (current == null) return;
    setState(() {
      _settings = {...current, key: value};
      _settingsDirty = true;
      _validation = null;
      _notice = null;
    });
  }

  void _updateNestedSetting(String parent, String key, Object? value) {
    final current = _settings;
    if (current == null) return;
    final nested = _asMap(current[parent]);
    _updateSetting(parent, {...nested, key: value});
  }

  void _setNotice(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _notice = text;
      _noticeIsError = error;
    });
  }

  Future<void> _runBusy(
    String action,
    String fallback,
    Future<void> Function() operation,
  ) async {
    if (_busyAction != null || !_adminAllowed) return;
    setState(() {
      _busyAction = action;
      _notice = null;
    });
    try {
      await operation();
    } catch (error) {
      _setNotice(_safeRequestError(error, fallback), error: true);
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  List<String> _localValidationIssues() {
    final settings = _settings;
    if (settings == null) return const ['설정을 먼저 불러오세요.'];
    final issues = <String>[];
    for (final field in const [
      ('schedule_time', '실행 시각'),
      ('previous_day_collection_time', '전일 마감 수집 시각'),
    ]) {
      if (!_isTime(_string(settings[field.$1]))) {
        issues.add('${field.$2}을 HH:MM 형식으로 입력하세요.');
      }
    }
    if (_string(settings['timezone']).trim().isEmpty) {
      issues.add('시간대를 입력하세요.');
    }
    final defaultProfile = _defaultProfile();
    if (!_isTime(_string(defaultProfile['open_time'])) ||
        !_isTime(_string(defaultProfile['close_time']))) {
      issues.add('매장 영업 시각을 HH:MM 형식으로 입력하세요.');
    }
    final weekdays = _stringList(settings['weekdays']);
    if (weekdays.isEmpty) issues.add('영업일을 하나 이상 선택하세요.');
    final recipients = _recipients(settings);
    if (recipients.length > 100) {
      issues.add('Telegram 수신자는 최대 100명까지 등록할 수 있습니다.');
    }
    final normalizedIds = <String>{};
    for (var index = 0; index < recipients.length; index += 1) {
      final recipient = recipients[index];
      final name = _string(recipient['label']).trim();
      final chatId = _normalizeChatId(_string(recipient['chat_id']));
      if (name.isEmpty) issues.add('${index + 1}번 Telegram 수신자 이름을 입력하세요.');
      if (chatId == null) {
        issues.add('${index + 1}번 Telegram Chat ID를 확인하세요.');
      } else if (!normalizedIds.add(chatId)) {
        issues.add('${index + 1}번 Telegram Chat ID가 중복되었습니다.');
      }
    }
    if (settings['telegram_enabled'] == true &&
        !recipients.any((recipient) => recipient['enabled'] == true)) {
      issues.add('Telegram 전송을 켜려면 활성 수신자가 하나 이상 필요합니다.');
    }
    if (settings['llm_enabled'] == true &&
        _stringList(settings['llm_targets']).isEmpty) {
      issues.add('LLM 분석 항목을 하나 이상 선택하세요.');
    }
    if (_stringList(settings['collection_sources']).isEmpty) {
      issues.add('수집 소스를 하나 이상 입력하세요.');
    }
    if (_profileJsonError != null) issues.add('매장별 설정 JSON을 확인하세요.');
    return issues;
  }

  bool _validateForm() {
    final formValid = _settingsFormKey.currentState?.validate() ?? false;
    final issues = _localValidationIssues();
    if (!formValid || issues.isNotEmpty) {
      _setNotice(
        issues.isNotEmpty ? issues.join(' ') : '입력값을 확인하세요.',
        error: true,
      );
      return false;
    }
    return true;
  }

  Future<void> _validateSettings() async {
    if (!_validateForm() || _settings == null) return;
    final settings = Map<String, dynamic>.from(_settings!);
    await _runBusy('validate', '설정 검증 요청을 완료하지 못했습니다.', () async {
      final response = await _request(
        '/api/admin/daily-reports/settings/validate',
        method: 'POST',
        body: settings,
      );
      if (!mounted) return;
      setState(() => _validation = response);
      final valid = response['valid'] == true;
      _setNotice(
        valid ? '설정 검증을 통과했습니다.' : '설정 오류를 확인하세요.',
        error: !valid,
      );
    });
  }

  Future<void> _saveSettings() async {
    if (!_validateForm() || _settings == null) return;
    final settings = Map<String, dynamic>.from(_settings!);
    await _runBusy('save', '설정을 저장하지 못했습니다.', () async {
      final response = await _request(
        '/api/admin/daily-reports/settings',
        method: 'PUT',
        body: {
          'expected_version': _settingsVersion,
          'settings': settings,
        },
      );
      if (!mounted) return;
      _acceptSettingsResponse(response);
      _setNotice('일일보고서 설정을 저장했습니다.');
      await _refreshOverview(
        generation: _authorizationGeneration,
        includeSettings: false,
      );
    });
  }

  void _acceptSettingsResponse(Map<String, dynamic> response) {
    final settings = _asMap(response['settings']);
    setState(() {
      _settings = settings;
      _settingsVersion = _intValue(response['version']) ?? _settingsVersion;
      _secretStatus = _asMap(response['secret_status']);
      _settingsDirty = false;
      _validation = null;
      _profileJsonError = null;
      _settingsRevision += 1;
      _recipientOriginalChatIds
        ..clear()
        ..addEntries(_recipients(settings).map(
          (recipient) => MapEntry(
            _string(recipient['recipient_id']),
            _string(recipient['chat_id']),
          ),
        ));
      _recipientLocalKeys
        ..clear()
        ..addEntries(_recipients(settings).map(
          (recipient) => MapEntry(
            _string(recipient['recipient_id']),
            _newUuid(),
          ),
        ));
      _rotatedRecipientIds.clear();
    });
  }

  Future<void> _testTelegramGeneral() async {
    if (_settingsDirty) {
      _setNotice('설정을 저장한 후 연결 테스트를 실행하세요.', error: true);
      return;
    }
    final enabled =
        _recipients(_settings ?? {}).where((item) => item['enabled'] == true);
    if (enabled.length != 1) {
      _setNotice(
        '활성 수신자가 여러 명이면 각 수신자 행의 테스트 버튼을 사용하세요.',
        error: true,
      );
      return;
    }
    await _testTelegramRecipient(enabled.single);
  }

  Future<void> _testTelegramRecipient(
    Map<String, dynamic> recipient,
  ) async {
    if (_settingsDirty) {
      _setNotice('설정을 저장한 후 Telegram 테스트를 실행하세요.', error: true);
      return;
    }
    final id = _string(recipient['recipient_id']);
    if (id.isEmpty) return;
    final intentKey =
        '$id|$_settingsVersion|${_string(recipient['chat_id']).trim()}';
    if (_ambiguousTelegramTestTarget == intentKey) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('테스트 전송 결과 확인'),
          content: const Text(
            '응답을 받지 못해 서버가 테스트 메시지를 이미 전달했을 수 있습니다. '
            '먼저 Telegram 대화를 확인하세요. 확인하지 않고 다시 보내면 중복 메시지가 생길 수 있습니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('대화를 확인하고 다시 테스트'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    setState(() => _testingRecipientId = id);
    await _runBusy('telegram-$id', 'Telegram 연결 테스트에 실패했습니다.', () async {
      try {
        final response = await _request(
          '/api/admin/daily-reports/tests/telegram',
          method: 'POST',
          body: {
            'recipient_id': id,
            'expected_version': _settingsVersion,
          },
        );
        if (!mounted) return;
        setState(() => _ambiguousTelegramTestTarget = null);
        final ok = response['ok'] == true;
        final latency = _intValue(response['latency_ms']);
        final latencySuffix = latency == null ? '' : ' (${latency}ms)';
        _setNotice(
          ok
              ? 'Telegram 연결을 확인했습니다$latencySuffix.'
              : 'Telegram 테스트에 실패했습니다. 연결 설정을 확인하세요.',
          error: !ok,
        );
      } catch (error) {
        if (_isAmbiguousTelegramTestFailure(error)) {
          if (mounted) {
            setState(() => _ambiguousTelegramTestTarget = intentKey);
            _setNotice(
              '응답을 확인하지 못했습니다. 서버가 테스트 메시지를 전달했을 수 있으니 Telegram 대화를 확인한 뒤 다시 시도하세요.',
              error: true,
            );
          }
          return;
        }
        if (mounted) setState(() => _ambiguousTelegramTestTarget = null);
        rethrow;
      }
    });
    if (mounted) setState(() => _testingRecipientId = null);
  }

  bool _isAmbiguousTelegramTestFailure(Object error) {
    if (error is! ApiException) return true;
    return error.isTransportError ||
        error.statusCode == null ||
        error.statusCode! >= 500;
  }

  Future<void> _testProvider(String provider) async {
    if (_settingsDirty) {
      _setNotice('설정을 저장한 후 연결 테스트를 실행하세요.', error: true);
      return;
    }
    final endpoint = provider == 'opencode'
        ? '/api/admin/daily-reports/tests/opencode'
        : '/api/admin/daily-reports/tests/codex';
    final label = provider == 'opencode' ? 'OpenCode' : 'Codex';
    await _runBusy('test-$provider', '$label 연결 테스트를 완료하지 못했습니다.',
        () async {
      final response = await _request(endpoint, method: 'POST');
      final ok = response['ok'] == true;
      final latency = _intValue(response['latency_ms']);
      _setNotice(
        ok
            ? '$label 연결을 확인했습니다${latency == null ? '' : ' (${latency}ms)'}.'
            : '$label 테스트에 실패했습니다. 인증 및 프로바이더 설정을 확인하세요.',
        error: !ok,
      );
    });
  }

  Future<void> _startCodexLogin(String method) async {
    if (_codexLoginAction != null || !_adminAllowed) return;
    _codexPollingTimer?.cancel();
    _codexPollingTimer = null;
    final generation = ++_codexGeneration;
    setState(() {
      _codexLoginAction = method;
      _codexLoginError = null;
    });
    try {
      final response = await _request(
        '/api/admin/daily-reports/auth/codex/login',
        method: 'POST',
        body: {'method': method},
      );
      if (!_isCurrent(_authorizationGeneration) ||
          generation != _codexGeneration) {
        return;
      }
      _acceptCodexLogin(response);
      _setNotice(
        'Codex 로그인 흐름을 시작했습니다. URL을 복사해 브라우저에서 진행하세요.',
      );
    } catch (error) {
      if (!_isCurrent(_authorizationGeneration) ||
          generation != _codexGeneration) {
        return;
      }
      setState(() => _codexLoginError =
          _safeRequestError(error, 'Codex 로그인을 시작하지 못했습니다.'));
    } finally {
      if (mounted && generation == _codexGeneration) {
        setState(() => _codexLoginAction = null);
        _scheduleCodexPoll();
      }
    }
  }

  Future<void> _restoreCodexLogin(int authorizationGeneration) async {
    if (!_isCurrent(authorizationGeneration)) return;
    _codexPollingTimer?.cancel();
    _codexPollingTimer = null;
    final generation = ++_codexGeneration;
    try {
      final response =
          await _request('/api/admin/daily-reports/auth/codex/login');
      if (!_isCurrent(authorizationGeneration) ||
          generation != _codexGeneration) {
        return;
      }
      _acceptCodexLogin(response);
      setState(() => _codexLoginError = null);
    } catch (error) {
      if (!_isCurrent(authorizationGeneration) ||
          generation != _codexGeneration) {
        return;
      }
      setState(() => _codexLoginError =
          _safeRequestError(error, '진행 중인 Codex 로그인을 복원하지 못했습니다.'));
    }
  }

  void _acceptCodexLogin(Map<String, dynamic> response) {
    setState(() {
      _codexLogin = Map<String, dynamic>.from(response);
      _codexPollCount = 0;
      final seconds = _intValue(response['expires_in_seconds']) ?? 600;
      _codexPollingDeadline = DateTime.now().add(
        Duration(seconds: seconds.clamp(0, 1800).toInt() + 10),
      );
      _codexLoginError = null;
    });
    _scheduleCodexPoll();
  }

  void _scheduleCodexPoll() {
    _codexPollingTimer?.cancel();
    _codexPollingTimer = null;
    final login = _codexLogin;
    final flowId = _string(login?['flow_id']);
    if (!_adminAllowed ||
        login?['status'] != 'pending' ||
        flowId.isEmpty ||
        _codexLoginAction != null) {
      return;
    }
    if (_codexPollCount >= 905 ||
        (_codexPollingDeadline != null &&
            DateTime.now().isAfter(_codexPollingDeadline!))) {
      setState(() {
        _codexLoginError =
            '자동 상태 확인을 중지했습니다. 로그인을 취소한 뒤 다시 시도하세요.';
      });
      return;
    }
    final generation = _codexGeneration;
    final authorizationGeneration = _authorizationGeneration;
    _codexPollingTimer = Timer(widget.codexPollingInterval, () {
      unawaited(_pollCodexLogin(
        flowId,
        generation: generation,
        authorizationGeneration: authorizationGeneration,
      ));
    });
  }

  Future<void> _pollCodexLogin(
    String flowId, {
    required int generation,
    required int authorizationGeneration,
  }) async {
    if (_codexPollInFlight ||
        !_isCurrent(authorizationGeneration) ||
        generation != _codexGeneration ||
        _string(_codexLogin?['flow_id']) != flowId) {
      return;
    }
    if (_codexPollCount >= 905 ||
        (_codexPollingDeadline != null &&
            DateTime.now().isAfter(_codexPollingDeadline!))) {
      _setNotice('Codex 로그인 상태 확인 시간이 끝났습니다.', error: true);
      return;
    }
    _codexPollInFlight = true;
    _codexPollCount += 1;
    try {
      final response = await _request(
        '/api/admin/daily-reports/auth/codex/login/${Uri.encodeComponent(flowId)}',
      );
      if (!_isCurrent(authorizationGeneration) ||
          generation != _codexGeneration ||
          _string(_codexLogin?['flow_id']) != flowId) {
        return;
      }
      setState(() {
        _codexLogin = response;
        _codexLoginError = null;
      });
      if (response['status'] == 'pending' &&
          _string(response['flow_id']) == flowId) {
        _scheduleCodexPoll();
      } else {
        unawaited(_loadProviders(authorizationGeneration));
      }
    } catch (error) {
      if (!_isCurrent(authorizationGeneration) ||
          generation != _codexGeneration ||
          _string(_codexLogin?['flow_id']) != flowId) {
        return;
      }
      setState(() => _codexLoginError =
          _safeRequestError(error, 'Codex 로그인 상태를 확인하지 못했습니다.'));
      _scheduleCodexPoll();
    } finally {
      _codexPollInFlight = false;
    }
  }

  Future<void> _cancelCodexLogin() async {
    final flowId = _string(_codexLogin?['flow_id']);
    if (flowId.isEmpty ||
        _codexLogin?['status'] != 'pending' ||
        _codexLoginAction != null) {
      return;
    }
    _codexPollingTimer?.cancel();
    _codexPollingTimer = null;
    final generation = ++_codexGeneration;
    setState(() {
      _codexLoginAction = 'cancel';
      _codexLoginError = null;
    });
    try {
      final response = await _request(
        '/api/admin/daily-reports/auth/codex/login/${Uri.encodeComponent(flowId)}/cancel',
        method: 'POST',
      );
      if (!_isCurrent(_authorizationGeneration) ||
          generation != _codexGeneration) {
        return;
      }
      setState(() => _codexLogin = response);
      _setNotice(
        response['status'] == 'cancelled' ||
                response['status'] == 'canceled'
            ? 'Codex 로그인을 취소했습니다.'
            : 'Codex 로그인 상태를 확인했습니다.',
      );
      unawaited(_loadProviders(_authorizationGeneration));
    } catch (error) {
      if (!_isCurrent(_authorizationGeneration) ||
          generation != _codexGeneration) {
        return;
      }
      setState(() => _codexLoginError =
          _safeRequestError(error, 'Codex 로그인을 취소하지 못했습니다.'));
    } finally {
      if (mounted && generation == _codexGeneration) {
        setState(() => _codexLoginAction = null);
        _scheduleCodexPoll();
      }
    }
  }

  Future<void> _logoutCodex() async {
    await _runBusy('codex-logout', 'Codex 로그아웃에 실패했습니다.', () async {
      final response = await _request(
        '/api/admin/daily-reports/auth/codex/logout',
        method: 'POST',
      );
      final ok = response['ok'] == true;
      _setNotice(
        ok ? 'Codex 로그아웃을 완료했습니다.' : 'Codex 로그아웃에 실패했습니다.',
        error: !ok,
      );
      await _loadProviders(_authorizationGeneration);
    });
  }

  Future<void> _copyCodexUrl() async {
    final login = _codexLogin;
    if (login == null) return;
    final method = _string(login['method']);
    final url = method == 'device_code'
        ? _string(login['verification_url']).isNotEmpty
            ? _string(login['verification_url'])
            : _string(login['auth_url'])
        : _string(login['auth_url']).isNotEmpty
            ? _string(login['auth_url'])
            : _string(login['verification_url']);
    if (url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    _setNotice('Codex 로그인 URL을 클립보드에 복사했습니다.');
  }

  Future<void> _startManualRun() async {
    final targetDate = _manualTargetDate;
    if (targetDate == null) {
      _setNotice('보고서 대상 날짜를 선택하세요.', error: true);
      return;
    }
    const reason = 'Flutter 관리자 수동 실행';
    final fingerprint = jsonEncode(
      <String, Object?>{'target_date': targetDate, 'reason': reason},
    );
    await _runBusy('run', '수동 실행을 요청하지 못했습니다.', () async {
      final requestId = await _requestIdForIntent(
        prefix: _manualRunRequestPrefix,
        fingerprint: fingerprint,
      );
      final response = await _request(
        '/api/admin/daily-reports/runs',
        method: 'POST',
        body: {
          'target_date': targetDate,
          'request_id': requestId,
          'reason': reason,
        },
      );
      await _completeRequestIntent(
        prefix: _manualRunRequestPrefix,
        fingerprint: fingerprint,
      );
      final id = _runId(_asMap(response['run']));
      _setNotice('$targetDate 보고서 실행을 요청했습니다.');
      await _refreshOverview(
        generation: _authorizationGeneration,
        includeSettings: !_settingsDirty,
      );
      if (id.isNotEmpty) {
        await _loadRunDetail(
          id,
          generation: _authorizationGeneration,
          select: true,
        );
      }
    });
  }

  String? get _manualTargetDate {
    final date = _manualDate;
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  DateTime _manualDate = DateTime.now();

  Future<void> _chooseManualDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _manualDate.isAfter(now) ? now : _manualDate,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _manualDate = picked);
  }

  Future<void> _cancelRun(Map<String, dynamic> run) async {
    final id = _runId(run);
    if (id.isEmpty) return;
    await _runBusy('cancel', '실행 취소를 요청하지 못했습니다.', () async {
      final response = await _request(
        '/api/admin/daily-reports/runs/${Uri.encodeComponent(id)}/cancel',
        method: 'POST',
      );
      if (_asMap(response['run']).isNotEmpty) {
        setState(() => _selectedRun = _asMap(response['run']));
      }
      await _refreshOverview(
        generation: _authorizationGeneration,
        includeSettings: !_settingsDirty,
      );
      await _loadRunDetail(
        id,
        generation: _authorizationGeneration,
      );
      _setNotice('실행 취소를 요청했습니다.');
    });
  }

  Future<void> _regenerateReport(Map<String, dynamic> run) async {
    final reportId = _string(run['report_id']);
    if (reportId.isEmpty) return;
    const reason = 'Flutter 관리자 재생성';
    final fingerprint =
        jsonEncode(<String, Object?>{'report_id': reportId, 'reason': reason});
    await _runBusy('regenerate', '보고서 재생성을 요청하지 못했습니다.', () async {
      final requestId = await _requestIdForIntent(
        prefix: _regenerateRequestPrefix,
        fingerprint: fingerprint,
      );
      final response = await _request(
        '/api/admin/daily-reports/reports/${Uri.encodeComponent(reportId)}/regenerate',
        method: 'POST',
        body: {
          'request_id': requestId,
          'reason': reason,
        },
      );
      await _completeRequestIntent(
        prefix: _regenerateRequestPrefix,
        fingerprint: fingerprint,
      );
      _setNotice('보고서 재생성을 요청했습니다.');
      await _refreshOverview(
        generation: _authorizationGeneration,
        includeSettings: !_settingsDirty,
      );
      final id = _runId(_asMap(response['run']));
      if (id.isNotEmpty) {
        await _loadRunDetail(
          id,
          generation: _authorizationGeneration,
          select: true,
        );
      }
    });
  }

  Future<void> _openResendDialog(Map<String, dynamic> run) async {
    final settings = _settings;
    if (settings == null || _settingsDirty || _recipientIssues().isNotEmpty) {
      _setNotice('수신자 설정을 저장하고 오류를 해결한 뒤 재전송하세요.', error: true);
      return;
    }
    final activeRecipients = _recipients(settings)
        .where((recipient) => recipient['enabled'] == true)
        .toList(growable: false);
    if (activeRecipients.isEmpty) {
      _setNotice('활성 Telegram 수신자가 없습니다.', error: true);
      return;
    }
    final deliveries = _mapList(run['deliveries']);
    final failedIds = deliveries
        .where((delivery) =>
            delivery['status'] == 'failed' ||
            delivery['status'] == 'partial_failed')
        .map((delivery) => _string(delivery['recipient_id']))
        .where((id) => id.isNotEmpty)
        .toSet();
    final selected = <String>{
      for (final recipient in activeRecipients)
        if (failedIds.contains(_string(recipient['recipient_id'])))
          _string(recipient['recipient_id']),
    };
    var confirmDuplicate = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final duplicateRisk = deliveries.any((delivery) =>
              selected.contains(_string(delivery['recipient_id'])) &&
              const {'sent', 'partial_failed', 'ambiguous'}
                  .contains(delivery['status']));
          return AlertDialog(
            title: const Text('보고서 선택 재전송'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_string(run['target_date'])} · '
                      '${_reportTitle(run)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    for (final recipient in activeRecipients)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: selected
                            .contains(_string(recipient['recipient_id'])),
                        title: Text(_string(recipient['label'])),
                        subtitle: Text(
                          _maskChatId(_string(recipient['chat_id'])),
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            final id = _string(recipient['recipient_id']);
                            if (value == true) {
                              selected.add(id);
                            } else {
                              selected.remove(id);
                            }
                          });
                        },
                      ),
                    if (duplicateRisk)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: confirmDuplicate,
                        title: const Text(
                          '이미 전달됐을 수 있어 중복 수신이 발생할 수 있음을 확인했습니다.',
                        ),
                        onChanged: (value) => setDialogState(
                          () => confirmDuplicate = value == true,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('닫기'),
              ),
              FilledButton(
                onPressed: selected.isEmpty ||
                        (duplicateRisk && !confirmDuplicate)
                    ? null
                    : () {
                        final ids = selected.toList(growable: false);
                        Navigator.of(dialogContext).pop();
                        unawaited(_submitResend(
                          run,
                          ids,
                          confirmDuplicate,
                        ));
                      },
                child: Text('재전송 (${selected.length}명)'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _submitResend(
    Map<String, dynamic> run,
    List<String> recipientIds,
    bool confirmDuplicate,
  ) async {
    final reportId = _string(run['report_id']);
    if (reportId.isEmpty || _settingsDirty) return;
    const reason = 'Flutter 관리자 확인 후 재전송';
    final stableRecipientIds = recipientIds.toList()..sort();
    final fingerprint = jsonEncode(<String, Object?>{
      'report_id': reportId,
      'expected_settings_version': _settingsVersion,
      'recipient_ids': stableRecipientIds,
      'mode': 'full_report',
      'reason': reason,
      'confirm_possible_duplicate': confirmDuplicate,
    });
    await _runBusy('resend', '보고서 재전송을 요청하지 못했습니다.', () async {
      final requestId = await _requestIdForIntent(
        prefix: _resendRequestPrefix,
        fingerprint: fingerprint,
      );
      final response = await _request(
        '/api/admin/daily-reports/reports/${Uri.encodeComponent(reportId)}/resend',
        method: 'POST',
        body: {
          'request_id': requestId,
          'expected_settings_version': _settingsVersion,
          'recipient_ids': stableRecipientIds,
          'mode': 'full_report',
          'reason': reason,
          'confirm_possible_duplicate': confirmDuplicate,
        },
      );
      await _completeRequestIntent(
        prefix: _resendRequestPrefix,
        fingerprint: fingerprint,
      );
      _setNotice('${recipientIds.length}명에게 전체 보고서 재전송을 요청했습니다.');
      await _refreshOverview(
        generation: _authorizationGeneration,
        includeSettings: false,
      );
      final id = _runId(_asMap(response['run']));
      if (id.isNotEmpty) {
        await _loadRunDetail(
          id,
          generation: _authorizationGeneration,
          select: true,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AccessGate(
      minimumRole: UserRole.admin,
      child: AppScreen(
        title: '일일보고서 관리',
        subtitle: '스케줄, 연결, 실행과 보고서 전송을 관리합니다.',
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _overviewLoading
                ? null
                : () => unawaited(_refreshOverview(
                      generation: _authorizationGeneration,
                    )),
            icon: const Icon(Icons.refresh),
          ),
        ],
        body: _initialLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () => _refreshOverview(
                  generation: _authorizationGeneration,
                ),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(AppSpacing.page),
                  children: [
                    if (_notice != null) _buildNotice(),
                    _buildSettingsPanel(),
                    _buildConnectionsPanel(),
                    _buildManualRunPanel(),
                    _buildRunsPanel(),
                    _buildSelectedRunPanel(),
                    _buildAuditsPanel(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildNotice() {
    final color = _noticeIsError ? AppColors.danger : AppColors.success;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _noticeIsError ? Icons.error_outline : Icons.check_circle_outline,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(_notice!, style: TextStyle(color: color))),
        ],
      ),
    );
  }

  Widget _buildSettingsPanel() {
    final settings = _settings;
    if (settings == null) {
      return Panel(
        title: '보고서 운영 설정',
        subtitle: '스케줄, 수집, 생성, 전송 정책',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_settingsError ?? '설정을 불러오는 중입니다.'),
            if (_settingsError != null)
              TextButton(
                onPressed: () => unawaited(
                  _loadSettings(_authorizationGeneration),
                ),
                child: const Text('다시 불러오기'),
              ),
          ],
        ),
      );
    }
    return Panel(
      title: '보고서 운영 설정',
      subtitle: '버전 $_settingsVersion${_settingsDirty ? ' · 저장되지 않은 변경' : ''}',
      child: Form(
        key: _settingsFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _settingsSection(
              '자동화',
              [
                _switchField('일일보고서 자동 실행', 'enabled'),
                _switchField('POS 자동 동기화', 'auto_sync_enabled'),
                _switchField('Telegram 보고서 전송', 'telegram_enabled'),
                _switchField('LLM 보고서 생성', 'llm_enabled'),
                _timeField('실행 시각', 'schedule_time'),
                _timeField('전일 마감 수집 시각', 'previous_day_collection_time'),
                _textField('시간대 (IANA)', 'timezone'),
                _numberField(
                  'POS 수집 주기 (분)',
                  'collection_interval_minutes',
                  min: 1,
                  max: 1440,
                ),
                _weekdayField(),
              ],
            ),
            _settingsSection(
              '매장 운영 기본값',
              [
                _profileTimeField('영업 시작', 'open_time'),
                _profileTimeField('영업 종료', 'close_time'),
              ],
            ),
            _settingsSection(
              '템플릿과 수집 범위',
              [
                _textField('제목 템플릿', 'title_template'),
                _textField(
                  '메시지 템플릿',
                  'message_template',
                  maxLines: 4,
                ),
                _listField('보고서 섹션', 'sections'),
                _listField('수집 소스', 'collection_sources'),
                _listField('LLM 분석 항목', 'llm_targets'),
                _dropdownField(
                  '상세 수준',
                  'detail_level',
                  const {
                    'brief': '간단',
                    'standard': '표준',
                    'detailed': '상세',
                  },
                ),
                _numberField('조회 일수', 'lookback_days', min: 1, max: 90),
                _numberField(
                  '최대 입력 레코드',
                  'max_input_records',
                  min: 10,
                  max: 5000,
                ),
              ],
            ),
            _settingsSection(
              '재시도 및 전송 정책',
              [
                _numberField('재시도 횟수', 'retry_count', min: 0, max: 9),
                _numberField(
                  '재시도 간격 (초)',
                  'retry_interval_seconds',
                  min: 1,
                  max: 300,
                ),
                _numberField(
                  '요청 제한시간 (초)',
                  'request_timeout_seconds',
                  min: 1,
                  max: 120,
                ),
                _numberField(
                  '메시지 분할 길이',
                  'message_split_limit',
                  min: 500,
                  max: 4000,
                ),
                _switchField('실패 알림', 'failure_notifications_enabled'),
                _switchField('부분 실패 보고', 'partial_failure_reporting'),
                _switchField('데이터가 없어도 전송', 'send_when_no_data'),
              ],
            ),
            _settingsSection(
              '매장 운영 판단',
              [
                _switchField('능동 분석 활성화', 'active_analysis_enabled'),
                _listField('비교 기간', 'comparison_periods'),
                _dropdownField(
                  '최소 이상 심각도',
                  'alert_min_severity',
                  const {'low': '낮음 이상', 'medium': '중간 이상', 'high': '높음만'},
                ),
                _dropdownField(
                  '최소 판단 신뢰도',
                  'alert_min_confidence',
                  const {'low': '낮음 이상', 'medium': '중간 이상', 'high': '높음만'},
                ),
                for (final field in _thresholdFields)
                  _thresholdField(field.$1, field.$2,
                      integer: field.$3, min: field.$4, max: field.$5),
                _profilesJsonField(),
              ],
            ),
            _settingsSection(
              'LLM 판단 정책',
              [
                _providerField(),
                _textField('모델 override', 'llm_model'),
                _dropdownField(
                  'Codex reasoning effort',
                  'llm_reasoning_effort',
                  const {
                    'none': 'none',
                    'minimal': 'minimal',
                    'low': 'low',
                    'medium': 'medium',
                    'high': 'high',
                  },
                ),
                _numberField(
                  'LLM 최대 출력 토큰',
                  'llm_max_output_tokens',
                  min: 256,
                  max: 4000,
                ),
                _textField(
                  'LLM 시스템 프롬프트',
                  'llm_system_prompt',
                  maxLines: 6,
                  maxLength: 6000,
                ),
              ],
            ),
            _buildRecipientsEditor(),
            if (_settingsError != null) ...[
              const SizedBox(height: 8),
              _errorText(_settingsError!),
            ],
            if (_validation != null) _buildValidationResult(_validation!),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busyAction == null ? _validateSettings : null,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('설정 검증'),
                ),
                FilledButton.icon(
                  onPressed: _busyAction == null ? _saveSettings : null,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_busyAction == 'save' ? '저장 중…' : '설정 저장'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsSection(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...children.expand((child) => [child, const SizedBox(height: 8)]),
        ],
      ),
    );
  }

  Widget _switchField(String label, String key) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(label),
      value: _settings?[key] == true,
      onChanged: (value) => _updateSetting(key, value),
    );
  }

  Widget _weekdayField() {
    final selected = _stringList(_settings?['weekdays']).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('영업일'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final (value, label) in _weekdayOptions)
              FilterChip(
                label: Text(label),
                selected: selected.contains(value),
                onSelected: (enabled) {
                  final next = Set<String>.from(selected);
                  if (enabled) {
                    next.add(value);
                  } else if (next.length > 1) {
                    next.remove(value);
                  }
                  _updateSetting(
                    'weekdays',
                    [
                      for (final option in _weekdayOptions)
                        if (next.contains(option.$1)) option.$1,
                    ],
                  );
                  _updateDefaultProfile({});
                },
              ),
          ],
        ),
        const Text(
          '영업일은 POS 자동 수집과 보고서 자동 실행에 함께 적용됩니다.',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _timeField(String label, String key) {
    return TextFormField(
      key: ValueKey('settings-$key-$_settingsRevision'),
      initialValue: _string(_settings?[key]),
      keyboardType: TextInputType.datetime,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'HH:MM',
      ),
      validator: (value) =>
          _isTime(value ?? '') ? null : 'HH:MM 형식으로 입력하세요.',
      onChanged: (value) => _updateSetting(key, value),
    );
  }

  Widget _profileTimeField(String label, String key) {
    final profile = _defaultProfile();
    return TextFormField(
      key: ValueKey('profile-$key-$_settingsRevision'),
      initialValue: _string(profile[key]),
      keyboardType: TextInputType.datetime,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'HH:MM',
      ),
      validator: (value) =>
          _isTime(value ?? '') ? null : 'HH:MM 형식으로 입력하세요.',
      onChanged: (value) => _updateDefaultProfile({key: value}),
    );
  }

  Map<String, dynamic> _defaultProfile() {
    final profiles = _asMap(_settings?['store_profiles']);
    final profile = _asMap(profiles['default']);
    return {
      'display_name': '기본 매장',
      'operating_hours_configured': false,
      'open_time': '10:00',
      'close_time': '19:30',
      'closed_weekdays': <int>[],
      'holidays': <String>[],
      'size': '',
      'menu_items': <String>[],
      'important_metrics': <String>[
        'gross_amount',
        'pure_sales_amount',
        'receipt_count',
        'avg_ticket',
        'cancel_rate',
      ],
      'thresholds': <String, dynamic>{},
      ...profile,
    };
  }

  void _updateDefaultProfile(Map<String, dynamic> patch) {
    final settings = _settings;
    if (settings == null) return;
    final profile = {..._defaultProfile(), ...patch};
    profile['operating_hours_configured'] = true;
    final weekdays = _stringList(settings['weekdays']);
    final weekdayNumbers = <String, int>{
      'mon': 1,
      'tue': 2,
      'wed': 3,
      'thu': 4,
      'fri': 5,
      'sat': 6,
      'sun': 7,
    };
    profile['closed_weekdays'] = [
      for (final (day, _) in _weekdayOptions)
        if (!weekdays.contains(day)) weekdayNumbers[day]!,
    ];
    final profiles = _asMap(settings['store_profiles']);
    _updateSetting('store_profiles', {...profiles, 'default': profile});
  }

  Widget _textField(
    String label,
    String key, {
    int maxLines = 1,
    int? maxLength,
  }) {
    return TextFormField(
      key: ValueKey('settings-$key-$_settingsRevision'),
      initialValue: _string(_settings?[key]),
      maxLines: maxLines,
      maxLength: maxLength,
      decoration: InputDecoration(labelText: label),
      onChanged: (value) => _updateSetting(key, value),
    );
  }

  Widget _numberField(
    String label,
    String key, {
    required double min,
    double? max,
  }) {
    final integer = _settings?[key] is int;
    return TextFormField(
      key: ValueKey('settings-$key-$_settingsRevision'),
      initialValue: _string(_settings?[key]),
      keyboardType: TextInputType.numberWithOptions(decimal: !integer),
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final parsed = double.tryParse(value ?? '');
        if (parsed == null ||
            !parsed.isFinite ||
            parsed < min ||
            (max != null && parsed > max)) {
          return '범위 ${_numberText(min)}${max == null ? ' 이상' : '–${_numberText(max)}'}';
        }
        if (integer && parsed != parsed.roundToDouble()) {
          return '정수로 입력하세요.';
        }
        return null;
      },
      onChanged: (value) {
        final current = _settings?[key];
        final parsed = current is int
            ? int.tryParse(value)
            : double.tryParse(value);
        if (parsed != null) _updateSetting(key, parsed);
      },
    );
  }

  Widget _thresholdField(
    String key,
    String label, {
    required bool integer,
    required double min,
    double? max,
  }) {
    final thresholds = _asMap(_settings?['thresholds']);
    return TextFormField(
      key: ValueKey('threshold-$key-$_settingsRevision'),
      initialValue: _string(thresholds[key]),
      keyboardType: TextInputType.numberWithOptions(decimal: !integer),
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final parsed = double.tryParse(value ?? '');
        if (parsed == null || parsed < min || (max != null && parsed > max)) {
          return '값을 확인하세요.';
        }
        if (integer && parsed != parsed.roundToDouble()) {
          return '정수로 입력하세요.';
        }
        return null;
      },
      onChanged: (value) {
        final parsed =
            integer ? int.tryParse(value) : double.tryParse(value);
        if (parsed != null) _updateNestedSetting('thresholds', key, parsed);
      },
    );
  }

  Widget _listField(String label, String key) {
    return TextFormField(
      key: ValueKey('list-$key-$_settingsRevision'),
      initialValue: _stringList(_settings?[key]).join(', '),
      decoration: InputDecoration(
        labelText: '$label (쉼표 구분)',
        helperText: '서버가 지원하는 값만 저장됩니다.',
      ),
      onChanged: (value) => _updateSetting(
        key,
        value
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList(growable: false),
      ),
    );
  }

  Widget _dropdownField(
    String label,
    String key,
    Map<String, String> options,
  ) {
    final current = _string(_settings?[key]);
    final value = options.containsKey(current) ? current : options.keys.first;
    return DropdownButtonFormField<String>(
      key: ValueKey('dropdown-$key-$_settingsRevision'),
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final entry in options.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: (next) {
        if (next != null) _updateSetting(key, next);
      },
    );
  }

  Widget _providerField() {
    final availableProviders = _providers
        .where((provider) => _string(provider['id']).isNotEmpty)
        .toList(growable: false);
    final options = availableProviders.isEmpty
        ? const [
            {'id': 'openai_codex', 'name': 'OpenAI Codex', 'available': true},
            {'id': 'opencode_go', 'name': 'OpenCode', 'available': true},
          ]
        : availableProviders;
    final current = _string(_settings?['llm_provider'], 'openai_codex');
    final valid = options.any((provider) => provider['id'] == current);
    return DropdownButtonFormField<String>(
      key: ValueKey('provider-$_settingsRevision'),
      initialValue: valid ? current : _string(options.first['id']),
      decoration: const InputDecoration(labelText: 'LLM 프로바이더'),
      items: [
        for (final provider in options)
          DropdownMenuItem(
            value: _string(provider['id']),
            enabled: provider['available'] != false,
            child: Text(
              '${_string(provider['name'], _string(provider['id']))}'
              '${provider['enabled'] == false ? ' (Off)' : ''}'
              '${provider['available'] == false ? ' (인증 필요)' : ''}',
            ),
          ),
      ],
      onChanged: (value) {
        if (value != null) _updateSetting('llm_provider', value);
      },
    );
  }

  Widget _profilesJsonField() {
    final profiles = _asMap(_settings?['store_profiles']);
    final initial = const JsonEncoder.withIndent('  ').convert(profiles);
    return TextFormField(
      key: ValueKey('store-profiles-$_settingsRevision'),
      initialValue: initial,
      maxLines: 8,
      keyboardType: TextInputType.multiline,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      decoration: InputDecoration(
        labelText: '매장별 운영·메뉴·임계값 profile (JSON)',
        helperText: _profileJsonError ?? 'JSON 객체를 입력하세요.',
        errorText: _profileJsonError,
      ),
      onChanged: (value) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is! Map) throw const FormatException();
          _profileJsonError = null;
          _updateSetting('store_profiles', _asMap(decoded));
        } on FormatException {
          setState(() {
            _profileJsonError = '올바른 JSON 객체를 입력하세요.';
            _settingsDirty = true;
          });
        }
      },
    );
  }

  Widget _buildRecipientsEditor() {
    final recipients = _recipients(_settings ?? {});
    final issues = _recipientIssues();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            children: [
              const Text(
                'Telegram 수신자',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              TextButton.icon(
                onPressed: recipients.length >= 100 ? null : _addRecipient,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('추가'),
              ),
            ],
          ),
          Text(
            '활성 ${recipients.where((item) => item['enabled'] == true).length}명'
            ' · 등록 ${recipients.length} / 100명',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          if (recipients.isEmpty)
            const Text('등록된 수신자가 없습니다.')
          else
            for (var index = 0; index < recipients.length; index += 1)
              _recipientCard(recipients[index], index),
          for (final issue in issues) _errorText(issue),
          const Text(
            'Chat ID는 서버에서 secret으로 관리되지 않습니다. 실제 보고서를 보내는 봇에 먼저 /start를 보내세요.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _recipientCard(Map<String, dynamic> recipient, int index) {
    final id = _string(recipient['recipient_id']);
    final localKey = _recipientLocalKeys[id] ?? id;
    final dirty = _settingsDirty;
    return Card(
      key: ValueKey('recipient-$localKey'),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: ValueKey('recipient-label-$localKey-$_settingsRevision'),
              initialValue: _string(recipient['label']),
              maxLength: 80,
              decoration: InputDecoration(labelText: '수신자 ${index + 1} 이름'),
              onChanged: (value) =>
                  _updateRecipient(id, {'label': value}),
            ),
            TextFormField(
              key: ValueKey('recipient-chat-$localKey-$_settingsRevision'),
              initialValue: _string(recipient['chat_id']),
              maxLength: 64,
              keyboardType: TextInputType.text,
              decoration: const InputDecoration(
                labelText: 'Telegram Chat ID',
                hintText: '예: 123456789 또는 -100…',
              ),
              onChanged: (value) => _updateRecipientChatId(id, value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('보고서 수신'),
              value: recipient['enabled'] == true,
              onChanged: (value) =>
                  _updateRecipient(id, {'enabled': value}),
            ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              children: [
                OutlinedButton(
                  onPressed: dirty ||
                          _string(recipient['chat_id']).isEmpty ||
                          _busyAction != null
                      ? null
                      : () => unawaited(_testTelegramRecipient(recipient)),
                  child: Text(
                    _testingRecipientId == id ? '테스트 중…' : '연결 테스트',
                  ),
                ),
                TextButton(
                  onPressed: () => _removeRecipient(id),
                  child: const Text('삭제'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _addRecipient() {
    final settings = _settings;
    if (settings == null) return;
    final recipients = _recipients(settings);
    if (recipients.length >= 100) return;
    final id = _newUuid();
    _recipientOriginalChatIds[id] = '';
    _recipientLocalKeys[id] = _newUuid();
    _updateSetting('telegram_recipients', [
      ...recipients,
      {
        'recipient_id': id,
        'label': '새 수신자',
        'chat_id': '',
        'enabled': false,
      },
    ]);
  }

  void _updateRecipient(String id, Map<String, dynamic> patch) {
    final recipients = _recipients(_settings ?? {});
    _updateSetting(
      'telegram_recipients',
      recipients.map((recipient) {
        if (_string(recipient['recipient_id']) != id) return recipient;
        return {...recipient, ...patch};
      }).toList(growable: false),
    );
  }

  void _updateRecipientChatId(String id, String chatId) {
    final recipients = _recipients(_settings ?? {});
    final target = recipients.where(
      (recipient) => _string(recipient['recipient_id']) == id,
    );
    if (target.isEmpty) return;
    final original = _recipientOriginalChatIds.putIfAbsent(
      id,
      () => _string(target.first['chat_id']),
    );
    var nextId = id;
    final changed = _normalizeChatId(original) != _normalizeChatId(chatId);
    if (changed && !_rotatedRecipientIds.contains(id)) {
      nextId = _newUuid();
      _rotatedRecipientIds
        ..remove(id)
        ..add(nextId);
      _recipientOriginalChatIds.remove(id);
      _recipientOriginalChatIds[nextId] = original;
      _recipientLocalKeys[nextId] = _recipientLocalKeys.remove(id) ?? id;
    }
    _updateSetting(
      'telegram_recipients',
      recipients.map((recipient) {
        if (_string(recipient['recipient_id']) != id) return recipient;
        return {
          ...recipient,
          'recipient_id': nextId,
          'chat_id': chatId,
        };
      }).toList(growable: false),
    );
  }

  void _removeRecipient(String id) {
    final recipients = _recipients(_settings ?? {})
        .where((recipient) => _string(recipient['recipient_id']) != id)
        .toList(growable: false);
    _recipientOriginalChatIds.remove(id);
    _rotatedRecipientIds.remove(id);
    _recipientLocalKeys.remove(id);
    _updateSetting('telegram_recipients', recipients);
  }

  List<String> _recipientIssues() {
    final recipients = _recipients(_settings ?? {});
    final issues = <String>[];
    final seen = <String>{};
    for (var index = 0; index < recipients.length; index += 1) {
      final recipient = recipients[index];
      if (_string(recipient['label']).trim().isEmpty) {
        issues.add('${index + 1}번 수신자 이름을 입력하세요.');
      }
      final normalized = _normalizeChatId(_string(recipient['chat_id']));
      if (normalized == null) {
        issues.add('${index + 1}번 수신자의 Chat ID가 올바르지 않습니다.');
      } else if (!seen.add(normalized)) {
        issues.add('${index + 1}번 수신자의 Chat ID가 중복되었습니다.');
      }
    }
    if (_settings?['telegram_enabled'] == true &&
        !recipients.any((recipient) => recipient['enabled'] == true)) {
      issues.add('Telegram 전송에는 활성 수신자가 필요합니다.');
    }
    return issues;
  }

  Widget _buildConnectionsPanel() {
    final telegram = _secretStatus['telegram_bot_token'];
    final opencode = _secretStatus['opencode_go_api_token'];
    final codex = _codexAuth;
    return Panel(
      title: '연결 상태와 테스트',
      subtitle: '비밀값 원문은 읽거나 화면에 표시하지 않습니다.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _secretStatusRow('Telegram Bot', telegram),
          _secretStatusRow('OpenCode', opencode),
          _secretStatusRow(
            'OpenAI Codex',
            codex == null
                ? null
                : {
                    'configured': codex['configured'],
                    'source': codex['auth_method'],
                  },
          ),
          if (_providersError != null) _errorText(_providersError!),
          if (_providers.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _providers
                  .map((provider) {
                    final name = _string(
                      provider['name'],
                      _string(provider['id']),
                    );
                    final status = provider['enabled'] == false
                        ? 'Off'
                        : provider['available'] == true
                            ? '사용 가능'
                            : '인증 필요';
                    return '$name: $status';
                  })
                  .join(' · '),
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed:
                    _busyAction == null ? _testTelegramGeneral : null,
                child: const Text('Telegram 테스트'),
              ),
              OutlinedButton(
                onPressed: _busyAction == null
                    ? () => _testProvider('opencode')
                    : null,
                child: const Text('OpenCode 테스트'),
              ),
              OutlinedButton(
                onPressed: _busyAction == null
                    ? () => _testProvider('codex')
                    : null,
                child: const Text('Codex 테스트'),
              ),
            ],
          ),
          const Divider(height: 24),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            children: [
              const Text(
                'Codex 인증',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  codex == null
                      ? '확인 중'
                      : '${_string(codex['status'])}'
                          '${_string(codex['auth_method']).isEmpty ? '' : ' · ${_string(codex['auth_method'])}'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '로그인은 서버에서 처리됩니다. API 키 입력은 지원하지 않습니다. '
            '인증 주소는 복사해 브라우저에서 열고, 진행 중인 흐름은 화면을 나가면 폴링이 중지됩니다.',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _codexLoginAction == null
                    ? () => _startCodexLogin('chatgpt')
                    : null,
                child: Text(
                  _codexLoginAction == 'chatgpt'
                      ? '시작 중…'
                      : 'ChatGPT 로그인',
                ),
              ),
              OutlinedButton(
                onPressed: _codexLoginAction == null
                    ? () => _startCodexLogin('device_code')
                    : null,
                child: Text(
                  _codexLoginAction == 'device_code'
                      ? '시작 중…'
                      : '디바이스 로그인',
                ),
              ),
              if (codex?['configured'] == true)
                TextButton(
                  onPressed: _busyAction == null ? _logoutCodex : null,
                  child: const Text('Codex 로그아웃'),
                ),
            ],
          ),
          if (_codexLogin != null) _buildCodexLogin(),
          if (_codexLoginError != null) _errorText(_codexLoginError!),
        ],
      ),
    );
  }

  Widget _secretStatusRow(String label, Object? status) {
    final value = _asMap(status);
    final configured = value['configured'] == true;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        configured ? Icons.check_circle_outline : Icons.error_outline,
        color: configured ? AppColors.success : AppColors.warning,
      ),
      title: Text(label),
      subtitle: Text(
        status == null
            ? '상태 확인 불가'
            : configured
                ? '설정됨${_string(value['source']).isEmpty ? '' : ' · ${_string(value['source'])}'}'
                : '미설정',
      ),
      trailing: Text(
        configured ? '설정됨' : status == null ? '확인 중' : '미설정',
        style: TextStyle(
          color: configured ? AppColors.success : AppColors.warning,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildCodexLogin() {
    final login = _codexLogin!;
    final status = _string(login['status']);
    final method = _string(login['method']);
    final url = method == 'device_code'
        ? _string(login['verification_url']).isNotEmpty
            ? _string(login['verification_url'])
            : _string(login['auth_url'])
        : _string(login['auth_url']).isNotEmpty
            ? _string(login['auth_url'])
            : _string(login['verification_url']);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Codex 로그인 · ${_codexStatusLabel(status)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (status == 'pending') ...[
            if (_string(login['message']).isNotEmpty)
              Text(
                _safeOperationalText(_string(login['message'])),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            if (_string(login['user_code']).isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('인증 코드'),
              SelectableText(
                _string(login['user_code']),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
            ],
            if (url.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(
                url,
                style: const TextStyle(color: AppColors.info, fontSize: 12),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _copyCodexUrl,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('로그인 URL 복사'),
                ),
              ),
            ],
            OutlinedButton(
              onPressed: _codexLoginAction == null ? _cancelCodexLogin : null,
              child: Text(
                _codexLoginAction == 'cancel' ? '취소 중…' : '로그인 취소',
              ),
            ),
          ] else if (_string(login['message']).isNotEmpty)
            Text(
              _safeOperationalText(_string(login['message'])),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }

  String _codexStatusLabel(String status) => switch (status) {
        'pending' => '진행 중',
        'succeeded' || 'success' || 'completed' => '완료',
        'failed' => '실패',
        'cancelled' || 'canceled' => '취소됨',
        'expired' => '만료됨',
        'timed_out' => '시간 초과',
        'not_found' => '진행 중인 로그인 없음',
        _ => status.isEmpty ? '확인 중' : status,
      };

  Widget _buildManualRunPanel() {
    return Panel(
      title: '수동 날짜 실행',
      subtitle: '선택한 영업일의 보고서를 즉시 생성합니다.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _chooseManualDate,
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text('대상 날짜 · ${_manualTargetDate ?? '-'}'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busyAction == null ? _startManualRun : null,
            icon: const Icon(Icons.play_arrow),
            label: Text(_busyAction == 'run' ? '요청 중…' : '보고서 실행'),
          ),
        ],
      ),
    );
  }

  Widget _buildRunsPanel() {
    final active = _runs.where(_isRunActive).length;
    return Panel(
      title: '최근 실행 (${_runs.length})',
      subtitle: active > 0
          ? '$active건 진행 중 · ${widget.runPollingInterval.inSeconds}초 간격으로 갱신'
          : '실행을 선택하면 상세 정보와 보고서 작업을 확인할 수 있습니다.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_runsError != null) _errorText(_runsError!),
          if (_runs.isEmpty)
            const Text('실행 이력이 없습니다.')
          else
            for (final run in _runs) _runTile(run),
        ],
      ),
    );
  }

  Widget _runTile(Map<String, dynamic> run) {
    final id = _runId(run);
    final selected = id.isNotEmpty && id == _selectedRunId;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        selected: selected,
        title: Text(
          _string(run['target_date'], '대상일 미상'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${_triggerLabel(_string(run['trigger']))} · '
          '${_dateTime(run['created_at'])}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _statusChip(_string(run['status'])),
        onTap: id.isEmpty
            ? null
            : () => unawaited(_loadRunDetail(
                  id,
                  generation: _authorizationGeneration,
                  select: true,
                )),
      ),
    );
  }

  Widget _buildSelectedRunPanel() {
    final run = _selectedRun;
    return Panel(
      title: '실행 상세',
      subtitle: run == null
          ? '최근 실행에서 상세 보기를 선택하세요.'
          : '${_string(run['target_date'])} · ${_statusLabel(_string(run['status']))}',
      child: run == null
          ? const Text('선택된 실행이 없습니다.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _metricChip('상태', _statusLabel(_string(run['status']))),
                    _metricChip('단계', _string(run['current_step'], '-')),
                    _metricChip(
                      '수집',
                      _string(run['records_collected'], '-'),
                    ),
                    _metricChip('시도', _string(run['attempts'], '-')),
                    _metricChip(
                      '시작',
                      _dateTime(run['started_at'] ?? run['created_at']),
                    ),
                    _metricChip('완료', _dateTime(run['finished_at'])),
                    _metricChip('전송', _dateTime(run['sent_at'])),
                  ],
                ),
                if (_string(run['llm_status']).isNotEmpty ||
                    _string(run['delivery_status']).isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'LLM ${_string(run['llm_status'], '-')} · '
                    'Telegram ${_string(run['delivery_status'], '-')}',
                  ),
                ],
                if (_string(run['error_message']).isNotEmpty)
                  _messagePanel(
                    '오류',
                    _string(run['error_message']),
                    AppColors.danger,
                  ),
                if (_detailError != null) _errorText(_detailError!),
                if (_string(run['warning_message']).isNotEmpty)
                  _messagePanel(
                    '경고',
                    _string(run['warning_message']),
                    AppColors.warning,
                  ),
                _buildDeliveryList(run),
                _buildExternalCalls(run),
                const SizedBox(height: 8),
                Text(
                  _reportTitle(run),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                SelectableText(
                  _reportBody(run),
                  style: const TextStyle(height: 1.45),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_isRunActive(run))
                      OutlinedButton.icon(
                        onPressed:
                            _busyAction == null ? () => _cancelRun(run) : null,
                        icon: const Icon(Icons.cancel_outlined),
                        label: Text(
                          _busyAction == 'cancel' ? '취소 중…' : '실행 취소',
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: _busyAction == null &&
                              _string(run['report_id']).isNotEmpty
                          ? () => _regenerateReport(run)
                          : null,
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        _busyAction == 'regenerate' ? '요청 중…' : '보고서 재생성',
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _busyAction == null &&
                              _string(run['report_id']).isNotEmpty &&
                              !_settingsDirty &&
                              _recipientIssues().isEmpty
                          ? () => _openResendDialog(run)
                          : null,
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('보고서 재전송'),
                    ),
                  ],
                ),
                if (_settingsDirty)
                  const Text(
                    '재전송 전에 수신자 변경을 저장하세요.',
                    style: TextStyle(color: AppColors.warning, fontSize: 12),
                  ),
              ],
            ),
    );
  }

  Widget _buildDeliveryList(Map<String, dynamic> run) {
    final deliveries = _mapList(run['deliveries']);
    if (deliveries.isEmpty) return const SizedBox.shrink();
    final summary = _asMap(run['delivery_summary']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Text(
          'Telegram 전송 결과'
          '${summary.isEmpty ? '' : ' · ${_string(summary['sent'], '0')} / ${_string(summary['total'], '0')} 전송'}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        for (final delivery in deliveries)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_string(delivery['recipient_label'])} · '
                  '${_statusLabel(_string(delivery['status']))}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${_string(delivery['target_masked'])} · '
                  '${_string(delivery['sent_count'], '0')}/'
                  '${_string(delivery['chunk_count'], '0')}개 전송',
                  style:
                      const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                if (_string(delivery['error_message']).isNotEmpty)
                  Text(
                    _safeOperationalText(_string(delivery['error_message'])),
                    style:
                        const TextStyle(color: AppColors.warning, fontSize: 12),
                  ),
                if (_string(delivery['skip_reason']).isNotEmpty)
                  Text(
                    _safeOperationalText(_string(delivery['skip_reason'])),
                    style:
                        const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildExternalCalls(Map<String, dynamic> run) {
    final calls = _mapList(run['external_calls']);
    if (calls.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('외부 호출 기록'),
      children: [
        for (final call in calls)
          ListTile(
            dense: true,
            title: Text(
              '${_string(call['provider'])} · ${_string(call['operation'])}',
            ),
            subtitle: Text(
              '${_string(call['status'])}'
              '${call['http_status'] == null ? '' : ' · HTTP ${_string(call['http_status'])}'}'
              '${_string(call['error_message']).isEmpty ? '' : ' · ${_safeOperationalText(_string(call['error_message']))}'}',
            ),
          ),
      ],
    );
  }

  Widget _buildAuditsPanel() {
    return Panel(
      title: '감사 로그 (${_audits.length})',
      subtitle: '설정 변경, 연결 테스트, 실행과 보고서 작업 기록입니다.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_auditsError != null) _errorText(_auditsError!),
          if (_audits.isEmpty)
            const Text('감사 이력이 없습니다.')
          else
            for (final audit in _audits)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_string(audit['action'], '작업 미상')),
                subtitle: Text(
                  '${_dateTime(audit['created_at'])} · '
                  '${_string(audit['actor'], '-')}'
                  '${_string(audit['detail']).isEmpty ? '' : '\n${_safeOperationalText(_string(audit['detail']))}'}',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildValidationResult(Map<String, dynamic> validation) {
    final errors = _mapList(validation['errors']);
    final warnings = _mapList(validation['warnings']);
    if (errors.isEmpty && warnings.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          validation['valid'] == true
              ? '서버 검증을 통과했습니다.'
              : '설정 검증 결과를 확인하세요.',
          style: TextStyle(
            color: validation['valid'] == true
                ? AppColors.success
                : AppColors.warning,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final issue in errors)
          _errorText(
            '${_string(issue['field']).isEmpty ? '' : '${_string(issue['field'])} · '}${_safeOperationalText(_string(issue['message']))}',
          ),
        for (final issue in warnings)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '경고 · ${_safeOperationalText(_string(issue['message']))}',
              style: const TextStyle(color: AppColors.warning),
            ),
          ),
      ],
    );
  }

  Widget _statusChip(String status) {
    final color = switch (status.toLowerCase()) {
      'succeeded' || 'sent' => AppColors.success,
      'failed' || 'partial_failed' || 'ambiguous' => AppColors.danger,
      'pending' || 'running' || 'retry_wait' || 'queued' => AppColors.warning,
      _ => AppColors.muted,
    };
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(
        _statusLabel(status),
        style: TextStyle(color: color, fontSize: 11),
      ),
      side: BorderSide(color: color.withValues(alpha: 0.35)),
      backgroundColor: color.withValues(alpha: 0.08),
    );
  }

  Widget _metricChip(String label, String value) => Chip(
        visualDensity: VisualDensity.compact,
        label: Text('$label · $value', overflow: TextOverflow.ellipsis),
      );

  Widget _messagePanel(String label, String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label · ${_safeOperationalText(text)}',
        style: TextStyle(color: color),
      ),
    );
  }

  Widget _errorText(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          text,
          style: const TextStyle(color: AppColors.danger, fontSize: 13),
        ),
      );

  String _reportTitle(Map<String, dynamic> run) {
    final report = _asMap(run['report']);
    return _string(report['title'], '${_string(run['target_date'])} 일일보고서');
  }

  String _reportBody(Map<String, dynamic> run) {
    final report = _asMap(run['report']);
    final content = _string(report['content']);
    if (content.isNotEmpty) return _safeOperationalText(content);
    final message = _string(report['message']);
    if (message.isNotEmpty) return _safeOperationalText(message);
    final sections = report['sections'];
    if (sections is List) {
      return sections.map((item) => _safeOperationalText('$item')).join('\n\n');
    }
    if (sections is Map) {
      return sections.entries
          .map((entry) =>
              '${entry.key}\n${_safeOperationalText('${entry.value}')}')
          .join('\n\n');
    }
    return '생성된 보고서 본문이 없습니다.';
  }

  String _triggerLabel(String trigger) => switch (trigger) {
        'scheduled' => '자동',
        'manual' => '수동',
        'regenerate' => '재생성',
        'resend' => '재전송',
        '' => '유형 미상',
        _ => trigger,
      };

  String _statusLabel(String status) => switch (status.toLowerCase()) {
        'queued' || 'pending' => '대기 중',
        'running' => '생성 중',
        'retry_wait' => '재시도 대기',
        'succeeded' || 'success' || 'completed' => '완료',
        'sent' => '전송 완료',
        'partial_failed' => '일부 확인 필요',
        'failed' => '실패',
        'ambiguous' => '전송 확인 필요',
        'skipped' => '건너뜀',
        'cancelled' || 'canceled' => '취소됨',
        'timed_out' => '시간 초과',
        '' => '확인 불가',
        _ => status,
      };

  bool _isRunActive(Map<String, dynamic> run) => const {
        'queued',
        'pending',
        'running',
        'retry_wait',
      }.contains(_string(run['status']).toLowerCase());

  String _safeRequestError(Object error, String fallback) {
    if (error is! ApiException) return fallback;
    if (error.isTransportError) return '서버에 연결할 수 없습니다. 네트워크 상태를 확인하세요.';
    return switch (error.statusCode) {
      401 || 403 => '관리자 인증 또는 권한을 확인하세요.',
      404 => '요청한 항목을 찾을 수 없습니다.',
      409 => '설정이 변경됐거나 중복 가능성 확인이 필요합니다. 새로고침 후 다시 시도하세요.',
      422 => '입력값 또는 대상 상태를 확인하세요.',
      400 => '요청을 처리할 수 없습니다. 날짜와 대상 상태를 확인하세요.',
      final code when code != null => '요청에 실패했습니다 (HTTP $code).',
      _ => fallback,
    };
  }

  String _safeOperationalText(String value) {
    var sanitized = value;
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'\bBearer\s+[^\s,;]+', caseSensitive: false),
      (_) => 'Bearer [숨김]',
    );
    sanitized = sanitized.replaceAllMapped(
      RegExp(
        r'\b(api[_ -]?key|token|secret|password)\b\s*[:=]\s*[^\s,;]+',
        caseSensitive: false,
      ),
      (match) => '${match[1]}=[숨김]',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'\b(?:sk-[A-Za-z0-9_-]{12,}|xox[baprs]-[A-Za-z0-9-]+)\b'),
      '[숨김]',
    );
    return sanitized.length > 1200
        ? '${sanitized.substring(0, 1200)}…'
        : sanitized;
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _recipients(Map<String, dynamic> settings) =>
      _mapList(settings['telegram_recipients']);

  String _newUuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  Future<String> _requestIdForIntent({
    required String prefix,
    required String fingerprint,
  }) async {
    var requests = _pendingRequestIds[prefix];
    if (requests == null) {
      requests = <String, String>{};
      if (widget.requestJson == null) {
        final stored = await context.read<AppState>().readActiveTask(prefix);
        if (stored != null) {
          try {
            final decoded = jsonDecode(stored);
            final rawRequests = decoded is Map ? decoded['requests'] : null;
            if (rawRequests is Map) {
              for (final entry in rawRequests.entries) {
                final key = entry.key.toString();
                final value = entry.value?.toString() ?? '';
                if (key.isNotEmpty && value.isNotEmpty) {
                  requests[key] = value;
                }
              }
            }
          } on FormatException {
            // Ignore an older or malformed entry and establish a fresh intent.
          }
        }
      }
      _pendingRequestIds[prefix] = requests;
    }

    final existing = requests[fingerprint];
    final requestId = existing ?? _newUuid();
    if (existing == null) {
      requests[fingerprint] = requestId;
    }
    if (widget.requestJson == null) {
      await context.read<AppState>().saveActiveTask(
            prefix,
            jsonEncode(<String, Object?>{'requests': requests}),
          );
    }
    return requestId;
  }

  Future<void> _completeRequestIntent({
    required String prefix,
    required String fingerprint,
  }) async {
    final current = _pendingRequestIds[prefix];
    if (current == null || !current.containsKey(fingerprint)) return;
    final requests = Map<String, String>.of(current)..remove(fingerprint);
    if (widget.requestJson == null) {
      if (requests.isEmpty) {
        await context.read<AppState>().clearActiveTask(prefix);
      } else {
        await context.read<AppState>().saveActiveTask(
              prefix,
              jsonEncode(<String, Object?>{'requests': requests}),
            );
      }
    }
    if (requests.isEmpty) {
      _pendingRequestIds.remove(prefix);
    } else {
      _pendingRequestIds[prefix] = requests;
    }
  }

  static String _maskChatId(String value) =>
      value.isEmpty ? '-' : '***${value.substring(value.length > 4 ? value.length - 4 : 0)}';

  static String? _normalizeChatId(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || RegExp(r'[\x00-\x1f]').hasMatch(trimmed)) {
      return null;
    }
    if (RegExp(r'^@[A-Za-z0-9_]{1,255}$').hasMatch(trimmed)) return trimmed;
    if (!RegExp(r'^-?\d+$').hasMatch(trimmed)) return null;
    final parsed = BigInt.tryParse(trimmed);
    if (parsed == null ||
        parsed == BigInt.zero ||
        parsed < BigInt.parse('-9223372036854775808') ||
        parsed > BigInt.parse('9223372036854775807')) {
      return null;
    }
    return parsed.toString();
  }

  static bool _isTime(String value) =>
      RegExp(r'^\d{2}:\d{2}$').hasMatch(value) &&
      (int.tryParse(value.substring(0, 2)) ?? 99) < 24 &&
      (int.tryParse(value.substring(3, 5)) ?? 99) < 60;

  static String _numberText(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';

  static String _runId(Map<String, dynamic> run) =>
      _string(run['id'] ?? run['run_id']);

  static String _dateTime(Object? value) {
    final text = _string(value);
    if (text.isEmpty) return '-';
    return text.replaceFirst('T', ' ').split('.').first;
  }

  static int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static String _string(Object? value, [String fallback = '']) {
    if (value == null) return fallback;
    final text = value.toString();
    return text.isEmpty ? fallback : text;
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is! Map) return <String, dynamic>{};
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  static List<Map<String, dynamic>> _mapList(Object? value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map(_asMap).toList(growable: false);
  }
}
