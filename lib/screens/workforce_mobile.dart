import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/workforce_models.dart';
import '../state/app_state.dart';
import '../widgets/cache_notice.dart';
import '../widgets/empty_state.dart';
import '../widgets/panel.dart';
import '../widgets/responsive_wrap_grid.dart';
import '../widgets/stat_card.dart';

class WorkforceScreen extends StatelessWidget {
  const WorkforceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 5,
      child: Column(
        children: [
          _WorkforceHeader(),
          Expanded(
            child: TabBarView(
              children: [
                _DashboardTab(),
                _CalendarTab(),
                _ShiftsTab(),
                _PayslipsTab(),
                _EmployeesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkforceHeader extends StatelessWidget {
  const _WorkforceHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('인력 관리',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: Color(0xFF0F172A))),
          SizedBox(height: 4),
          Text('근무 일정, 직원, 급여를 관리합니다.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
          SizedBox(height: 12),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: '대시보드'),
              Tab(text: '캘린더'),
              Tab(text: '근무'),
              Tab(text: '급여'),
              Tab(text: '직원'),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashboardTab extends StatefulWidget {
  const _DashboardTab();

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  WorkforceDashboardData? _dashboard;
  List<Workplace> _workplaces = const [];
  bool _loading = true;
  String _error = '';
  bool _fromCache = false;
  DateTime? _cachedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final appState = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final dashboardResponse =
          await appState.fetchMapParsed<WorkforceDashboardData>(
        '/api/workforce/dashboard',
        parser: WorkforceDashboardData.fromJson,
        cacheTtl: const Duration(minutes: 10),
      );
      final workplacesResponse = await appState.fetchMapParsed<List<Workplace>>(
        '/api/workforce/workplaces',
        parser: (json) {
          final raw = json['workplaces'];
          if (raw is! List) return const <Workplace>[];
          return raw
              .whereType<Map>()
              .map(
                  (item) => Workplace.fromJson(Map<String, dynamic>.from(item)))
              .toList(growable: false);
        },
        cacheTtl: const Duration(minutes: 10),
      );
      if (!mounted) return;
      setState(() {
        _dashboard = dashboardResponse.data;
        _workplaces = workplacesResponse.data;
        _fromCache =
            dashboardResponse.fromCache || workplacesResponse.fromCache;
        _cachedAt = dashboardResponse.cachedAt ?? workplacesResponse.cachedAt;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _editWorkplace({Workplace? workplace}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        String name = workplace?.name ?? '';
        String shopNo = workplace?.shopNo ?? '';
        String payType = workplace?.payType.isNotEmpty == true
            ? workplace!.payType
            : 'hourly';
        String payCycle = workplace?.payCycle.isNotEmpty == true
            ? workplace!.payCycle
            : 'monthly';
        int payday = workplace?.payday ?? 10;
        bool isActive = workplace?.isActive ?? true;
        return AlertDialog(
          title: Text(workplace == null ? '근무지 추가' : '근무지 수정'),
          content: StatefulBuilder(
            builder: (context, setModalState) => SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                        initialValue: name,
                        decoration: const InputDecoration(labelText: '근무지명'),
                        onChanged: (value) => name = value),
                    TextFormField(
                        initialValue: shopNo,
                        decoration: const InputDecoration(labelText: '지점 번호'),
                        onChanged: (value) => shopNo = value),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: payType,
                            decoration:
                                const InputDecoration(labelText: '급여 타입'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'hourly', child: Text('시급')),
                              DropdownMenuItem(
                                  value: 'daily', child: Text('일급')),
                              DropdownMenuItem(
                                  value: 'monthly', child: Text('월급')),
                            ],
                            onChanged: (value) =>
                                setModalState(() => payType = value ?? payType),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: payCycle,
                            decoration:
                                const InputDecoration(labelText: '급여 주기'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'weekly', child: Text('주급')),
                              DropdownMenuItem(
                                  value: 'biweekly', child: Text('격주')),
                              DropdownMenuItem(
                                  value: 'monthly', child: Text('월급')),
                            ],
                            onChanged: (value) => setModalState(
                                () => payCycle = value ?? payCycle),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: payday.toString(),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: '급여일'),
                            onChanged: (value) =>
                                payday = int.tryParse(value) ?? payday,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('활성'),
                            value: isActive,
                            onChanged: (value) =>
                                setModalState(() => isActive = value),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소')),
            FilledButton(
              onPressed: () async {
                try {
                  final body = <String, dynamic>{
                    'name': name.trim(),
                    'shop_no': shopNo.trim(),
                    'pay_type': payType,
                    'pay_cycle': payCycle,
                    'payday': payday,
                    'is_active': isActive,
                    'pay_rule': {
                      'default_break_minutes':
                          workplace?.payRule?.defaultBreakMinutes ?? 0
                    },
                    'tax_rule': {
                      'preset': workplace?.taxRule?.preset ?? 'none',
                      'custom_rate': workplace?.taxRule?.customRate ?? 0,
                      'apply_unit': workplace?.taxRule?.applyUnit ?? 'monthly',
                    },
                  };
                  final appState = context.read<AppState>();
                  if (workplace == null) {
                    await appState.postJson('/api/workforce/workplaces',
                        body: body);
                  } else {
                    await appState.postJson(
                        '/api/workforce/workplaces/${workplace.id}',
                        method: 'PATCH',
                        body: body);
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text(error.toString())));
                  }
                }
              },
              child: Text(workplace == null ? '저장' : '수정'),
            ),
          ],
        );
      },
    );
    if (saved == true) await _load();
  }

