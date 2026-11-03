import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/api_contracts.dart';
import '../models/payroll_models.dart';
import '../models/workforce_models.dart';
import '../services/api.dart';
import '../state/app_state.dart';
import '../widgets/empty_state.dart';
import '../widgets/panel.dart';

class PayrollRunsScreen extends StatefulWidget {
  const PayrollRunsScreen({super.key});

  @override
  State<PayrollRunsScreen> createState() => _PayrollRunsScreenState();
}

class _PayrollRunsScreenState extends State<PayrollRunsScreen> {
  late DateTime _fromDate;
  late DateTime _toDate;
  int? _workplaceId;
  List<Workplace> _workplaces = const [];
  List<PayrollRun> _runs = const [];
  PayrollRun? _selectedRun;
  bool _loading = true;
  bool _detailLoading = false;
  String _error = '';
  String _detailError = '';
  String _actionError = '';
  String _busy = '';
  bool _acknowledgeIssues = false;

  @override
  void initState() {
    super.initState();
    final now = ApiService.kstNow();
    _fromDate = DateTime(now.year, now.month, 1);
    _toDate = DateTime(now.year, now.month, now.day);
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final selectedRunId = _selectedRun?.runId;
    if (_fromDate.isAfter(_toDate)) {
      setState(() {
        _error = '시작일은 종료일보다 늦을 수 없습니다.';
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
      _detailError = '';
    });
    try {
      final appState = context.read<AppState>();
      final workplacesResponse = await appState.fetchMapParsed<List<Workplace>>(
        '/api/workforce/workplaces',
        parser: (json) => asListOfMaps(json['workplaces'])
            .map(Workplace.fromJson)
            .toList(growable: false),
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      final runsResponse = await appState.fetchMapParsed<PayrollRunList>(
        '/api/workforce/payroll-runs',
        params: {
          'from_date': _formatDate(_fromDate),
          'to_date': _formatDate(_toDate),
          if (_workplaceId != null) 'workplace_id': _workplaceId,
        },
        parser: PayrollRunList.fromJson,
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      PayrollRun? detail;
      if (selectedRunId != null) {
        final detailResponse = await appState.fetchMapParsed<PayrollRun>(
          '/api/workforce/payroll-runs/$selectedRunId',
          parser: PayrollRun.fromJson,
          cacheTtl: Duration.zero,
          allowStaleOnError: false,
        );
        detail = detailResponse.data;
      }
      if (!mounted) return;
      setState(() {
        _workplaces = workplacesResponse.data;
        _runs = runsResponse.data.runs;
        _selectedRun = detail;
        _loading = false;
        _detailLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
        _detailLoading = false;
      });
    }
  }

  Future<void> _loadDetail(String runId) async {
    setState(() {
      _detailLoading = true;
      _detailError = '';
      _actionError = '';
    });
    try {
      final response =
          await context.read<AppState>().fetchMapParsed<PayrollRun>(
                '/api/workforce/payroll-runs/$runId',
                parser: PayrollRun.fromJson,
                cacheTtl: Duration.zero,
                allowStaleOnError: false,
              );
      if (!mounted) return;
      setState(() {
        _selectedRun = response.data;
        _acknowledgeIssues = false;
        _detailLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _detailError = error.toString();
        _detailLoading = false;
      });
    }
  }

  Future<void> _pickDate({required bool fromDate}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fromDate ? _fromDate : _toDate,
      firstDate: DateTime(2020),
      lastDate: ApiService.kstNow().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (fromDate) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
    await _load();
  }

  Future<void> _createDraft() async {
    if (!context.read<AppState>().hasOperatorAccess || _busy.isNotEmpty) return;
    if (_fromDate.isAfter(_toDate)) {
      setState(() => _error = '시작일은 종료일보다 늦을 수 없습니다.');
      return;
    }
    setState(() {
      _busy = 'create';
      _actionError = '';
    });
    try {
      final created = await context.read<AppState>().postJson(
        '/api/workforce/payroll-runs',
        body: {
          'from_date': _formatDate(_fromDate),
          'to_date': _formatDate(_toDate),
          if (_workplaceId != null) 'workplace_id': _workplaceId,
        },
      );
      if (!mounted) return;
      setState(() => _selectedRun = PayrollRun.fromJson(created));
      await _load();
    } catch (error) {
      if (mounted) setState(() => _actionError = error.toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _runAction(String action) async {
    final run = _selectedRun;
    if (run == null || !context.read<AppState>().hasOperatorAccess) return;
    if (action == 'review' && run.status != 'draft') return;
    if (action == 'confirm' && run.status != 'reviewed') return;
    if (action == 'confirm' &&
        (run.hasBlockingIssues ||
            (run.issues.isNotEmpty && !_acknowledgeIssues))) {
      return;
    }
    setState(() {
      _busy = action;
      _actionError = '';
    });
    try {
      await context.read<AppState>().postJson(
            '/api/workforce/payroll-runs/${run.runId}/$action',
            body: action == 'confirm'
                ? {'acknowledge_issues': _acknowledgeIssues}
                : action == 'explain'
                    ? <String, dynamic>{}
                    : null,
          );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _actionError = error.toString());
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final canOperate = context.select<AppState, bool>(
      (state) => state.hasOperatorAccess,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('급여 정산서')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Panel(
              title: '정산 기간',
              subtitle: '확정된 근무만 급여 정산서에 포함됩니다.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _pickDate(fromDate: true),
                        icon:
                            const Icon(Icons.calendar_today_outlined, size: 16),
                        label: Text('시작 ${_formatDate(_fromDate)}'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _pickDate(fromDate: false),
                        icon: const Icon(Icons.event_outlined, size: 16),
                        label: Text('종료 ${_formatDate(_toDate)}'),
                      ),
                      DropdownButton<int?>(
                        value: _workplaceId,
                        hint: const Text('전체 근무지'),
                        items: [
                          const DropdownMenuItem<int?>(
                              value: null, child: Text('전체 근무지')),
                          ..._workplaces.map((workplace) =>
                              DropdownMenuItem<int?>(
                                  value: workplace.id,
                                  child: Text(workplace.name))),
                        ],
                        onChanged: (value) async {
                          setState(() => _workplaceId = value);
                          await _load();
                        },
                      ),
                    ],
                  ),
                  if (_fromDate.isAfter(_toDate)) ...[
                    const SizedBox(height: 8),
                    const Text('시작일은 종료일보다 늦을 수 없습니다.',
                        style: TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 8),
                  if (canOperate)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed:
                            _busy.isNotEmpty || _fromDate.isAfter(_toDate)
                                ? null
                                : _createDraft,
                        icon: const Icon(Icons.add, size: 16),
                        label:
                            Text(_busy == 'create' ? '생성 중...' : '정산 초안 만들기'),
                      ),
                    )
                  else
                    const Text('조회 전용 · 정산서 생성과 검토에는 operator 권한이 필요합니다.',
                        style:
                            TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                ],
              ),
            ),
            if (_error.isNotEmpty)
              EmptyState(
                title: '정산서를 불러오지 못했습니다.',
                message: _error,
                action:
                    FilledButton(onPressed: _load, child: const Text('다시 시도')),
              )
            else if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_runs.isEmpty)
              const EmptyState(title: '해당 기간에 생성된 정산서가 없습니다.')
            else
              Panel(
                title: '정산서 목록',
                subtitle: '${_runs.length}건',
                child: Column(
                  children: _runs
                      .map((run) => ListTile(
                            key: ValueKey('payroll-run-${run.runId}'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                                '${run.fromDate} ~ ${run.toDate} · v${run.version}'),
                            subtitle: Text(
                                '세전 ${_won(run.totals.grossPay)} · 공제 ${_won(run.totals.taxDeduction)} · 세후 ${_won(run.totals.netPay)} · ${run.totals.workedHours.toStringAsFixed(1)}h · 이슈 ${run.issueCount}건'),
                            trailing: Chip(
                                label: Text(payrollRunStatusLabel(run.status))),
                            onTap: _busy.isNotEmpty
                                ? null
                                : () => _loadDetail(run.runId),
                          ))
                      .toList(growable: false),
                ),
              ),
            if (_detailLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_detailError.isNotEmpty)
              EmptyState(
                title: '정산 상세를 불러오지 못했습니다.',
                message: _detailError,
                action: _selectedRun == null
                    ? null
                    : FilledButton(
                        onPressed: () => _loadDetail(_selectedRun!.runId),
                        child: const Text('다시 시도')),
              ),
            if (_actionError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_actionError,
                    key: const Key('payroll-action-error'),
                    style: const TextStyle(color: Colors.red)),
              ),
            if (_selectedRun != null) _buildDetail(_selectedRun!, canOperate),
          ],
        ),
      ),
    );
  }

  Widget _buildDetail(PayrollRun run, bool canOperate) {
    final workplaceName = run.workplaceId == null
        ? '전체'
        : _workplaces
                .where((workplace) => workplace.id == run.workplaceId)
                .isEmpty
            ? 'ID ${run.workplaceId}'
            : _workplaces
                .firstWhere((workplace) => workplace.id == run.workplaceId)
                .name;
    return Panel(
      title: '정산서 상세',
      subtitle:
          '${run.fromDate} ~ ${run.toDate} · v${run.version} · ${payrollRunStatusLabel(run.status)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              '정산 ID ${run.runId} · 생성 방식 ${run.source.isEmpty ? '-' : run.source}'),
          Text('근무지 $workplaceName'),
          if (run.createdAt != null) Text('생성 ${run.createdAt!.toLocal()}'),
          if (run.reviewedAt != null) Text('검토 ${run.reviewedAt!.toLocal()}'),
          if (run.confirmedAt != null) Text('확정 ${run.confirmedAt!.toLocal()}'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RunMetric(label: '세전', value: _won(run.totals.grossPay)),
              _RunMetric(label: '공제', value: _won(run.totals.taxDeduction)),
              _RunMetric(label: '세후', value: _won(run.totals.netPay)),
              _RunMetric(
                  label: '근무시간',
                  value: '${run.totals.workedHours.toStringAsFixed(1)}h'),
            ],
          ),
          if (run.issues.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('정산 이슈', style: TextStyle(fontWeight: FontWeight.w700)),
            ...run.issues.map((issue) => ListTile(
                  key: ValueKey(
                      'issue-${issue.code}-${issue.shiftId ?? issue.employeeId ?? issue.date ?? ''}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    issue.severity == 'blocking'
                        ? Icons.block
                        : Icons.warning_amber_outlined,
                    color: issue.severity == 'blocking'
                        ? Colors.red
                        : Colors.orange,
                  ),
                  title: Text('[${issue.severityLabel}] ${issue.message}'),
                  subtitle: [
                    if (issue.employeeName?.isNotEmpty == true)
                      issue.employeeName!,
                    if (issue.date?.isNotEmpty == true) issue.date!,
                  ].isEmpty
                      ? null
                      : Text([
                          if (issue.employeeName?.isNotEmpty == true)
                            issue.employeeName!,
                          if (issue.date?.isNotEmpty == true) issue.date!,
                        ].join(' · ')),
                )),
            if (canOperate && run.status == 'reviewed')
              CheckboxListTile(
                key: const Key('payroll-acknowledge-issues'),
                contentPadding: EdgeInsets.zero,
                value: _acknowledgeIssues,
                onChanged: (value) =>
                    setState(() => _acknowledgeIssues = value ?? false),
                title: const Text('위 정산 이슈를 확인했습니다.'),
              ),
            if (run.hasBlockingIssues)
              const Text('차단 이슈가 남아 있어 정산서를 확정할 수 없습니다.',
                  style: TextStyle(color: Colors.red)),
          ],
          if (canOperate) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: run.status == 'draft' && _busy.isEmpty
                      ? () => _runAction('review')
                      : null,
                  child: Text(_busy == 'review' ? '처리 중...' : '검토 완료'),
                ),
                FilledButton(
                  onPressed: run.status == 'reviewed' &&
                          _busy.isEmpty &&
                          !run.hasBlockingIssues &&
                          (run.issues.isEmpty || _acknowledgeIssues)
                      ? () => _runAction('confirm')
                      : null,
                  child: Text(_busy == 'confirm' ? '처리 중...' : '확정'),
                ),
                OutlinedButton(
                  onPressed: _busy.isEmpty ? () => _runAction('explain') : null,
                  child: Text(_busy == 'explain' ? '생성 중...' : 'AI 검토 의견'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          const Text('직원별 명세', style: TextStyle(fontWeight: FontWeight.w700)),
          if (run.statements.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('직원별 명세가 없습니다.'),
            )
          else
            ...run.statements.map((statement) => ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(statement.employeeName),
                  subtitle: Text(
                      '세전 ${_won(statement.totals.grossPay)} · 공제 ${_won(statement.totals.taxDeduction)} · 세후 ${_won(statement.totals.netPay)} · ${statement.totals.workedHours.toStringAsFixed(1)}h · 이슈 ${statement.issues.length}건'),
                  children: statement.issues
                      .map((issue) => ListTile(
                            dense: true,
                            title: Text(
                                '[${issue.severityLabel}] ${issue.message}'),
                            subtitle:
                                issue.date == null ? null : Text(issue.date!),
                          ))
                      .toList(growable: false),
                )),
          const SizedBox(height: 16),
          const Text('LLM 검토 결과',
              style: TextStyle(fontWeight: FontWeight.w700)),
          Text(
              '상태 ${run.explanation.status.isEmpty ? '-' : run.explanation.status} · 제공자 ${run.explanation.provider.isEmpty ? '-' : run.explanation.provider}'),
          if (run.explanation.summary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(run.explanation.summary),
            ),
          ...run.explanation.checks.map((check) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('[${check.severity}] ${check.item}'),
                subtitle: Text(check.reason),
              )),
          if (run.explanation.error.isNotEmpty)
            Text(run.explanation.error,
                style: const TextStyle(color: Colors.red)),
        ],
      ),
    );
  }
}

class _RunMetric extends StatelessWidget {
  final String label;
  final String value;

  const _RunMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Chip(
        label: Text('$label $value'),
        visualDensity: VisualDensity.compact,
      );
}

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _won(num value) {
  final text = value.round().toString();
  final output = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) output.write(',');
    output.write(text[i]);
  }
  return '$output원';
}
