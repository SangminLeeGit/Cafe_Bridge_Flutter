import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/async_request_guard.dart';
import '../models/api_contracts.dart';
import '../models/workforce_models.dart';
import 'payroll_runs.dart';
import '../services/api.dart';
import '../state/app_state.dart';
import '../widgets/cache_notice.dart';
import '../widgets/empty_state.dart';
import '../widgets/panel.dart';
import '../widgets/responsive_wrap_grid.dart';
import '../widgets/stat_card.dart';
import '../widgets/workforce_shift_forms.dart';

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

class _DashboardTabState extends State<_DashboardTab>
    with AsyncRequestGuard<_DashboardTab> {
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
    if (!mounted) return;
    final request = beginAsyncRequest();
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
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      final workplacesResponse = await appState.fetchMapParsed<List<Workplace>>(
        '/api/workforce/workplaces',
        parser: _parseWorkplaces,
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _dashboard = dashboardResponse.data;
        _workplaces = workplacesResponse.data;
        _fromCache =
            dashboardResponse.fromCache || workplacesResponse.fromCache;
        _cachedAt = dashboardResponse.cachedAt ?? workplacesResponse.cachedAt;
        _loading = false;
      });
    } catch (error) {
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _editWorkplace({Workplace? workplace}) async {
    if (!context.read<AppState>().hasOperatorAccess) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final payRule = workplace?.payRule;
        final taxRule = workplace?.taxRule;
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
        String hourlyWage = payRule?.hourlyWage?.toString() ?? '';
        String dailyWage = payRule?.dailyWage?.toString() ?? '';
        String monthlySalary = payRule?.monthlySalary?.toString() ?? '';
        String defaultBreakMinutes =
            payRule?.defaultBreakMinutes.toString() ?? '0';
        String overtimeThreshold =
            payRule?.overtimeDailyThresholdMinutes.toString() ?? '480';
        bool nightEnabled = payRule?.nightEnabled ?? true;
        bool overtimeEnabled = payRule?.overtimeEnabled ?? true;
        bool holidayEnabled = payRule?.holidayEnabled ?? true;
        bool weeklyHolidayEnabled = payRule?.weeklyHolidayEnabled ?? true;
        String weeklyHolidayStartDow =
            payRule?.weeklyHolidayStartDow.toString() ?? '0';
        String weeklyHolidayMinMinutes =
            payRule?.weeklyHolidayMinMinutes.toString() ?? '900';
        String weeklyHolidayMinDays =
            payRule?.weeklyHolidayMinDays.toString() ?? '1';
        String nightMultiplier = payRule?.nightMultiplier.toString() ?? '0.5';
        String overtimeMultiplier =
            payRule?.overtimeMultiplier.toString() ?? '0.5';
        String holidayMultiplierUnder8 =
            payRule?.holidayMultiplierUnder8.toString() ?? '0.5';
        String holidayMultiplierOver8 =
            payRule?.holidayMultiplierOver8.toString() ?? '1.0';
        String taxPreset = taxRule?.preset ?? 'none';
        String taxRate = taxRule?.customRate.toString() ?? '0';
        String taxApplyUnit = taxRule?.applyUnit ?? 'monthly';
        return AlertDialog(
          title: Text(workplace == null ? '근무지 추가' : '근무지 수정'),
          content: StatefulBuilder(
            builder: (context, setModalState) => SizedBox(
              width: 520,
              height: MediaQuery.sizeOf(context).height * 0.68,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    const _FormSectionHeader('급여 기준'),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: hourlyWage,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: '시급 (원)'),
                            onChanged: (value) => hourlyWage = value,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            initialValue: dailyWage,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: '일급 (원)'),
                            onChanged: (value) => dailyWage = value,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: monthlySalary,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: '월급 (원)'),
                            onChanged: (value) => monthlySalary = value,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            initialValue: defaultBreakMinutes,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: '기본 휴게 (분)'),
                            onChanged: (value) => defaultBreakMinutes = value,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: overtimeThreshold,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: '일 연장 기준 (분)'),
                            onChanged: (value) => overtimeThreshold = value,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            initialValue: weeklyHolidayStartDow,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: '주휴 시작요일 (0~6)'),
                            onChanged: (value) => weeklyHolidayStartDow = value,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: weeklyHolidayMinMinutes,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: '주휴 최소시간 (분)'),
                            onChanged: (value) =>
                                weeklyHolidayMinMinutes = value,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            initialValue: weeklyHolidayMinDays,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: '주휴 최소일수'),
                            onChanged: (value) => weeklyHolidayMinDays = value,
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('야간수당 적용'),
                      value: nightEnabled,
                      onChanged: (value) =>
                          setModalState(() => nightEnabled = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('연장수당 적용'),
                      value: overtimeEnabled,
                      onChanged: (value) =>
                          setModalState(() => overtimeEnabled = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('휴일수당 적용'),
                      value: holidayEnabled,
                      onChanged: (value) =>
                          setModalState(() => holidayEnabled = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('주휴수당 적용'),
                      value: weeklyHolidayEnabled,
                      onChanged: (value) =>
                          setModalState(() => weeklyHolidayEnabled = value),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: nightMultiplier,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration:
                                const InputDecoration(labelText: '야간 가산율'),
                            onChanged: (value) => nightMultiplier = value,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            initialValue: overtimeMultiplier,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration:
                                const InputDecoration(labelText: '연장 가산율'),
                            onChanged: (value) => overtimeMultiplier = value,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: holidayMultiplierUnder8,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                                labelText: '휴일 8시간 이하 가산율'),
                            onChanged: (value) =>
                                holidayMultiplierUnder8 = value,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            initialValue: holidayMultiplierOver8,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                                labelText: '휴일 8시간 초과 가산율'),
                            onChanged: (value) =>
                                holidayMultiplierOver8 = value,
                          ),
                        ),
                      ],
                    ),
                    const _FormSectionHeader('세금 기준'),
                    DropdownButtonFormField<String>(
                      initialValue: taxPreset,
                      decoration: const InputDecoration(labelText: '세금 프리셋'),
                      items: const [
                        DropdownMenuItem(value: 'none', child: Text('없음')),
                        DropdownMenuItem(
                            value: 'four_insurance', child: Text('4대보험형')),
                        DropdownMenuItem(
                            value: 'freelancer', child: Text('프리랜서형')),
                        DropdownMenuItem(value: 'custom', child: Text('직접입력')),
                      ],
                      onChanged: (value) =>
                          setModalState(() => taxPreset = value ?? taxPreset),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: taxRate,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                                labelText: '직접 세율 (0~100%)'),
                            onChanged: (value) => taxRate = value,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: taxApplyUnit,
                            decoration:
                                const InputDecoration(labelText: '세금 적용 단위'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'monthly', child: Text('월별')),
                              DropdownMenuItem(
                                  value: 'shift', child: Text('근무별')),
                            ],
                            onChanged: (value) => setModalState(
                                () => taxApplyUnit = value ?? taxApplyUnit),
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
                  int? parseOptionalWage(String value) =>
                      value.trim().isEmpty ? null : int.tryParse(value.trim());
                  final hourlyValue = parseOptionalWage(hourlyWage);
                  final dailyValue = parseOptionalWage(dailyWage);
                  final monthlyValue = parseOptionalWage(monthlySalary);
                  final integerValues = <String, int?>{
                    '기본 휴게시간': int.tryParse(defaultBreakMinutes.trim()),
                    '일 연장 기준': int.tryParse(overtimeThreshold.trim()),
                    '주휴 시작요일': int.tryParse(weeklyHolidayStartDow.trim()),
                    '주휴 최소시간': int.tryParse(weeklyHolidayMinMinutes.trim()),
                    '주휴 최소일수': int.tryParse(weeklyHolidayMinDays.trim()),
                  };
                  final decimalValues = <String, double?>{
                    '야간 가산율': double.tryParse(nightMultiplier.trim()),
                    '연장 가산율': double.tryParse(overtimeMultiplier.trim()),
                    '휴일 8시간 이하 가산율':
                        double.tryParse(holidayMultiplierUnder8.trim()),
                    '휴일 8시간 초과 가산율':
                        double.tryParse(holidayMultiplierOver8.trim()),
                  };
                  final parsedTaxRate = double.tryParse(taxRate.trim());
                  String? validationError;
                  if (name.trim().isEmpty) {
                    validationError = '근무지명을 입력하세요.';
                  } else if ((hourlyWage.trim().isNotEmpty &&
                          (hourlyValue == null || hourlyValue < 0)) ||
                      (dailyWage.trim().isNotEmpty &&
                          (dailyValue == null || dailyValue < 0)) ||
                      (monthlySalary.trim().isNotEmpty &&
                          (monthlyValue == null || monthlyValue < 0))) {
                    validationError = '급여 금액은 0원 이상 정수로 입력하세요.';
                  } else if (integerValues.values
                      .any((value) => value == null || value < 0)) {
                    validationError = '급여 기준은 0 이상의 정수로 입력하세요.';
                  } else if ((int.tryParse(weeklyHolidayStartDow.trim()) ??
                          -1) >
                      6) {
                    validationError = '주휴 시작요일은 0~6으로 입력하세요.';
                  } else if (decimalValues.values.any((value) =>
                      value == null || !value.isFinite || value < 0)) {
                    validationError = '가산율은 0 이상의 숫자로 입력하세요.';
                  } else if (parsedTaxRate == null ||
                      !parsedTaxRate.isFinite ||
                      parsedTaxRate < 0 ||
                      parsedTaxRate > 100) {
                    validationError = '세율은 0~100 사이로 입력하세요.';
                  }
                  if (validationError != null) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(content: Text(validationError)));
                    }
                    return;
                  }
                  final numbers =
                      integerValues.map((key, value) => MapEntry(key, value!));
                  final multipliers =
                      decimalValues.map((key, value) => MapEntry(key, value!));
                  final body = <String, dynamic>{
                    'name': name.trim(),
                    'shop_no': shopNo.trim(),
                    'pay_type': payType,
                    'pay_cycle': payCycle,
                    'payday': payday,
                    'is_active': isActive,
                    'pay_rule': <String, dynamic>{
                      'hourly_wage': hourlyValue,
                      'daily_wage': dailyValue,
                      'monthly_salary': monthlyValue,
                      'default_break_minutes': numbers['기본 휴게시간'],
                      'overtime_daily_threshold_minutes': numbers['일 연장 기준'],
                      'night_enabled': nightEnabled,
                      'overtime_enabled': overtimeEnabled,
                      'holiday_enabled': holidayEnabled,
                      'weekly_holiday_enabled': weeklyHolidayEnabled,
                      'weekly_holiday_start_dow': numbers['주휴 시작요일'],
                      'weekly_holiday_min_minutes': numbers['주휴 최소시간'],
                      'weekly_holiday_min_days': numbers['주휴 최소일수'],
                      'night_multiplier': multipliers['야간 가산율'],
                      'overtime_multiplier': multipliers['연장 가산율'],
                      'holiday_multiplier_under8': multipliers['휴일 8시간 이하 가산율'],
                      'holiday_multiplier_over8': multipliers['휴일 8시간 초과 가산율'],
                    },
                    'tax_rule': {
                      'preset': taxPreset,
                      'custom_rate': parsedTaxRate,
                      'apply_unit': taxApplyUnit,
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
    if (!context.read<AppState>().hasOperatorAccess) return;
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
    final canOperate = context.select<AppState, bool>(
      (state) => state.hasOperatorAccess,
    );
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
          if (!canOperate) ...[
            const SizedBox(height: 12),
            const _WorkforceReadOnlyHint(),
          ],
          const SizedBox(height: 16),
          Panel(
            title: '근무지 관리',
            subtitle: '추가 / 수정 / 삭제',
            child: Column(
              children: [
                if (canOperate)
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                        onPressed: () => _editWorkplace(),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('근무지 추가')),
                  ),
                if (canOperate) const SizedBox(height: 12),
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
                              if (canOperate) ...[
                                TextButton.icon(
                                    onPressed: () =>
                                        _editWorkplace(workplace: full),
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 16),
                                    label: const Text('편집')),
                                TextButton.icon(
                                    onPressed: () => _deleteWorkplace(full),
                                    icon: const Icon(Icons.delete_outline,
                                        size: 16),
                                    label: const Text('삭제')),
                              ],
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

class _CalendarTabState extends State<_CalendarTab>
    with AsyncRequestGuard<_CalendarTab> {
  late DateTime _selectedMonth;
  int? _workplaceId;
  List<Workplace> _workplaces = const [];
  List<Employee> _employees = const [];
  List<ShiftPreset> _presets = const [];
  WorkloadCalendarData? _data;
  bool _loading = true;
  String _error = '';
  bool _fromCache = false;
  DateTime? _cachedAt;
  final Set<String> _selectedDates = <String>{};
  bool _bulkSubmitting = false;
  String _bulkMessage = '';
  String _bulkError = '';

  @override
  void initState() {
    super.initState();
    final now = ApiService.kstNow();
    _selectedMonth = DateTime(now.year, now.month);
    _load();
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2024),
      lastDate: ApiService.kstNow().add(const Duration(days: 60)),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedMonth = DateTime(picked.year, picked.month);
      _selectedDates.clear();
      _bulkMessage = '';
      _bulkError = '';
    });
    await _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final request = beginAsyncRequest();
    final appState = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final workplacesResponse = await appState.fetchMapParsed<List<Workplace>>(
        '/api/workforce/workplaces',
        parser: _parseWorkplaces,
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      final employeesResponse = await appState.fetchMapParsed<List<Employee>>(
        '/api/workforce/employees',
        params: const {'is_active': true},
        parser: _parseEmployees,
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      final presetsResponse = await appState.fetchMapParsed<List<ShiftPreset>>(
        '/api/workforce/presets',
        parser: _parsePresets,
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
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
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _workplaces = workplacesResponse.data;
        _employees = employeesResponse.data;
        _presets = presetsResponse.data;
        _data = calendarResponse.data;
        _fromCache = workplacesResponse.fromCache || calendarResponse.fromCache;
        _cachedAt = workplacesResponse.cachedAt ?? calendarResponse.cachedAt;
        _loading = false;
      });
    } catch (error) {
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openBulkCreate() async {
    if (!context.read<AppState>().hasOperatorAccess) return;
    if (_selectedDates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('달력에서 등록할 날짜를 먼저 선택하세요.')),
      );
      return;
    }
    if (_workplaces.isEmpty || _employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('근무지와 활성 직원을 먼저 등록하세요.')),
      );
      return;
    }

    final sortedDates = _selectedDates.toList()..sort();
    final values = await showDialog<_BulkShiftValues>(
      context: context,
      builder: (dialogContext) => _BulkShiftFormDialog(
        workplaces: _workplaces,
        employees: _employees,
        presets: _presets,
        dates: sortedDates,
      ),
    );
    if (values == null || !mounted) return;

    final appState = context.read<AppState>();
    setState(() {
      _bulkSubmitting = true;
      _bulkMessage = '';
      _bulkError = '';
    });
    try {
      // Use the backend bulk contract so duplicate dates are skipped
      // atomically (skip_existing) instead of failing partway through a
      // client-side loop.
      final result = await appState.postJson(
        '/api/workforce/shifts/bulk',
        body: values.toBulkPayload(sortedDates),
      );
      if (!mounted) return;
      final createdCount = asInt(result['created_count']);
      final skippedDates = (result['skipped_dates'] as List? ?? const [])
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      setState(() {
        _selectedDates.clear();
        _bulkMessage = createdCount == 0
            ? '이미 등록된 근무만 있어 새로 추가하지 않았습니다.'
            : '$createdCount건을 등록했습니다.';
        _bulkError = skippedDates.isEmpty
            ? ''
            : '이미 같은 시간의 근무가 있어 ${skippedDates.length}일을 건너뛰었습니다: ${skippedDates.join(', ')}';
      });
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() => _bulkError = '일괄등록 실패: $error');
      }
    } finally {
      if (mounted) setState(() => _bulkSubmitting = false);
    }
  }

  void _toggleDate(String date) {
    if (!context.read<AppState>().hasOperatorAccess || _bulkSubmitting) return;
    setState(() {
      if (!_selectedDates.add(date)) _selectedDates.remove(date);
      _bulkMessage = '';
      _bulkError = '';
    });
  }

  Widget _buildMonthSelector(WorkloadCalendarData data) {
    final daysInMonth = DateTime(data.year, data.month + 1, 0).day;
    final dayMap = <String, CalendarDay>{
      for (final day in data.days) day.date: day,
    };
    final leading = DateTime(data.year, data.month, 1).weekday - 1;
    final cells = <Widget>[
      for (var index = 0; index < leading; index++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        Builder(
          builder: (context) {
            final date =
                '${data.year.toString().padLeft(4, '0')}-${data.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
            final summary = dayMap[date];
            final selected = _selectedDates.contains(date);
            return InkWell(
              onTap: () => _toggleDate(date),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                constraints: const BoxConstraints(minHeight: 64),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFE6FFFB)
                      : const Color(0xFFF8FAFC),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF0D9488)
                        : const Color(0xFFE2E8F0),
                    width: selected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$day${selected ? ' ✓' : ''}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    Text('근무 ${summary?.shiftCount ?? 0}건',
                        style: const TextStyle(fontSize: 10)),
                    Text('${(summary?.workedHours ?? 0).toStringAsFixed(1)}h',
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFF64748B))),
                  ],
                ),
              ),
            );
          },
        ),
    ];
    return Column(
      children: [
        const Row(
          children: [
            Expanded(
                child: Center(
                    child: Text('월',
                        style: TextStyle(
                            fontSize: 11, color: Color(0xFF64748B))))),
            Expanded(
                child: Center(
                    child: Text('화',
                        style: TextStyle(
                            fontSize: 11, color: Color(0xFF64748B))))),
            Expanded(
                child: Center(
                    child: Text('수',
                        style: TextStyle(
                            fontSize: 11, color: Color(0xFF64748B))))),
            Expanded(
                child: Center(
                    child: Text('목',
                        style: TextStyle(
                            fontSize: 11, color: Color(0xFF64748B))))),
            Expanded(
                child: Center(
                    child: Text('금',
                        style: TextStyle(
                            fontSize: 11, color: Color(0xFF64748B))))),
            Expanded(
                child: Center(
                    child: Text('토',
                        style: TextStyle(
                            fontSize: 11, color: Color(0xFF64748B))))),
            Expanded(
                child: Center(
                    child: Text('일',
                        style: TextStyle(
                            fontSize: 11, color: Color(0xFF64748B))))),
          ],
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 0.82,
          children: cells,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canOperate = context.select<AppState, bool>(
      (state) => state.hasOperatorAccess,
    );
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
            title: '선택 일괄등록',
            subtitle: canOperate
                ? '날짜를 선택한 뒤 동일한 근무 조건을 순차 등록합니다.'
                : '조회 전용 · 날짜 선택과 등록은 operator 권한이 필요합니다.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildMonthSelector(data),
                const SizedBox(height: 12),
                Text(
                  '선택 날짜 ${_selectedDates.length}일',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (_bulkMessage.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(_bulkMessage,
                      style: const TextStyle(color: Color(0xFF0F766E))),
                ],
                if (_bulkError.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(_bulkError,
                      style: const TextStyle(color: Color(0xFFB91C1C))),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _bulkSubmitting || _selectedDates.isEmpty
                            ? null
                            : () => setState(_selectedDates.clear),
                        child: const Text('선택 해제'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: !canOperate || _bulkSubmitting
                            ? null
                            : _openBulkCreate,
                        icon: const Icon(Icons.playlist_add, size: 18),
                        label: Text(_bulkSubmitting ? '등록 중...' : '선택 일괄등록'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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

class _ShiftsTabState extends State<_ShiftsTab>
    with AsyncRequestGuard<_ShiftsTab> {
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
    if (!mounted) return;
    final request = beginAsyncRequest();
    final appState = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final workplacesResponse = await appState.fetchMapParsed<List<Workplace>>(
        '/api/workforce/workplaces',
        parser: _parseWorkplaces,
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      final employeesResponse = await appState.fetchMapParsed<List<Employee>>(
        '/api/workforce/employees',
        params: const {'is_active': true},
        parser: _parseEmployees,
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
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
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      final presetsResponse = await appState.fetchMapParsed<List<ShiftPreset>>(
        '/api/workforce/presets',
        params: {if (_workplaceId != null) 'workplace_id': _workplaceId},
        parser: _parsePresets,
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _workplaces = workplacesResponse.data;
        _employees = employeesResponse.data;
        _shifts = shiftsResponse.data;
        _presets = presetsResponse.data;
        _loading = false;
      });
    } catch (error) {
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<EmployeePayPreview> _previewShift(WorkforceShiftDraft draft) async {
    final payload = await context.read<AppState>().postJson(
          '/api/workforce/calculate-preview',
          body: draft.toPayload(),
        );
    final raw = payload['preview'];
    return EmployeePayPreview.fromJson(
        raw is Map ? Map<String, dynamic>.from(raw) : const {});
  }

  Future<void> _editShift({ShiftRecord? shift, ShiftPreset? preset}) async {
    if (!context.read<AppState>().hasOperatorAccess) return;
    if (_workplaces.isEmpty || _employees.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('근무지와 활성 직원을 먼저 등록하세요.')));
      return;
    }
    final workplaceId = shift?.workplaceId ??
        preset?.workplaceId ??
        _workplaceId ??
        _workplaces.first.id;
    final matchingEmployees = _employees
        .where((employee) => employee.workplaceId == workplaceId)
        .toList(growable: false);
    final employeeId = shift?.employeeId ??
        (_employeeId != null &&
                matchingEmployees.any((item) => item.id == _employeeId)
            ? _employeeId
            : matchingEmployees.isEmpty
                ? null
                : matchingEmployees.first.id);
    final initial = shift != null
        ? WorkforceShiftDraft.fromShift(shift)
        : preset != null
            ? WorkforceShiftDraft.fromPreset(
                preset, _formatDate(ApiService.kstNow()),
                employeeId: employeeId)
            : WorkforceShiftDraft(
                workplaceId: workplaceId,
                employeeId: employeeId,
                date: _formatDate(ApiService.kstNow()),
                startTime: '09:00',
                endTime: '18:00',
                breakMinutes: 60,
              );
    final draft = await showDialog<WorkforceShiftDraft>(
      context: context,
      builder: (_) => WorkforceShiftFormDialog(
        workplaces: _workplaces,
        employees: _employees,
        initialValue: initial,
        editing: shift != null,
        onPreview: _previewShift,
      ),
    );
    if (draft == null || !mounted) return;
    try {
      await context.read<AppState>().postJson(
            shift == null
                ? '/api/workforce/shifts'
                : '/api/workforce/shifts/${shift.id}',
            method: shift == null ? 'POST' : 'PATCH',
            body: draft.toPayload(),
          );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _deleteShift(ShiftRecord shift) async {
    if (!context.read<AppState>().hasOperatorAccess) return;
    final confirmed = await _confirmDelete(
        title: '근무 삭제',
        message: '${_formatWeekday(shift.shiftDate)} 근무를 삭제할까요?');
    if (!confirmed || !mounted) return;
    try {
      await context
          .read<AppState>()
          .postJson('/api/workforce/shifts/${shift.id}', method: 'DELETE');
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _confirmFilteredShifts(bool confirmed) async {
    if (!context.read<AppState>().hasOperatorAccess) return;
    final actionLabel = confirmed ? '확정' : '확정 해제';
    final accepted = await _confirmShiftAction(
      title: '기간 근무 $actionLabel',
      message:
          '${_formatDate(_fromDate)} ~ ${_formatDate(_toDate)} 기간의 현재 필터 근무를 $actionLabel합니다. 확정된 근무만 급여 정산서에 포함됩니다.',
      confirmLabel: actionLabel,
    );
    if (!accepted || !mounted) return;
    try {
      final result = await context.read<AppState>().postJson(
        '/api/workforce/shifts/confirm',
        body: {
          'from_date': _formatDate(_fromDate),
          'to_date': _formatDate(_toDate),
          if (_workplaceId != null) 'workplace_id': _workplaceId,
          if (_employeeId != null) 'employee_id': _employeeId,
          'confirmed': confirmed,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${asInt(result['updated_count'])}건의 근무를 $actionLabel했습니다.')));
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _confirmSingleShift(ShiftRecord shift) async {
    if (!context.read<AppState>().hasOperatorAccess) return;
    final confirmed = shift.confirmedAt == null;
    final actionLabel = confirmed ? '확정' : '확정 해제';
    final accepted = await _confirmShiftAction(
      title: '근무 $actionLabel',
      message:
          '${_formatWeekday(shift.shiftDate)} ${timePart(shift.startAt)}-${timePart(shift.endAt)} 근무를 $actionLabel할까요? 확정된 근무만 급여 정산서에 포함됩니다.',
      confirmLabel: actionLabel,
    );
    if (!accepted || !mounted) return;
    try {
      final result = await context.read<AppState>().postJson(
        '/api/workforce/shifts/confirm',
        body: {
          'shift_ids': [shift.id],
          'confirmed': confirmed,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${asInt(result['updated_count'])}건의 근무를 $actionLabel했습니다.')));
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<bool> _confirmShiftAction({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('취소')),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(confirmLabel)),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _editPreset({ShiftPreset? preset}) async {
    if (!context.read<AppState>().hasOperatorAccess) return;
    if (_workplaces.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('근무지를 먼저 등록하세요.')));
      return;
    }
    final initial = preset == null
        ? WorkforcePresetDraft(
            workplaceId: _workplaceId ?? _workplaces.first.id,
            name: '',
            startTime: '09:00',
            endTime: '18:00',
            breakMinutes: 60,
          )
        : WorkforcePresetDraft.fromPreset(preset);
    final draft = await showDialog<WorkforcePresetDraft>(
      context: context,
      builder: (_) => WorkforcePresetFormDialog(
          workplaces: _workplaces,
          initialValue: initial,
          editing: preset != null),
    );
    if (draft == null || !mounted) return;
    try {
      await context.read<AppState>().postJson(
            preset == null
                ? '/api/workforce/presets'
                : '/api/workforce/presets/${preset.id}',
            method: preset == null ? 'POST' : 'PATCH',
            body: draft.toPayload(),
          );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _toggleFavorite(ShiftPreset preset) async {
    if (!context.read<AppState>().hasOperatorAccess) return;
    try {
      await context.read<AppState>().postJson(
        '/api/workforce/presets/${preset.id}',
        method: 'PATCH',
        body: {'is_favorite': !preset.isFavorite},
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _deletePreset(ShiftPreset preset) async {
    if (!context.read<AppState>().hasOperatorAccess) return;
    final confirmed = await _confirmDelete(
        title: '프리셋 삭제', message: '"${preset.name}" 프리셋을 삭제할까요?');
    if (!confirmed || !mounted) return;
    try {
      await context
          .read<AppState>()
          .postJson('/api/workforce/presets/${preset.id}', method: 'DELETE');
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<bool> _confirmDelete(
      {required String title, required String message}) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('취소')),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('삭제')),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final canOperate = context.select<AppState, bool>(
      (state) => state.hasOperatorAccess,
    );
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return EmptyState(
          title: '근무 데이터를 불러오지 못했습니다.',
          message: _error,
          action: FilledButton(onPressed: _load, child: const Text('다시 시도')));
    }
    final totalMinutes =
        _shifts.fold<int>(0, (sum, shift) => sum + _workedMinutes(shift));
    final confirmedCount =
        _shifts.where((shift) => shift.confirmedAt != null).length;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text('근무 기록 (${_formatDate(_fromDate)} ~ ${_formatDate(_toDate)})',
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2024, 1, 1),
                      lastDate:
                          ApiService.kstNow().add(const Duration(days: 365)),
                      initialDateRange:
                          DateTimeRange(start: _fromDate, end: _toDate));
                  if (picked == null || !mounted) return;
                  setState(() {
                    _fromDate = picked.start;
                    _toDate = picked.end;
                  });
                  await _load();
                },
                icon: const Icon(Icons.date_range_outlined, size: 16),
                label: const Text('기간'),
              ),
              FilledButton.icon(
                onPressed: canOperate ? () => _editShift() : null,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('빠른 등록'),
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
          if (!canOperate) ...[
            const SizedBox(height: 12),
            const _WorkforceReadOnlyHint(),
          ],
          const SizedBox(height: 8),
          const Text('확정된 근무만 급여 정산서에 포함됩니다.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
          if (canOperate) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _shifts.isEmpty
                      ? null
                      : () => _confirmFilteredShifts(true),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('필터 기간 근무 확정'),
                ),
                OutlinedButton.icon(
                  onPressed: confirmedCount == 0
                      ? null
                      : () => _confirmFilteredShifts(false),
                  icon: const Icon(Icons.undo_outlined, size: 16),
                  label: const Text('필터 기간 확정 해제'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _MetricGrid(cards: [
            StatCard(label: '근무 건수', value: '${_shifts.length}건', accent: true),
            StatCard(label: '확정 근무', value: '$confirmedCount건'),
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
                              onTap: canOperate
                                  ? () => _editShift(shift: shift)
                                  : null,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                  '${_formatWeekday(shift.shiftDate)} · ${timePart(shift.startAt)}-${timePart(shift.endAt)}'),
                              subtitle: Text(
                                  '${shift.workplaceName}${shift.employeeName?.isNotEmpty == true ? ' · ${shift.employeeName}' : ''}'),
                              leading: Chip(
                                avatar: Icon(
                                  shift.confirmedAt == null
                                      ? Icons.schedule_outlined
                                      : Icons.check_circle_outline,
                                  size: 16,
                                ),
                                label: Text(
                                    shift.confirmedAt == null ? '미확정' : '확정'),
                                visualDensity: VisualDensity.compact,
                              ),
                              trailing: canOperate
                                  ? PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'edit') {
                                          _editShift(shift: shift);
                                        }
                                        if (value == 'delete') {
                                          _deleteShift(shift);
                                        }
                                        if (value == 'toggle-confirm') {
                                          _confirmSingleShift(shift);
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(
                                            value: 'edit', child: Text('수정')),
                                        PopupMenuItem(
                                            value: 'toggle-confirm',
                                            child: Text(
                                                shift.confirmedAt == null
                                                    ? '근무 확정'
                                                    : '확정 해제')),
                                        const PopupMenuItem(
                                            value: 'delete', child: Text('삭제')),
                                      ],
                                    )
                                  : null,
                            ))
                        .toList(growable: false)),
          ),
          const SizedBox(height: 16),
          Panel(
            title: '근무 템플릿',
            subtitle: '적용 가능한 템플릿',
            child: Column(children: [
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: canOperate ? () => _editPreset() : null,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('프리셋 추가'),
                ),
              ),
              const SizedBox(height: 8),
              if (_presets.isEmpty)
                const Text('등록된 템플릿이 없습니다.',
                    style: TextStyle(color: Color(0xFF64748B)))
              else
                Column(
                    children: _presets
                        .map((preset) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(preset.name),
                              subtitle: Text(
                                  '${preset.workplaceName} · ${preset.startTime}~${preset.endTime}'),
                              leading: canOperate
                                  ? IconButton(
                                      tooltip: '즐겨찾기',
                                      onPressed: () => _toggleFavorite(preset),
                                      icon: Icon(preset.isFavorite
                                          ? Icons.star
                                          : Icons.star_border),
                                    )
                                  : null,
                              trailing: canOperate
                                  ? PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'use') {
                                          _editShift(preset: preset);
                                        }
                                        if (value == 'edit') {
                                          _editPreset(preset: preset);
                                        }
                                        if (value == 'delete') {
                                          _deletePreset(preset);
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                            value: 'use', child: Text('근무 생성')),
                                        PopupMenuItem(
                                            value: 'edit', child: Text('수정')),
                                        PopupMenuItem(
                                            value: 'delete', child: Text('삭제')),
                                      ],
                                    )
                                  : null,
                            ))
                        .toList(growable: false)),
            ]),
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

class _PayslipsTabState extends State<_PayslipsTab>
    with AsyncRequestGuard<_PayslipsTab> {
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
    if (!mounted) return;
    final request = beginAsyncRequest();
    final appState = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final workplacesResponse = await appState.fetchMapParsed<List<Workplace>>(
        '/api/workforce/workplaces',
        parser: _parseWorkplaces,
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      final employeesResponse = await appState.fetchMapParsed<List<Employee>>(
        '/api/workforce/employees',
        params: const {'is_active': true},
        parser: _parseEmployees,
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      final payslipsPayload = await appState.postJson(
        '/api/workforce/payslips/calculate',
        body: {
          'from_date': _formatDate(_fromDate),
          'to_date': _formatDate(_toDate),
          if (_workplaceId != null) 'workplace_id': _workplaceId,
          if (_employeeId != null) 'employee_id': _employeeId
        },
      );
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _workplaces = workplacesResponse.data;
        _employees = employeesResponse.data;
        _data = WorkforcePeriodData.fromJson(payslipsPayload);
        _loading = false;
      });
    } catch (error) {
      if (!isCurrentAsyncRequest(request)) return;
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
          Panel(
            title: '급여 정산서',
            subtitle: '확정 근무만 포함하는 정산 초안·검토·확정 흐름',
            child: Row(
              children: [
                const Expanded(
                  child: Text('근무 확정 상태와 정산 이슈를 확인하고 단계별로 처리합니다.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                        builder: (_) => const PayrollRunsScreen()),
                  ),
                  icon: const Icon(Icons.receipt_long_outlined, size: 16),
                  label: const Text('열기'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2024),
                    lastDate:
                        ApiService.kstNow().add(const Duration(days: 365)),
                    initialDateRange:
                        DateTimeRange(start: _fromDate, end: _toDate),
                  );
                  if (picked == null || !mounted) return;
                  setState(() {
                    _fromDate = picked.start;
                    _toDate = picked.end;
                  });
                  await _load();
                },
                icon: const Icon(Icons.date_range_outlined, size: 16),
                label:
                    Text('${_formatDate(_fromDate)} ~ ${_formatDate(_toDate)}'),
              ),
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

class _EmployeesTabState extends State<_EmployeesTab>
    with AsyncRequestGuard<_EmployeesTab> {
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
    if (!mounted) return;
    final request = beginAsyncRequest();
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
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _list = response.data;
        _loading = false;
      });
    } catch (error) {
      if (!isCurrentAsyncRequest(request)) return;
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
            parser: _parseWorkplaces,
            cacheTtl: Duration.zero,
            allowStaleOnError: false);
    return response.data;
  }

  Future<void> _editEmployee({Employee? employee}) async {
    if (!context.read<AppState>().hasOperatorAccess) return;
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
        String monthlySalary = employee?.monthlySalary?.toString() ?? '';
        String monthlySalaryMode =
            employee?.monthlySalaryCalculationMode == 'fixed_period'
                ? 'fixed_period'
                : 'prorated_hours';
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
                            initialValue: monthlySalary,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: '월급 (원)'),
                            onChanged: (value) => monthlySalary = value,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: monthlySalaryMode,
                            decoration:
                                const InputDecoration(labelText: '월급 계산 방식'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'prorated_hours',
                                  child: Text('근무시간 비례')),
                              DropdownMenuItem(
                                  value: 'fixed_period', child: Text('고정 기간급')),
                            ],
                            onChanged: (value) => setModalState(() =>
                                monthlySalaryMode = value ?? monthlySalaryMode),
                          ),
                        ),
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
                  final validationError = validateEmployeeForm(
                    workplaceId: workplaceId,
                    name: name,
                    joinedOn: joinedOn,
                    resignedOn: resignedOn,
                    hourlyWage: hourlyWage,
                    taxRate: taxRate,
                    monthlySalary: monthlySalary,
                  );
                  if (validationError != null) {
                    ScaffoldMessenger.of(dialogContext)
                        .showSnackBar(SnackBar(content: Text(validationError)));
                    return;
                  }
                  final body = <String, dynamic>{
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
                        : int.parse(hourlyWage.trim()),
                    'monthly_salary': monthlySalary.trim().isEmpty
                        ? null
                        : int.parse(monthlySalary.trim()),
                    'monthly_salary_calculation_mode': monthlySalaryMode,
                    'tax_preset': taxPreset,
                    'tax_custom_rate': double.parse(taxRate.trim()),
                    'memo': memo.trim(),
                    'linked_auth_user_id': linkedAuthUserId.trim().isEmpty
                        ? null
                        : int.tryParse(linkedAuthUserId.trim()),
                    'is_active': isActive,
                  };
                  await context.read<AppState>().postJson(
                        employee == null
                            ? '/api/workforce/employees'
                            : '/api/workforce/employees/${employee.id}',
                        method: employee == null ? 'POST' : 'PATCH',
                        body: body,
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
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
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
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      final payslipResponse =
          await appState.fetchMapParsed<EmployeePayslipData>(
        '/api/workforce/employees/${employee.id}/payslips',
        params: _currentMonthRangeAsParams(),
        parser: EmployeePayslipData.fromJson,
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      if (!mounted) return;
      final detail = detailResponse.data;
      final auditLogs = auditLogsResponse.data;
      final payslip = payslipResponse.data;
      final canOperate = context.read<AppState>().hasOperatorAccess;
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
            if (canOperate) ...[
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
            ],
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
    final appState = context.read<AppState>();
    final previewDate = ApiService.kstNow();
    await showDialog<void>(
      context: context,
      builder: (_) => EmployeePayPreviewDialog(
        employee: employee,
        date: previewDate,
        onPreview: (draft) async {
          final payload = await appState.postJson(
            '/api/workforce/employees/${employee.id}/pay-preview',
            body: {
              'start_at': '${draft.date}T${draft.startTime}',
              'end_at': '${draft.date}T${draft.endTime}',
              'break_minutes': draft.breakMinutes,
              'leave_type': draft.leaveType,
              'holiday_type': draft.holidayType,
              'adjustments': [
                if (draft.extraAmount > 0)
                  {
                    'kind': 'extra',
                    'label': '추가 지급',
                    'amount': draft.extraAmount,
                  },
                if (draft.deductionAmount > 0)
                  {
                    'kind': 'deduction',
                    'label': '추가 차감',
                    'amount': draft.deductionAmount,
                  },
              ],
            },
          );
          return EmployeePayPreviewData.fromJson(payload);
        },
      ),
    );
  }

  Future<void> _deleteEmployee(Employee employee) async {
    if (!context.read<AppState>().hasOperatorAccess) return;
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
    if (!context.read<AppState>().hasOperatorAccess) return;
    try {
      await context.read<AppState>().postJson(
          '/api/workforce/employees/${employee.id}',
          method: 'PATCH',
          body: employee.toPatchPayload(active: !employee.isActive));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canOperate = context.select<AppState, bool>(
      (state) => state.hasOperatorAccess,
    );
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
                  onPressed: canOperate ? () => _editEmployee() : null,
                  icon: const Icon(Icons.person_add_alt_1, size: 16),
                  label: const Text('직원 추가')),
            ],
          ),
          if (!canOperate) ...[
            const SizedBox(height: 12),
            const _WorkforceReadOnlyHint(),
          ],
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

class _BulkShiftValues {
  final int workplaceId;
  final int employeeId;
  final String startTime;
  final String endTime;
  final int breakMinutes;
  final String leaveType;
  final String holidayType;
  final String memo;
  final int extraAmount;
  final int deductionAmount;

  const _BulkShiftValues({
    required this.workplaceId,
    required this.employeeId,
    required this.startTime,
    required this.endTime,
    required this.breakMinutes,
    required this.leaveType,
    required this.holidayType,
    required this.memo,
    required this.extraAmount,
    required this.deductionAmount,
  });

  WorkforceShiftDraft toDraft(String date) => WorkforceShiftDraft(
        workplaceId: workplaceId,
        employeeId: employeeId,
        date: date,
        startTime: startTime,
        endTime: endTime,
        breakMinutes: breakMinutes,
        leaveType: leaveType,
        holidayType: holidayType,
        memo: memo,
        extraAmount: extraAmount,
        deductionAmount: deductionAmount,
      );

  Map<String, dynamic> toBulkPayload(List<String> dates) => {
        'workplace_id': workplaceId,
        'employee_id': employeeId,
        'dates': dates,
        'start_time': normalizeWorkforceTime(startTime),
        'end_time': normalizeWorkforceTime(endTime),
        'break_minutes': breakMinutes,
        'leave_type': leaveType,
        'holiday_type': holidayType,
        'memo': memo.trim(),
        'extra_amount': extraAmount,
        'deduction_amount': deductionAmount,
        'skip_existing': true,
      };
}

class _BulkShiftFormDialog extends StatefulWidget {
  final List<Workplace> workplaces;
  final List<Employee> employees;
  final List<ShiftPreset> presets;
  final List<String> dates;

  const _BulkShiftFormDialog({
    required this.workplaces,
    required this.employees,
    required this.presets,
    required this.dates,
  });

  @override
  State<_BulkShiftFormDialog> createState() => _BulkShiftFormDialogState();
}

class _BulkShiftFormDialogState extends State<_BulkShiftFormDialog> {
  late int? _workplaceId;
  late int? _employeeId;
  int? _presetId;
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  late final TextEditingController _breakController;
  late final TextEditingController _extraController;
  late final TextEditingController _deductionController;
  late final TextEditingController _memoController;
  String _leaveType = 'none';
  String _holidayType = 'none';
  String? _error;

  @override
  void initState() {
    super.initState();
    _workplaceId = widget.workplaces.first.id;
    final employees = _employeesFor(_workplaceId);
    _employeeId = employees.isEmpty ? null : employees.first.id;
    _startController = TextEditingController(text: '09:00');
    _endController = TextEditingController(text: '18:00');
    _breakController = TextEditingController(text: '60');
    _extraController = TextEditingController(text: '0');
    _deductionController = TextEditingController(text: '0');
    _memoController = TextEditingController();
  }

  List<Employee> _employeesFor(int? workplaceId) => widget.employees
      .where((employee) => employee.workplaceId == workplaceId)
      .toList(growable: false);

  List<ShiftPreset> get _presetsForWorkplace => widget.presets
      .where((preset) => preset.workplaceId == _workplaceId)
      .toList(growable: false);

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    _breakController.dispose();
    _extraController.dispose();
    _deductionController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  void _applyPreset(int? presetId) {
    ShiftPreset? preset;
    for (final item in widget.presets) {
      if (item.id == presetId) {
        preset = item;
        break;
      }
    }
    setState(() {
      _presetId = presetId;
      if (preset == null) return;
      _startController.text = _timePart(preset.startTime);
      _endController.text = _timePart(preset.endTime);
      _breakController.text = preset.breakMinutes.toString();
      _extraController.text = preset.extraAmount.toString();
      _deductionController.text = preset.deductionAmount.toString();
      _memoController.text = preset.memo;
      _leaveType = preset.leaveType;
      _holidayType = preset.holidayType;
    });
  }

  void _submit() {
    final workplaceId = _workplaceId;
    final employeeId = _employeeId;
    final values = _BulkShiftValues(
      workplaceId: workplaceId ?? 0,
      employeeId: employeeId ?? 0,
      startTime: _startController.text,
      endTime: _endController.text,
      breakMinutes: int.tryParse(_breakController.text) ?? -1,
      leaveType: _leaveType,
      holidayType: _holidayType,
      memo: _memoController.text,
      extraAmount: int.tryParse(_extraController.text) ?? -1,
      deductionAmount: int.tryParse(_deductionController.text) ?? -1,
    );
    final error = values.toDraft(widget.dates.first).validate();
    if (workplaceId == null || employeeId == null || error != null) {
      setState(() => _error = error ?? '근무지와 직원을 선택하세요.');
      return;
    }
    Navigator.pop(context, values);
  }

  @override
  Widget build(BuildContext context) {
    final employees = _employeesFor(_workplaceId);
    final presets = _presetsForWorkplace;
    final employeeValue =
        employees.any((item) => item.id == _employeeId) ? _employeeId : null;
    final presetValue =
        presets.any((item) => item.id == _presetId) ? _presetId : null;
    return AlertDialog(
      title: const Text('선택 일괄등록'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    '${widget.dates.length}일 선택됨 · ${widget.dates.first} 외',
                    style: const TextStyle(color: Color(0xFF64748B))),
              ),
              DropdownButtonFormField<int?>(
                initialValue: _workplaceId,
                decoration: const InputDecoration(labelText: '근무지 *'),
                items: widget.workplaces
                    .map((item) => DropdownMenuItem<int?>(
                        value: item.id, child: Text(item.name)))
                    .toList(growable: false),
                onChanged: (value) => setState(() {
                  _workplaceId = value;
                  _employeeId = null;
                  _presetId = null;
                }),
              ),
              DropdownButtonFormField<int?>(
                key: ValueKey('bulk-employee-$employeeValue'),
                initialValue: employeeValue,
                decoration: const InputDecoration(labelText: '직원 *'),
                items: employees
                    .map((item) => DropdownMenuItem<int?>(
                        value: item.id, child: Text(item.name)))
                    .toList(growable: false),
                onChanged: (value) => setState(() => _employeeId = value),
              ),
              DropdownButtonFormField<int?>(
                key: ValueKey('bulk-preset-$presetValue'),
                initialValue: presetValue,
                decoration: const InputDecoration(labelText: '템플릿'),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('직접 입력')),
                  ...presets.map((item) => DropdownMenuItem<int?>(
                      value: item.id, child: Text(item.name))),
                ],
                onChanged: _applyPreset,
              ),
              Row(
                children: [
                  Expanded(
                      child: TextField(
                          controller: _startController,
                          decoration:
                              const InputDecoration(labelText: '시작 *'))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: TextField(
                          controller: _endController,
                          decoration:
                              const InputDecoration(labelText: '종료 *'))),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _numberField('휴게(분)', _breakController)),
                  const SizedBox(width: 12),
                  Expanded(child: _numberField('추가 지급', _extraController)),
                  const SizedBox(width: 12),
                  Expanded(child: _numberField('추가 차감', _deductionController)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _leaveDropdown()),
                  const SizedBox(width: 12),
                  Expanded(child: _holidayDropdown()),
                ],
              ),
              TextField(
                controller: _memoController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '메모'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: const TextStyle(color: Color(0xFFB91C1C))),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(onPressed: _submit, child: const Text('등록 시작')),
      ],
    );
  }

  Widget _numberField(String label, TextEditingController controller) =>
      TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
      );

  Widget _leaveDropdown() => DropdownButtonFormField<String>(
        initialValue: _leaveType,
        decoration: const InputDecoration(labelText: '근무 구분'),
        items: const [
          DropdownMenuItem(value: 'none', child: Text('정상근무')),
          DropdownMenuItem(value: 'vacation', child: Text('휴가')),
          DropdownMenuItem(value: 'absent', child: Text('결근')),
          DropdownMenuItem(value: 'day_off', child: Text('휴무')),
          DropdownMenuItem(value: 'paid_day_off', child: Text('유급휴무')),
          DropdownMenuItem(value: 'substitute', child: Text('대타')),
        ],
        onChanged: (value) => setState(() => _leaveType = value ?? 'none'),
      );

  Widget _holidayDropdown() => DropdownButtonFormField<String>(
        initialValue: _holidayType,
        decoration: const InputDecoration(labelText: '휴일 구분'),
        items: const [
          DropdownMenuItem(value: 'none', child: Text('일반일')),
          DropdownMenuItem(value: 'weekend', child: Text('주말')),
          DropdownMenuItem(value: 'public', child: Text('공휴일')),
          DropdownMenuItem(value: 'custom', child: Text('기타 휴일')),
        ],
        onChanged: (value) => setState(() => _holidayType = value ?? 'none'),
      );

  String _timePart(String value) =>
      value.length > 5 ? value.substring(0, 5) : value;
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

class _WorkforceReadOnlyHint extends StatelessWidget {
  const _WorkforceReadOnlyHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.visibility_outlined, size: 18, color: Color(0xFF64748B)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '현재 계정은 조회 전용입니다. 근무지, 직원, 근무 기록 변경은 operator 권한에서 사용할 수 있습니다.',
              style: TextStyle(
                color: Color(0xFF475569),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
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

class _FormSectionHeader extends StatelessWidget {
  final String title;

  const _FormSectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155))),
        ),
      );
}

List<Workplace> _parseWorkplaces(Map<String, dynamic> json) {
  return requireListOfMaps(json, 'workplaces')
      .map(Workplace.fromJson)
      .toList(growable: false);
}

List<Employee> _parseEmployees(Map<String, dynamic> json) {
  return requireListOfMaps(json, 'employees')
      .map(Employee.fromJson)
      .toList(growable: false);
}

List<ShiftRecord> _parseShifts(Map<String, dynamic> json) {
  return requireListOfMaps(json, 'shifts')
      .map(ShiftRecord.fromJson)
      .toList(growable: false);
}

List<ShiftPreset> _parsePresets(Map<String, dynamic> json) {
  return requireListOfMaps(json, 'presets')
      .map(ShiftPreset.fromJson)
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
  return workforceTimePart(isoText);
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
  final now = ApiService.kstNow();
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