  Future<void> _deleteWorkplace(Workplace workplace) async {
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('근무지 삭제'),
        content: Text('"${workplace.name}" 근무지를 삭제할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await appState.postJson('/api/workforce/workplaces/${workplace.id}',
          method: 'DELETE');
      await _load();
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return EmptyState(
          title: '인력 대시보드를 불러오지 못했습니다.',
          message: _error,
          action: FilledButton(onPressed: _load, child: const Text('다시 시도')));
    }
    final data = _dashboard;
    if (data == null) {
      return EmptyState(
          title: '데이터 없음',
          action: FilledButton(onPressed: _load, child: const Text('새로고침')));
    }

    final workplacesById = {
      for (final workplace in _workplaces) workplace.id: workplace
    };
    final s = data.summary;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_fromCache && _cachedAt != null) ...[
            CacheNotice(cachedAt: _cachedAt),
            const SizedBox(height: 12),
          ],
          Text(
              '이번 달 (${data.period['from_date'] ?? ''} ~ ${data.period['to_date'] ?? ''})',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
          const SizedBox(height: 8),
          _MetricGrid(cards: [
            StatCard(
                label: '세전 급여', value: _won(s.totalGrossPay), accent: true),
            StatCard(label: '세후 급여', value: _won(s.totalNetPay)),
            StatCard(
                label: '총 근무시간',
                value: '${s.totalWorkedHours.toStringAsFixed(1)}h'),
            StatCard(
                label: '근무지 수',
                value: '${_workplaces.length}곳',
                sub: '최저시급 ${_won(data.minimumWage)}원'),
          ]),
          const SizedBox(height: 16),
          Panel(
            title: '근무지 관리',
            subtitle: '추가 / 수정 / 삭제',
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                      onPressed: () => _editWorkplace(),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('근무지 추가')),
                ),
                const SizedBox(height: 12),
                if (_workplaces.isEmpty)
                  const Text('등록된 근무지가 없습니다.',
                      style: TextStyle(color: Color(0xFF64748B)))
                else
                  ..._workplaces.map((workplace) {
                    final full = workplacesById[workplace.id] ?? workplace;
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: const BoxDecoration(
                          border: Border(
                              bottom: BorderSide(color: Color(0xFFE2E8F0)))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                  child: Text(full.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700))),
                              _Tag(full.isActive ? '활성' : '비활성',
                                  color: full.isActive
                                      ? const Color(0xFF0D9488)
                                      : const Color(0xFF94A3B8)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                              '${full.payType} · ${full.payCycle} · 급여일 ${full.payday}일',
                              style: const TextStyle(
                                  color: Color(0xFF64748B), fontSize: 12)),
                          if (full.shopNo.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text('지점번호 ${full.shopNo}',
                                style: const TextStyle(
                                    color: Color(0xFF94A3B8), fontSize: 12)),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              TextButton.icon(
                                  onPressed: () =>
                                      _editWorkplace(workplace: full),
                                  icon:
                                      const Icon(Icons.edit_outlined, size: 16),
                                  label: const Text('편집')),
                              TextButton.icon(
                                  onPressed: () => _deleteWorkplace(full),
                                  icon: const Icon(Icons.delete_outline,
                                      size: 16),
                                  label: const Text('삭제')),
                              const Spacer(),
                              Text(
                                  full.payRule?.hourlyWage != null
                                      ? '${_won(full.payRule!.hourlyWage!)}원/h'
                                      : '시급 미설정',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('적용 기준 ${_won(data.minimumWage)}원/시간',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
        ],
      ),
    );
  }
}

class _CalendarTab extends StatefulWidget {
  const _CalendarTab();

