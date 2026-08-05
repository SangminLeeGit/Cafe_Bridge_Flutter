import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/panel.dart';

typedef DailyReportJsonFetcher = Future<Map<String, dynamic>> Function(
  String endpoint, {
  Map<String, Object?>? params,
});

class DailyReportMonitorScreen extends StatefulWidget {
  final DailyReportJsonFetcher? fetchJson;
  final Duration pollingInterval;

  const DailyReportMonitorScreen({
    super.key,
    this.fetchJson,
    this.pollingInterval = const Duration(seconds: 3),
  });

  @override
  State<DailyReportMonitorScreen> createState() =>
      _DailyReportMonitorScreenState();
}

class _DailyReportMonitorScreenState extends State<DailyReportMonitorScreen> {
  DailyReportSettingsSummary? _settings;
  List<DailyReportRun> _runs = const [];
  List<DailyReportAudit> _audits = const [];
  DailyReportRun? _selectedRun;
  String? _selectedRunId;
  String _settingsError = '';
  String _runsError = '';
  String _auditsError = '';
  String _detailError = '';
  bool _initialLoading = true;
  bool _settingsInFlight = false;
  bool _runsInFlight = false;
  bool _auditsInFlight = false;
  bool _detailInFlight = false;
  bool _showAudits = false;
  int _detailRequest = 0;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _detailRequest += 1;
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _get(
    String endpoint, {
    Map<String, Object?>? params,
  }) async {
    final injected = widget.fetchJson;
    if (injected != null) {
      return injected(endpoint, params: params);
    }
    final response = await context.read<AppState>().fetchMapParsed(
          endpoint,
          params: params,
          parser: (json) => json,
          cacheTtl: Duration.zero,
          allowStaleOnError: false,
        );
    return response.data;
  }