  @override
  State<_CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<_CalendarTab> {
  late DateTime _selectedMonth;
  int? _workplaceId;
  List<Workplace> _workplaces = const [];
  WorkloadCalendarData? _data;
  bool _loading = true;
  String _error = '';
  bool _fromCache = false;
  DateTime? _cachedAt;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _load();
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked == null) return;
    setState(() => _selectedMonth = DateTime(picked.year, picked.month));
    await _load();
  }

  Future<void> _load() async {
    final appState = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final workplacesResponse = await appState.fetchMapParsed<List<Workplace>>(
        '/api/workforce/workplaces',
        parser: _parseWorkplaces,
      );
      final calendarResponse =
          await appState.fetchMapParsed<WorkloadCalendarData>(
        '/api/workforce/calendar',
        params: {
          'year': _selectedMonth.year,
          'month': _selectedMonth.month,
          if (_workplaceId != null) 'workplace_id': _workplaceId
        },
        parser: WorkloadCalendarData.fromJson,
      );
      if (!mounted) return;
      setState(() {
        _workplaces = workplacesResponse.data;
        _data = calendarResponse.data;
        _fromCache = workplacesResponse.fromCache || calendarResponse.fromCache;
        _cachedAt = workplacesResponse.cachedAt ?? calendarResponse.cachedAt;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return EmptyState(
          title: '근무 캘린더를 불러오지 못했습니다.',
          message: _error,
          action: FilledButton(onPressed: _load, child: const Text('다시 시도')));
    }
    final data = _data;
    if (data == null) {
      return EmptyState(
          title: '캘린더 데이터가 없습니다.',
          action: FilledButton(onPressed: _load, child: const Text('새로고침')));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                  child: Text('${data.year}년 ${data.month}월 근무',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16))),
              OutlinedButton.icon(
                  onPressed: _pickMonth,
                  icon: const Icon(Icons.tune_outlined, size: 16),
                  label: const Text('월 선택')),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  value: _workplaceId,
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('전체 근무지')),
                    ..._workplaces.map((workplace) => DropdownMenuItem<int?>(
                        value: workplace.id, child: Text(workplace.name))),
                  ],
                  onChanged: (value) async {
                    setState(() => _workplaceId = value);
                    await _load();
                  },
                ),
              ),
              if (_fromCache && _cachedAt != null)
                CacheNotice(cachedAt: _cachedAt),
            ],
          ),
          const SizedBox(height: 12),
          _MetricGrid(cards: [
            StatCard(
                label: '세전 급여',
                value: _won(data.summary.grossPay),
                accent: true),
            StatCard(label: '공제', value: _won(data.summary.taxDeduction)),
            StatCard(label: '세후 급여', value: _won(data.summary.netPay)),
            StatCard(
                label: '근무시간',
                value: '${data.summary.workedHours.toStringAsFixed(1)}h'),
            StatCard(label: '근무지 수', value: '${data.summary.workplaceCount}곳'),
          ]),
          const SizedBox(height: 16),
          Panel(
            title: '일자별 근무 현황',
            subtitle: '근무가 있는 날만 표시',
            child: data.days.isEmpty
                ? const Text('이 기간에 등록된 시프트가 없습니다.',
                    style: TextStyle(color: Color(0xFF64748B)))
                : Column(
                    children: data.days
                        .map((day) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(_formatWeekday(day.date)),
                              subtitle: Text(
                                  '${day.shiftCount}건 · ${day.workedHours.toStringAsFixed(1)}h'),
                              trailing: Text(_won(day.grossPay),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                            ))
                        .toList(growable: false),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ShiftsTab extends StatefulWidget {
  const _ShiftsTab();

  @override
  State<_ShiftsTab> createState() => _ShiftsTabState();
}

class _ShiftsTabState extends State<_ShiftsTab> {
  late DateTime _fromDate;
  late DateTime _toDate;
  int? _workplaceId;
  int? _employeeId;
  List<Workplace> _workplaces = const [];
  List<Employee> _employees = const [];
  List<ShiftRecord> _shifts = const [];
  List<ShiftPreset> _presets = const [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final range = _currentMonthRange();
    _fromDate = range.from;
    _toDate = range.to;
    _load();
  }

  Future<void> _load() async {
    final appState = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final workplacesResponse = await appState.fetchMapParsed<List<Workplace>>(
        '/api/workforce/workplaces',
        parser: _parseWorkplaces,
      );
      final employeesResponse = await appState.fetchMapParsed<List<Employee>>(
        '/api/workforce/employees',
        params: const {'is_active': true},
        parser: _parseEmployees,
      );
      final shiftsResponse = await appState.fetchMapParsed<List<ShiftRecord>>(
        '/api/workforce/shifts',
        params: {
          'from_date': _formatDate(_fromDate),
          'to_date': _formatDate(_toDate),
          if (_workplaceId != null) 'workplace_id': _workplaceId,
          if (_employeeId != null) 'employee_id': _employeeId
        },
        parser: _parseShifts,
      );
      final presetsResponse = await appState.fetchMapParsed<List<ShiftPreset>>(
        '/api/workforce/presets',
        params: {if (_workplaceId != null) 'workplace_id': _workplaceId},
        parser: _parsePresets,
      );
      if (!mounted) return;
      setState(() {
        _workplaces = workplacesResponse.data;
        _employees = employeesResponse.data;
        _shifts = shiftsResponse.data;
        _presets = presetsResponse.data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return EmptyState(
          title: '근무 데이터를 불러오지 못했습니다.',
          message: _error,
          action: FilledButton(onPressed: _load, child: const Text('다시 시도')));
    }
    final totalMinutes =
        _shifts.fold<int>(0, (sum, shift) => sum + _workedMinutes(shift));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(
                      '근무 기록 (${_formatDate(_fromDate)} ~ ${_formatDate(_toDate)})',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16))),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2024, 1, 1),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDateRange:
                          DateTimeRange(start: _fromDate, end: _toDate));
                  if (picked == null) return;
                  setState(() {
                    _fromDate = picked.start;
                    _toDate = picked.end;
                  });
                  await _load();
                },
                icon: const Icon(Icons.date_range_outlined, size: 16),
                label: const Text('기간'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  value: _workplaceId,
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('전체 근무지')),
                    ..._workplaces.map((workplace) => DropdownMenuItem<int?>(
                        value: workplace.id, child: Text(workplace.name)))
                  ],
                  onChanged: (value) async {
                    setState(() {
                      _workplaceId = value;
                      _employeeId = null;
                    });
                    await _load();
                  },
                ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  value: _employeeId,
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('전체 직원')),
                    ..._employees.map((employee) => DropdownMenuItem<int?>(
                        value: employee.id, child: Text(employee.name)))
                  ],
                  onChanged: (value) async {
                    setState(() => _employeeId = value);
                    await _load();
                  },
                ),
              ),
              FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('새로고침')),
            ],
          ),
          const SizedBox(height: 12),
          _MetricGrid(cards: [
            StatCard(label: '근무 건수', value: '${_shifts.length}건', accent: true),
            StatCard(
                label: '총 근무시간',
                value: '${(totalMinutes / 60).toStringAsFixed(1)}h'),
            StatCard(label: '템플릿 수', value: '${_presets.length}개'),
          ]),
          const SizedBox(height: 16),
          Panel(
            title: '근무 목록',
            subtitle: '최근 순',
            child: _shifts.isEmpty
                ? const Text('등록된 근무가 없습니다.',
                    style: TextStyle(color: Color(0xFF64748B)))
                : Column(
                    children: _shifts
                        .map((shift) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                  '${_formatWeekday(shift.shiftDate)} · ${timePart(shift.startAt)}-${timePart(shift.endAt)}'),
                              subtitle: Text(
                                  '${shift.workplaceName}${shift.employeeName?.isNotEmpty == true ? ' · ${shift.employeeName}' : ''}'),
                              trailing: Text(
                                  _won(_adjustmentTotal(shift.adjustments)),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                            ))
                        .toList(growable: false)),
          ),
          const SizedBox(height: 16),
          Panel(
            title: '근무 템플릿',
            subtitle: '적용 가능한 템플릿',
            child: _presets.isEmpty
                ? const Text('등록된 템플릿이 없습니다.',
                    style: TextStyle(color: Color(0xFF64748B)))
                : Column(
                    children: _presets
                        .map((preset) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(preset.name),
                              subtitle: Text(
                                  '${preset.workplaceName} · ${preset.startTime}~${preset.endTime}'),
                              trailing: const Icon(Icons.chevron_right_outlined,
                                  color: Color(0xFF94A3B8)),
                            ))
                        .toList(growable: false)),
          ),
        ],
      ),
    );
  }
}

class _PayslipsTab extends StatefulWidget {
  const _PayslipsTab();

  @override
  State<_PayslipsTab> createState() => _PayslipsTabState();
}

class _PayslipsTabState extends State<_PayslipsTab> {
  late DateTime _fromDate;
  late DateTime _toDate;
  int? _workplaceId;
  int? _employeeId;
  List<Workplace> _workplaces = const [];
  List<Employee> _employees = const [];
  WorkforcePeriodData? _data;
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final range = _currentMonthRange();
    _fromDate = range.from;
    _toDate = range.to;
    _load();
  }

  Future<void> _load() async {
    final appState = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final workplacesResponse = await appState.fetchMapParsed<List<Workplace>>(
        '/api/workforce/workplaces',
        parser: _parseWorkplaces,
      );
      final employeesResponse = await appState.fetchMapParsed<List<Employee>>(
        '/api/workforce/employees',
        params: const {'is_active': true},
        parser: _parseEmployees,
      );
      final payslipsResponse =
          await appState.fetchMapParsed<WorkforcePeriodData>(
        '/api/workforce/payslips',
        params: {
          'from_date': _formatDate(_fromDate),
          'to_date': _formatDate(_toDate),
          if (_workplaceId != null) 'workplace_id': _workplaceId,
          if (_employeeId != null) 'employee_id': _employeeId
        },
        parser: WorkforcePeriodData.fromJson,
      );
      if (!mounted) return;
      setState(() {
        _workplaces = workplacesResponse.data;
        _employees = employeesResponse.data;
        _data = payslipsResponse.data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return EmptyState(
          title: '급여 명세를 불러오지 못했습니다.',
          message: _error,
          action: FilledButton(onPressed: _load, child: const Text('다시 시도')));
    }
    final data = _data;
    if (data == null) {
      return EmptyState(
          title: '급여 데이터가 없습니다.',
          action: FilledButton(onPressed: _load, child: const Text('새로고침')));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const Text('급여 명세',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  value: _workplaceId,
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('전체 근무지')),
                    ..._workplaces.map((workplace) => DropdownMenuItem<int?>(
                        value: workplace.id, child: Text(workplace.name)))
                  ],
                  onChanged: (value) async {
                    setState(() {
                      _workplaceId = value;
                      _employeeId = null;
                    });
                    await _load();
                  },
                ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  value: _employeeId,
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('전체 직원')),
                    ..._employees.map((employee) => DropdownMenuItem<int?>(
                        value: employee.id, child: Text(employee.name)))
                  ],
                  onChanged: (value) async {
                    setState(() => _employeeId = value);
                    await _load();
                  },
                ),
              ),
              FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.calculate_outlined, size: 16),
                  label: const Text('계산')),
            ],
          ),
          const SizedBox(height: 12),
          _MetricGrid(cards: [
            StatCard(
                label: '세전 급여',
                value: _won(data.summary.grossPay),
                accent: true),
            StatCard(label: '공제', value: _won(data.summary.taxDeduction)),
            StatCard(label: '세후 급여', value: _won(data.summary.netPay)),
            StatCard(
                label: '근무시간',
                value: '${data.summary.workedHours.toStringAsFixed(1)}h'),
            StatCard(label: '근무지 수', value: '${data.summary.workplaceCount}곳'),
          ]),
          const SizedBox(height: 16),
          if (data.workplaces.isEmpty)
            const EmptyState(title: '기간에 산출된 급여가 없습니다.')
          else
            ...data.workplaces.map((entry) => Panel(
                  title: entry.workplace.name,
                  subtitle:
                      '${entry.workplace.payType} / ${entry.workplace.payCycle} / 급여일 ${entry.workplace.payday}일',
                  child: Column(
                    children: [
                      _MetricGrid(cards: [
                        StatCard(
                            label: '기본급', value: _won(entry.totals.regularPay)),
                        StatCard(
                            label: '가산합계',
                            value: _won(entry.totals.nightPremium +
                                entry.totals.overtimePremium +
                                entry.totals.holidayPremium)),
                        StatCard(
                            label: '주휴수당',
                            value: _won(entry.totals.weeklyHolidayPay)),
                        StatCard(
                            label: '세후',
                            value: _won(entry.totals.netPay),
                            accent: true),
                      ]),
                      const SizedBox(height: 12),
                      ...entry.lineItems.map((item) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(item.label),
                            subtitle: Text(item.date),
                            trailing: Text(_won(item.amount),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                          )),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

class _EmployeesTab extends StatefulWidget {
  const _EmployeesTab();

  @override
  State<_EmployeesTab> createState() => _EmployeesTabState();
}

class _EmployeesTabState extends State<_EmployeesTab> {
  List<Employee>? _list;
  bool _loading = true;
  String _error = '';
  String _query = '';
  int? _workplaceId;
  String _activeFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final appState = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final response = await appState.fetchMapParsed(
        '/api/workforce/employees',
        params: {
          if (_workplaceId != null) 'workplace_id': _workplaceId,
          if (_query.trim().isNotEmpty) 'query': _query.trim(),
          if (_activeFilter != 'all') 'is_active': _activeFilter == 'active',
        },
        parser: _parseEmployees,
        cacheTtl: const Duration(minutes: 10),
      );
      if (!mounted) return;
      setState(() {
        _list = response.data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<List<Workplace>> _loadWorkplaces() async {
    final response = await context
        .read<AppState>()
        .fetchMapParsed<List<Workplace>>('/api/workforce/workplaces',
            parser: _parseWorkplaces);
    return response.data;
  }

  Future<void> _editEmployee({Employee? employee}) async {
    final workplaces = await _loadWorkplaces();
    if (!mounted) return;
    if (workplaces.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('먼저 근무지를 등록하세요.')));
      return;
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        int workplaceId = employee?.workplaceId ?? workplaces.first.id;
        String name = employee?.name ?? '';
        String employeeNo = employee?.employeeNo ?? '';
        String role = employee?.role ?? '';
        String employmentType = employee?.employmentType.isNotEmpty == true
            ? employee!.employmentType
            : 'part_time';
        String joinedOn = employee?.joinedOn ?? '';
        String resignedOn = employee?.resignedOn ?? '';
        String phone = employee?.phone ?? '';
        String hourlyWage = employee?.hourlyWage?.toString() ?? '';
        String taxPreset = employee?.taxPreset.isNotEmpty == true
            ? employee!.taxPreset
            : 'inherit';
        String taxRate = employee?.taxCustomRate.toString() ?? '0';
        String memo = employee?.memo ?? '';
        String linkedAuthUserId = employee?.linkedAuthUserId?.toString() ?? '';
        bool isActive = employee?.isActive ?? true;
        return AlertDialog(
          title: Text(employee == null ? '직원 추가' : '직원 수정'),
          content: StatefulBuilder(
            builder: (context, setModalState) => SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: workplaceId,
                      decoration: const InputDecoration(labelText: '근무지'),
                      items: workplaces
                          .map((workplace) => DropdownMenuItem(
                              value: workplace.id, child: Text(workplace.name)))
                          .toList(growable: false),
                      onChanged: (value) => setModalState(
                          () => workplaceId = value ?? workplaceId),
                    ),
                    TextFormField(
                        initialValue: name,
                        decoration: const InputDecoration(labelText: '이름'),
                        onChanged: (value) => name = value),
                    TextFormField(
                        initialValue: employeeNo,
                        decoration: const InputDecoration(labelText: '사원번호'),
                        onChanged: (value) => employeeNo = value),
                    TextFormField(
                        initialValue: role,
                        decoration: const InputDecoration(labelText: '직책'),
                        onChanged: (value) => role = value),
                    DropdownButtonFormField<String>(
                      initialValue: employmentType,
                      decoration: const InputDecoration(labelText: '고용형태'),
                      items: const [
                        DropdownMenuItem(
                            value: 'part_time', child: Text('파트타임')),
                        DropdownMenuItem(value: 'full_time', child: Text('정규')),
                        DropdownMenuItem(value: 'contract', child: Text('계약')),
                        DropdownMenuItem(value: 'daily', child: Text('일용')),
                      ],
                      onChanged: (value) => setModalState(
                          () => employmentType = value ?? employmentType),
                    ),
                    Row(
                      children: [
                        Expanded(
                            child: TextFormField(
                                initialValue: joinedOn,
                                decoration:
                                    const InputDecoration(labelText: '입사일'),
                                onChanged: (value) => joinedOn = value)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: TextFormField(
                                initialValue: resignedOn,
                                decoration:
                                    const InputDecoration(labelText: '퇴사일'),
                                onChanged: (value) => resignedOn = value)),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                            child: TextFormField(
                                initialValue: phone,
                                decoration:
                                    const InputDecoration(labelText: '연락처'),
                                onChanged: (value) => phone = value)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: TextFormField(
                                initialValue: hourlyWage,
                                keyboardType: TextInputType.number,
                                decoration:
                                    const InputDecoration(labelText: '시급'),
                                onChanged: (value) => hourlyWage = value)),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: taxPreset,
                            decoration:
                                const InputDecoration(labelText: '세금 프리셋'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'inherit', child: Text('상속')),
                              DropdownMenuItem(
                                  value: 'none', child: Text('없음')),
                              DropdownMenuItem(
                                  value: 'four_insurance',
                                  child: Text('4대보험형')),
                              DropdownMenuItem(
                                  value: 'freelancer', child: Text('프리랜서형')),
                              DropdownMenuItem(
                                  value: 'custom', child: Text('직접입력')),
                            ],
                            onChanged: (value) => setModalState(
                                () => taxPreset = value ?? taxPreset),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            initialValue: taxRate,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration:
                                const InputDecoration(labelText: '세율(%)'),
                            onChanged: (value) => taxRate = value,
                          ),
                        ),
                      ],
                    ),
                    TextFormField(
                        initialValue: linkedAuthUserId,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: '연결 계정 ID'),
                        onChanged: (value) => linkedAuthUserId = value),
                    TextFormField(
                        initialValue: memo,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: '메모'),
                        onChanged: (value) => memo = value),
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: isActive,
                        onChanged: (value) =>
                            setModalState(() => isActive = value),
                        title: const Text('재직 중')),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소')),
            FilledButton(
              onPressed: () async {
                try {
                  await context.read<AppState>().postJson(
                    employee == null
                        ? '/api/workforce/employees'
                        : '/api/workforce/employees/${employee.id}',
                    method: employee == null ? 'POST' : 'PATCH',
                    body: {
                      'workplace_id': workplaceId,
                      'name': name.trim(),
                      'employee_no': employeeNo.trim(),
                      'role': role.trim(),
                      'employment_type': employmentType,
                      'joined_on': joinedOn.trim(),
                      'resigned_on': resignedOn.trim(),
                      'phone': phone.trim(),
                      'hourly_wage': hourlyWage.trim().isEmpty
                          ? null
                          : int.tryParse(hourlyWage.trim()),
                      'tax_preset': taxPreset,
                      'tax_custom_rate': double.tryParse(taxRate.trim()) ?? 0,
                      'memo': memo.trim(),
                      'linked_auth_user_id': linkedAuthUserId.trim().isEmpty
                          ? null
                          : int.tryParse(linkedAuthUserId.trim()),
                      'is_active': isActive,
                    },
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text(error.toString())));
                  }
                }
              },
              child: Text(employee == null ? '저장' : '수정'),
            ),
          ],
        );
      },
    );
    if (saved == true) await _load();
  }

  Future<void> _showEmployeeDetail(Employee employee) async {
    try {
      final appState = context.read<AppState>();
      final detailResponse = await appState.fetchMapParsed<EmployeeDetailData>(
        '/api/workforce/employees/${employee.id}',
        parser: EmployeeDetailData.fromJson,
      );
      final auditLogsResponse =
          await appState.fetchMapParsed<List<EmployeeAuditLog>>(
        '/api/workforce/employees/${employee.id}/audit-logs',
        parser: (json) {
          final raw = json['logs'];
          if (raw is! List) return const <EmployeeAuditLog>[];
          return raw
              .whereType<Map>()
              .map((item) =>
                  EmployeeAuditLog.fromJson(Map<String, dynamic>.from(item)))
              .toList(growable: false);
        },
      );
      final payslipResponse =
          await appState.fetchMapParsed<EmployeePayslipData>(
        '/api/workforce/employees/${employee.id}/payslips',
        params: _currentMonthRangeAsParams(),
        parser: EmployeePayslipData.fromJson,
      );
      if (!mounted) return;
      final detail = detailResponse.data;
      final auditLogs = auditLogsResponse.data;
      final payslip = payslipResponse.data;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(detail.employee.name),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${detail.employee.workplaceName} · ${detail.employee.role.isEmpty ? '직원' : detail.employee.role}',
                      style: const TextStyle(
                          color: Color(0xFF64748B), fontSize: 12)),
                  const SizedBox(height: 12),
                  _MetricGrid(cards: [
                    StatCard(
                        label: '시급',
                        value: _won(detail.employee.hourlyWage ?? 0)),
                    StatCard(
                        label: '재직',
                        value: detail.employee.isActive ? '활성' : '비활성'),
                    StatCard(label: '세금', value: detail.employee.taxPreset),
                    StatCard(
                        label: '연락처',
                        value: detail.employee.phone.isNotEmpty
                            ? detail.employee.phone
                            : '-'),
                  ]),
                  const SizedBox(height: 12),
                  if (payslip.workplaces.isNotEmpty) ...[
                    const Text('이번 달 급여',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    _MetricGrid(cards: [
                      StatCard(
                          label: '세전', value: _won(payslip.summary.grossPay)),
                      StatCard(
                          label: '공제',
                          value: _won(payslip.summary.taxDeduction)),
                      StatCard(
                          label: '세후',
                          value: _won(payslip.summary.netPay),
                          accent: true),
                    ]),
                  ],
                  if (detail.recentShifts.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('최근 근무',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    ...detail.recentShifts.map((shift) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(_formatWeekday(shift.shiftDate)),
                          subtitle: Text(
                              '${timePart(shift.startAt)} ~ ${timePart(shift.endAt)} · ${shift.workplaceName}'),
                        )),
                  ],
                  if (auditLogs.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('변경 이력',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    ...auditLogs.map((log) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(log.action),
                          subtitle: Text(log.createdAt?.toString() ?? ''),
                        )),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('닫기')),
            TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _toggleActive(detail.employee);
                },
                child: Text(detail.employee.isActive ? '비활성화' : '활성화')),
            TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _deleteEmployee(detail.employee);
                },
                child: const Text('삭제')),
            TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _editEmployee(employee: detail.employee);
                },
                child: const Text('수정')),
            FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _openPayPreview(detail.employee);
                },
                child: const Text('급여 미리보기')),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _openPayPreview(Employee employee) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        String startAt = '09:00';
        String endAt = '18:00';
        int breakMinutes = 60;
        String leaveType = 'none';
        String holidayType = 'none';
        int extraAmount = 0;
        int deductionAmount = 0;
        EmployeePayPreviewData? preview;
        String? error;
        late StateSetter setModalState;
        return AlertDialog(
          title: Text('${employee.name} 급여 미리보기'),
          content: StatefulBuilder(
            builder: (context, stateSetter) {
              setModalState = stateSetter;
              return SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: TextFormField(
                                  initialValue: startAt,
                                  decoration:
                                      const InputDecoration(labelText: '시작'),
                                  onChanged: (value) => startAt = value)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: TextFormField(
                                  initialValue: endAt,
                                  decoration:
                                      const InputDecoration(labelText: '종료'),
                                  onChanged: (value) => endAt = value)),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                              child: TextFormField(
                                  initialValue: breakMinutes.toString(),
                                  keyboardType: TextInputType.number,
                                  decoration:
                                      const InputDecoration(labelText: '휴게(분)'),
                                  onChanged: (value) => breakMinutes =
                                      int.tryParse(value) ?? breakMinutes)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: TextFormField(
                                  initialValue: extraAmount.toString(),
                                  keyboardType: TextInputType.number,
                                  decoration:
                                      const InputDecoration(labelText: '추가 지급'),
                                  onChanged: (value) => extraAmount =
                                      int.tryParse(value) ?? extraAmount)),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                              child: TextFormField(
                                  initialValue: deductionAmount.toString(),
                                  keyboardType: TextInputType.number,
                                  decoration:
                                      const InputDecoration(labelText: '추가 차감'),
                                  onChanged: (value) => deductionAmount =
                                      int.tryParse(value) ?? deductionAmount)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: leaveType,
                              decoration:
                                  const InputDecoration(labelText: '휴무 타입'),
                              items: const [
                                DropdownMenuItem(
                                    value: 'none', child: Text('정상근무')),
                                DropdownMenuItem(
                                    value: 'vacation', child: Text('휴가')),
                                DropdownMenuItem(
                                    value: 'absent', child: Text('결근')),
                                DropdownMenuItem(
                                    value: 'day_off', child: Text('휴무')),
                                DropdownMenuItem(
                                    value: 'paid_day_off', child: Text('유급휴무')),
                                DropdownMenuItem(
                                    value: 'substitute', child: Text('대타')),
                              ],
                              onChanged: (value) => setModalState(
                                  () => leaveType = value ?? leaveType),
                            ),
                          ),
                        ],
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: holidayType,
                        decoration: const InputDecoration(labelText: '휴일 타입'),
                        items: const [
                          DropdownMenuItem(value: 'none', child: Text('일반일')),
                          DropdownMenuItem(value: 'weekend', child: Text('주말')),
                          DropdownMenuItem(value: 'public', child: Text('공휴일')),
                          DropdownMenuItem(
                              value: 'custom', child: Text('기타 휴일')),
                        ],
                        onChanged: (value) => setModalState(
                            () => holidayType = value ?? holidayType),
                      ),
                      if (error != null)
                        Text(error!, style: const TextStyle(color: Colors.red)),
                      if (preview != null) ...[
                        const SizedBox(height: 12),
                        _MetricGrid(cards: [
                          StatCard(
                              label: '세전',
                              value: _won(preview!.preview.grossPay),
                              accent: true),
                          StatCard(
                              label: '세금',
                              value: _won(preview!.preview.taxEstimate)),
                          StatCard(
                              label: '세후',
                              value: _won(preview!.preview.netEstimate)),
                        ]),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('닫기')),
            FilledButton(
              onPressed: () async {
                try {
                  final payload = await context.read<AppState>().postJson(
                    '/api/workforce/employees/${employee.id}/pay-preview',
                    body: {
                      'start_at': '${_formatDate(DateTime.now())}T$startAt',
                      'end_at': '${_formatDate(DateTime.now())}T$endAt',
                      'break_minutes': breakMinutes,
                      'leave_type': leaveType,
                      'holiday_type': holidayType,
                      'adjustments': [
                        if (extraAmount > 0)
                          {
                            'kind': 'extra',
                            'label': '추가 지급',
                            'amount': extraAmount
                          },
                        if (deductionAmount > 0)
                          {
                            'kind': 'deduction',
                            'label': '추가 차감',
                            'amount': deductionAmount
                          },
                      ],
                    },
                  );
                  setModalState(() {
                    preview = EmployeePayPreviewData.fromJson(payload);
                    error = null;
                  });
                } catch (err) {
                  setModalState(() => error = err.toString());
                }
              },
              child: const Text('계산'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteEmployee(Employee employee) async {
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('직원 삭제'),
        content: Text('"${employee.name}" 직원을 삭제할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    try {
      await appState.postJson('/api/workforce/employees/${employee.id}',
          method: 'DELETE');
      await _load();
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _toggleActive(Employee employee) async {
    try {
      await context.read<AppState>().postJson(
          '/api/workforce/employees/${employee.id}',
          method: 'PATCH',
          body: {'is_active': !employee.isActive});
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return EmptyState(
          title: '직원 목록을 불러오지 못했습니다.',
          message: _error,
          action: FilledButton(onPressed: _load, child: const Text('다시 시도')));
    }
    final list = _list ?? const <Employee>[];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const Text('직원 관리',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 160,
                child: TextField(
                  decoration: const InputDecoration(hintText: '검색'),
                  onSubmitted: (value) async {
                    setState(() => _query = value);
                    await _load();
                  },
                ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _activeFilter,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('전체')),
                    DropdownMenuItem(value: 'active', child: Text('재직 중')),
                    DropdownMenuItem(value: 'inactive', child: Text('비활성')),
                  ],
                  onChanged: (value) async {
                    setState(() => _activeFilter = value ?? 'all');
                    await _load();
                  },
                ),
              ),
              FilledButton.icon(
                  onPressed: () => _editEmployee(),
                  icon: const Icon(Icons.person_add_alt_1, size: 16),
                  label: const Text('직원 추가')),
            ],
          ),
          const SizedBox(height: 12),
          _MetricGrid(cards: [
            StatCard(label: '전체 직원', value: '${list.length}명', accent: true),
            StatCard(
                label: '재직 중',
                value:
                    '${list.where((employee) => employee.isActive).length}명'),
            StatCard(
                label: '연결 계정',
                value:
                    '${list.where((employee) => employee.linkedAuthUserId != null).length}명'),
            const StatCard(label: '이번 달 급여', value: '상세에서 확인'),
          ]),
          const SizedBox(height: 16),
          Panel(
            title: '직원 목록',
            subtitle: '탭해서 상세 확인',
            child: list.isEmpty
                ? const Text('등록된 직원이 없습니다.',
                    style: TextStyle(color: Color(0xFF64748B)))
                : Column(
                    children: list
                        .map((emp) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                onTap: () => _showEmployeeDetail(emp),
                                leading: CircleAvatar(
                                  backgroundColor:
                                      const Color.fromRGBO(13, 148, 136, 0.12),
                                  child: Text(
                                      emp.name.isNotEmpty ? emp.name[0] : '?',
                                      style: const TextStyle(
                                          color: Color(0xFF0D9488),
                                          fontWeight: FontWeight.w700)),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                        child: Text(emp.name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700))),
                                    if (!emp.isActive)
                                      const Text('비활성',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF94A3B8))),
                                  ],
                                ),
                                subtitle: Text(
                                    '${emp.workplaceName} · ${emp.role.isEmpty ? '직원' : emp.role}'),
                                trailing: Text(
                                    '${_won(emp.hourlyWage ?? 0)}원/h',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                              ),
                            ))
                        .toList(growable: false),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  final List<Widget> cards;
  const _MetricGrid({required this.cards});

  @override
  Widget build(BuildContext context) {
    return ResponsiveWrapGrid(
      minItemWidth: 280,
      maxColumns: 2,
      children: cards,
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag(this.label, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

List<Workplace> _parseWorkplaces(Map<String, dynamic> json) {
  final raw = json['workplaces'];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((item) => Workplace.fromJson(Map<String, dynamic>.from(item)))
      .toList(growable: false);
}

List<Employee> _parseEmployees(Map<String, dynamic> json) {
  final raw = json['employees'];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((item) => Employee.fromJson(Map<String, dynamic>.from(item)))
      .toList(growable: false);
}

List<ShiftRecord> _parseShifts(Map<String, dynamic> json) {
  final raw = json['shifts'];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((item) => ShiftRecord.fromJson(Map<String, dynamic>.from(item)))
      .toList(growable: false);
}

List<ShiftPreset> _parsePresets(Map<String, dynamic> json) {
  final raw = json['presets'];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((item) => ShiftPreset.fromJson(Map<String, dynamic>.from(item)))
      .toList(growable: false);
}

String _won(num value) {
  final abs = value.abs().round();
  final str = abs.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
    buffer.write(str[i]);
  }
  return value < 0 ? '-${buffer.toString()}' : buffer.toString();
}

String _formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String _formatWeekday(String date) {
  try {
    final dt = DateTime.parse(date);
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return '$date (${days[dt.weekday - 1]})';
  } catch (_) {
    return date;
  }
}

String timePart(String isoText) {
  final idx = isoText.indexOf('T');
  if (idx < 0) return isoText.length >= 5 ? isoText.substring(0, 5) : isoText;
  return isoText.substring(idx + 1, idx + 6);
}

int _adjustmentTotal(List<ShiftAdjustment> adjustments) {
  return adjustments.fold<int>(
      0,
      (sum, item) =>
          item.kind == 'deduction' ? sum - item.amount : sum + item.amount);
}

int _workedMinutes(ShiftRecord shift) {
  final start = DateTime.tryParse(shift.startAt);
  final end = DateTime.tryParse(shift.endAt);
  if (start == null || end == null) {
    return 0;
  }
  final total = end.difference(start).inMinutes - shift.breakMinutes;
  return total < 0 ? 0 : total;
}

class _MonthRange {
  final DateTime from;
  final DateTime to;

  const _MonthRange({required this.from, required this.to});
}

_MonthRange _currentMonthRange() {
  final now = DateTime.now();
  return _MonthRange(
      from: DateTime(now.year, now.month, 1),
      to: DateTime(now.year, now.month, now.day));
}

Map<String, Object?> _currentMonthRangeAsParams() {
  final range = _currentMonthRange();
  return {
    'from_date': _formatDate(range.from),
    'to_date': _formatDate(range.to)
  };
}