  Future<void> _loadAll() async {
    if (mounted) {
      setState(() => _initialLoading = true);
    }
    await Future.wait<void>([
      _refreshSettings(),
      _refreshRuns(),
      _refreshAudits(),
    ]);
    if (mounted) {
      setState(() => _initialLoading = false);
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait<void>([
      _refreshSettings(),
      _refreshRuns(),
      _refreshAudits(),
    ]);
  }

  Future<void> _refreshSettings() async {
    if (_settingsInFlight) return;
    _settingsInFlight = true;
    try {
      final json = await _get('/api/admin/daily-reports/settings');
      final parsed = DailyReportSettingsSummary.fromJson(json);
      if (!mounted) return;
      setState(() {
        _settings = parsed;
        _settingsError = '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _settingsError = error.toString());
    } finally {
      _settingsInFlight = false;
    }
  }

  Future<void> _refreshRuns() async {
    if (_runsInFlight) return;
    _runsInFlight = true;
    try {
      final json = await _get(
        '/api/admin/daily-reports/runs',
        params: const {'limit': 30},
      );
      final parsed = DailyReportRun.parseList(json);
      if (!mounted) return;
      setState(() {
        _runs = parsed;
        _runsError = '';
      });
      _syncPolling();

      final selectedId = _selectedRunId;
      if (selectedId != null &&
          parsed.any((run) => run.id == selectedId && run.isActive)) {
        await _loadRunDetail(selectedId, preserveSelection: true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _runsError = error.toString());
    } finally {
      _runsInFlight = false;
    }
  }

  void _syncPolling() {
    final hasActiveRun = _runs.any((run) => run.isActive);
    if (!hasActiveRun) {
      _pollingTimer?.cancel();
      _pollingTimer = null;
      return;
    }
    _pollingTimer ??= Timer.periodic(widget.pollingInterval, (_) {
      _refreshRuns();
    });
  }

  Future<void> _refreshAudits() async {
    if (_auditsInFlight) return;
    _auditsInFlight = true;
    try {
      final json = await _get(
        '/api/admin/daily-reports/audits',
        params: const {'limit': 30},
      );
      final parsed = DailyReportAudit.parseList(json);
      if (!mounted) return;
      setState(() {
        _audits = parsed;
        _auditsError = '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _auditsError = error.toString());
    } finally {
      _auditsInFlight = false;
    }
  }

  Future<void> _loadRunDetail(
    String id, {
    bool preserveSelection = false,
  }) async {
    if (_detailInFlight && id == _selectedRunId) return;
    final request = ++_detailRequest;
    if (!preserveSelection && mounted) {
      setState(() {
        _selectedRunId = id;
        _selectedRun = null;
        _detailError = '';
      });
    }
    _detailInFlight = true;
    try {
      final json = await _get('/api/admin/daily-reports/runs/$id');
      final parsed = DailyReportRun.fromJson(_jsonMap(json['run']));
      if (!mounted || request != _detailRequest) return;
      setState(() {
        _selectedRun = parsed;
        _detailError = '';
      });
    } catch (error) {
      if (!mounted || request != _detailRequest) return;
      setState(() => _detailError = error.toString());
    } finally {
      if (request == _detailRequest) {
        _detailInFlight = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoading && _settings == null && _runs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildSettings(),
          _buildReadOnlyNotice(),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.receipt_long_outlined),
                      label: Text('실행 이력'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.history_outlined),
                      label: Text('감사 이력'),
                    ),
                  ],
                  selected: {_showAudits},
                  onSelectionChanged: (values) {
                    setState(() => _showAudits = values.first);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_showAudits) _buildAudits() else _buildRuns(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '일일보고서 모니터',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
              ),
              const SizedBox(height: 4),
              const Text(
                '자동 보고서 설정과 최근 처리 상태를 읽기 전용으로 확인합니다.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: '새로고침',
          onPressed: _refreshAll,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  Widget _buildSettings() {
    final settings = _settings;
    return Panel(
      title: '자동 실행 설정',
      subtitle: '서버의 현재 설정 및 다음 실행 시각',
      child: settings == null
          ? _errorBlock(_settingsError, retry: _refreshSettings)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _summaryChip(
                      '상태',
                      settings.enabled == null
                          ? '확인 불가'
                          : settings.enabled!
                              ? '사용 중'
                              : '중지됨',
                      icon: settings.enabled == true
                          ? Icons.play_circle_outline
                          : Icons.pause_circle_outline,
                    ),
                    _summaryChip(
                      '일정',
                      settings.scheduleTime ?? '미설정',
                      icon: Icons.schedule_outlined,
                    ),
                    _summaryChip(
                      '시간대',
                      settings.timezone ?? '미설정',
                      icon: Icons.public_outlined,
                    ),
                    _summaryChip(
                      '요일',
                      settings.weekdayLabel,
                      icon: Icons.date_range_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _labelValue(
                  '다음 실행',
                  DailyReportFormat.kst(settings.nextRunAt),
                ),
                const SizedBox(height: 10),
                const Text(
                  '연동 비밀정보',
                  style: TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: settings.secretStatus.entries
                      .map(
                        (entry) => Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(
                            entry.value == true
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                            size: 17,
                            color: entry.value == true
                                ? const Color(0xFF15803D)
                                : const Color(0xFFB45309),
                          ),
                          label: Text(
                            '${_secretLabel(entry.key)} · ${entry.value == null ? '확인 불가' : entry.value! ? '설정됨' : '미설정'}',
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
                if (settings.secretStatus.isEmpty)
                  const Text(
                    '비밀정보 상태를 확인할 수 없습니다.',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                if (_settingsError.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _inlineError(_settingsError),
                ],
              ],
            ),
    );
  }

  Widget _buildReadOnlyNotice() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 20, color: Color(0xFF1D4ED8)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '이 화면에서는 조회만 지원합니다. 설정 변경, 연결 테스트, 수동 실행, 재생성 및 재전송은 웹 관리자 화면을 이용해 주세요.',
              style: TextStyle(color: Color(0xFF1E3A8A), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuns() {
    return Panel(
      title: '최근 실행 30건',
      subtitle: _runs.any((run) => run.isActive)
          ? '진행 중인 실행이 있어 3초마다 갱신합니다.'
          : '실행을 선택하면 보고서 상세를 확인할 수 있습니다.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_runsError.isNotEmpty) ...[
            _inlineError(_runsError),
            const SizedBox(height: 10),
          ],
          if (_runs.isEmpty)
            const Text(
              '실행 이력이 없습니다.',
              style: TextStyle(color: Color(0xFF64748B)),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final list = _runList();
                final detail = _runDetail();
                if (constraints.maxWidth < 720) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      list,
                      if (_selectedRunId != null) ...[
                        const SizedBox(height: 16),
                        detail,
                      ],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: list),
                    const SizedBox(width: 16),
                    Expanded(child: detail),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _runList() {
    return Column(
      children: _runs.map((run) {
        final selected = run.id == _selectedRunId;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: selected ? const Color(0xFFEFF6FF) : Colors.white,
            shape: RoundedRectangleBorder(
              side: BorderSide(
                color: selected
                    ? const Color(0xFF93C5FD)
                    : const Color(0xFFE2E8F0),
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _loadRunDetail(run.id),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            run.targetDate ?? '대상일 미상',
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${run.trigger ?? '유형 미상'} · ${DailyReportFormat.kst(run.createdAt)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _statusBadge(run.status),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _runDetail() {
    if (_selectedRunId == null) {
      return const _DetailPlaceholder();
    }
    if (_detailInFlight && _selectedRun == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_detailError.isNotEmpty && _selectedRun == null) {
      return _errorBlock(
        _detailError,
        retry: () => _loadRunDetail(_selectedRunId!),
      );
    }
    final run = _selectedRun;
    if (run == null) return const _DetailPlaceholder();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  run.reportTitle ?? '생성된 보고서 없음',
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _statusBadge(run.status),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _metric('수집', run.recordsCollected?.toString() ?? '-'),
              _metric('시도', run.attempts?.toString() ?? '-'),
              _metric('시작', DailyReportFormat.kst(run.startedAt)),
              _metric('완료', DailyReportFormat.kst(run.finishedAt)),
            ],
          ),
          if (run.errorMessage != null) ...[
            const SizedBox(height: 12),
            _messageBox('오류', run.errorMessage!, const Color(0xFFDC2626)),
          ],
          if (run.warningMessage != null) ...[
            const SizedBox(height: 8),
            _messageBox(
              '경고',
              run.warningMessage!,
              const Color(0xFFB45309),
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            '보고서 내용',
            style: TextStyle(
              color: Color(0xFF475569),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            run.reportContent ?? '보고서 내용이 없습니다.',
            style: const TextStyle(
              color: Color(0xFF334155),
              height: 1.5,
            ),
          ),
          if (_detailError.isNotEmpty) ...[
            const SizedBox(height: 10),
            _inlineError(_detailError),
          ],
        ],
      ),
    );
  }

  Widget _buildAudits() {
    return Panel(
      title: '최근 감사 이력 30건',
      subtitle: '일일보고서 관리 작업 기록',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_auditsError.isNotEmpty) ...[
            _inlineError(_auditsError),
            const SizedBox(height: 10),
          ],
          if (_audits.isEmpty)
            const Text(
              '감사 이력이 없습니다.',
              style: TextStyle(color: Color(0xFF64748B)),
            )
          else
            ..._audits.map(
              (audit) => Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            audit.action ?? '작업 미상',
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          DailyReportFormat.kst(audit.createdAt),
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '작업자 ${audit.actor ?? '-'}',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                    if (audit.detail != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        audit.detail!,
                        style: const TextStyle(
                          color: Color(0xFF475569),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, String value, {required IconData icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: const Color(0xFF475569)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '$label · $value',
              style: const TextStyle(
                color: Color(0xFF334155),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _labelValue(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _metric(String label, String value) {
    return Text(
      '$label $value',
      style: const TextStyle(color: Color(0xFF475569), fontSize: 12),
    );
  }

  Widget _messageBox(String label, String message, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label · $message',
        style: TextStyle(color: color, fontSize: 13),
      ),
    );
  }

  Widget _statusBadge(String? status) {
    final normalized = status?.toLowerCase();
    final color = switch (normalized) {
      'succeeded' => const Color(0xFF15803D),
      'failed' || 'partial_failed' => const Color(0xFFDC2626),
      'pending' || 'running' => const Color(0xFFB45309),
      _ => const Color(0xFF64748B),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        status ?? 'unknown',
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _inlineError(String message) {
    return Text(
      message,
      style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
    );
  }

  Widget _errorBlock(String message, {required VoidCallback retry}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _inlineError(message.isEmpty ? '정보를 불러오지 못했습니다.' : message),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: retry,
          icon: const Icon(Icons.refresh),
          label: const Text('다시 시도'),
        ),
      ],
    );
  }

  String _secretLabel(String key) {
    return switch (key) {
      'telegram_bot_token' => 'Telegram',
      'opencode_go_api_token' => 'OpenCode',
      _ => key.replaceAll('_', ' '),
    };
  }
}

class _DetailPlaceholder extends StatelessWidget {
  const _DetailPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        '실행을 선택해 상세 보고서를 확인하세요.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFF64748B)),
      ),
    );
  }
}

class DailyReportSettingsSummary {
  final bool? enabled;
  final String? scheduleTime;
  final String? timezone;
  final List<String> weekdays;
  final String? nextRunAt;
  final Map<String, bool?> secretStatus;

  const DailyReportSettingsSummary({
    required this.enabled,
    required this.scheduleTime,
    required this.timezone,
    required this.weekdays,
    required this.nextRunAt,
    required this.secretStatus,
  });

  factory DailyReportSettingsSummary.fromJson(Map<String, dynamic> json) {
    final settings = _jsonMap(json['settings']);
    final secretJson = _jsonMap(json['secret_status']);
    return DailyReportSettingsSummary(
      enabled: _boolValue(settings['enabled']),
      scheduleTime: _nullableText(settings['schedule_time']),
      timezone: _nullableText(settings['timezone']),
      weekdays: _stringList(settings['weekdays']),
      nextRunAt: _nullableText(json['next_run_at']),
      secretStatus: {
        for (final entry in secretJson.entries)
          entry.key: _boolValue(
            entry.value is Map
                ? _jsonMap(entry.value)['configured']
                : entry.value,
          ),
      },
    );
  }

  String get weekdayLabel {
    if (weekdays.isEmpty) return '미설정';
    const labels = {
      'mon': '월',
      'tue': '화',
      'wed': '수',
      'thu': '목',
      'fri': '금',
      'sat': '토',
      'sun': '일',
    };
    return weekdays.map((day) => labels[day.toLowerCase()] ?? day).join(', ');
  }
}

class DailyReportRun {
  final String id;
  final String? reportId;
  final String? targetDate;
  final String? status;
  final String? trigger;
  final String? requestedBy;
  final String? startedAt;
  final String? finishedAt;
  final String? createdAt;
  final int? recordsCollected;
  final int? attempts;
  final String? errorMessage;
  final String? warningMessage;
  final String? reportTitle;
  final String? reportContent;

  const DailyReportRun({
    required this.id,
    required this.reportId,
    required this.targetDate,
    required this.status,
    required this.trigger,
    required this.requestedBy,
    required this.startedAt,
    required this.finishedAt,
    required this.createdAt,
    required this.recordsCollected,
    required this.attempts,
    required this.errorMessage,
    required this.warningMessage,
    required this.reportTitle,
    required this.reportContent,
  });

  factory DailyReportRun.fromJson(Map<String, dynamic> json) {
    final report = _jsonMap(json['report']);
    return DailyReportRun(
      id: _nullableText(json['id']) ?? '',
      reportId: _nullableText(json['report_id']),
      targetDate: _nullableText(json['target_date']),
      status: _nullableText(json['status']),
      trigger: _nullableText(json['trigger']),
      requestedBy: _nullableText(json['requested_by']),
      startedAt: _nullableText(json['started_at']),
      finishedAt: _nullableText(json['finished_at']),
      createdAt: _nullableText(json['created_at']),
      recordsCollected: _intValue(json['records_collected']),
      attempts: _intValue(json['attempts']),
      errorMessage: _nullableMessage(json['error_message']),
      warningMessage: _nullableMessage(json['warning_message']),
      reportTitle: _nullableText(report['title']),
      reportContent: _nullableText(report['content']),
    );
  }

  static List<DailyReportRun> parseList(Map<String, dynamic> json) {
    final rows = json['runs'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => DailyReportRun.fromJson(_jsonMap(row)))
        .where((run) => run.id.isNotEmpty)
        .toList(growable: false);
  }

  bool get isActive {
    final normalized = status?.toLowerCase();
    return normalized == 'pending' || normalized == 'running';
  }
}

class DailyReportAudit {
  final String? id;
  final String? action;
  final String? actor;
  final String? detail;
  final String? createdAt;

  const DailyReportAudit({
    required this.id,
    required this.action,
    required this.actor,
    required this.detail,
    required this.createdAt,
  });

  factory DailyReportAudit.fromJson(Map<String, dynamic> json) {
    return DailyReportAudit(
      id: _nullableText(json['id']),
      action: _nullableText(json['action']),
      actor: _nullableText(json['actor']),
      detail: _nullableMessage(json['detail']),
      createdAt: _nullableText(json['created_at']),
    );
  }

  static List<DailyReportAudit> parseList(Map<String, dynamic> json) {
    final rows = json['audits'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => DailyReportAudit.fromJson(_jsonMap(row)))
        .toList(growable: false);
  }
}

class DailyReportFormat {
  const DailyReportFormat._();

  static String kst(String? value) {
    final text = _nullableText(value);
    if (text == null) return '-';
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return text;
    final kst = parsed.isUtc
        ? parsed.add(const Duration(hours: 9))
        : parsed.toUtc().add(const Duration(hours: 9));
    String two(int number) => number.toString().padLeft(2, '0');
    return '${kst.year}-${two(kst.month)}-${two(kst.day)} '
        '${two(kst.hour)}:${two(kst.minute)} KST';
  }
}

Map<String, dynamic> _jsonMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, item) => MapEntry(key.toString(), item));
}

String? _nullableText(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty || text.toLowerCase() == 'null' ? null : text;
}

String? _nullableMessage(Object? value) {
  if (value is List) {
    final parts = value.map(_nullableMessage).whereType<String>().toList();
    return parts.isEmpty ? null : parts.join('; ');
  }
  if (value is Map) {
    final parts = value.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .toList(growable: false);
    return parts.isEmpty ? null : parts.join('; ');
  }
  return _nullableText(value);
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.map(_nullableText).whereType<String>().toList(growable: false);
}

bool? _boolValue(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final normalized = value?.toString().trim().toLowerCase();
  if (normalized == 'true' || normalized == 'yes' || normalized == '1') {
    return true;
  }
  if (normalized == 'false' || normalized == 'no' || normalized == '0') {
    return false;
  }
  return null;
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString().replaceAll(',', '').trim() ?? '');
}
