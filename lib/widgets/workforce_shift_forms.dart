import 'package:flutter/material.dart';

import '../models/workforce_models.dart';
import 'responsive_wrap_grid.dart';
import 'stat_card.dart';

typedef ShiftPreviewLoader = Future<EmployeePayPreview> Function(
    WorkforceShiftDraft draft);
typedef EmployeePayPreviewLoader = Future<EmployeePayPreviewData> Function(
  WorkforceShiftDraft draft,
);

class WorkforceShiftFormDialog extends StatefulWidget {
  final List<Workplace> workplaces;
  final List<Employee> employees;
  final WorkforceShiftDraft initialValue;
  final bool editing;
  final ShiftPreviewLoader onPreview;

  const WorkforceShiftFormDialog({
    super.key,
    required this.workplaces,
    required this.employees,
    required this.initialValue,
    required this.editing,
    required this.onPreview,
  });

  @override
  State<WorkforceShiftFormDialog> createState() =>
      _WorkforceShiftFormDialogState();
}

class _WorkforceShiftFormDialogState extends State<WorkforceShiftFormDialog> {
  late int? _workplaceId;
  late int? _employeeId;
  late String _date;
  late String _startTime;
  late String _endTime;
  late String _breakMinutes;
  late String _leaveType;
  late String _holidayType;
  late String _memo;
  late String _extraAmount;
  late String _deductionAmount;
  String? _error;
  EmployeePayPreview? _preview;
  bool _previewing = false;
  int _previewRequest = 0;

  @override
  void initState() {
    super.initState();
    final value = widget.initialValue;
    _workplaceId = value.workplaceId;
    _employeeId = value.employeeId;
    _date = value.date;
    _startTime = value.startTime;
    _endTime = value.endTime;
    _breakMinutes = value.breakMinutes.toString();
    _leaveType = value.leaveType;
    _holidayType = value.holidayType;
    _memo = value.memo;
    _extraAmount = value.extraAmount.toString();
    _deductionAmount = value.deductionAmount.toString();
  }

  List<Employee> get _availableEmployees => widget.employees
      .where((employee) => employee.workplaceId == _workplaceId)
      .toList(growable: false);

  WorkforceShiftDraft _draft() => WorkforceShiftDraft(
        workplaceId: _workplaceId,
        employeeId: _employeeId,
        date: _date,
        startTime: _startTime,
        endTime: _endTime,
        breakMinutes: int.tryParse(_breakMinutes.trim()) ?? -1,
        leaveType: _leaveType,
        holidayType: _holidayType,
        memo: _memo,
        extraAmount: int.tryParse(_extraAmount.trim()) ?? -1,
        deductionAmount: int.tryParse(_deductionAmount.trim()) ?? -1,
      );

  void _submit() {
    final draft = _draft();
    final error = draft.validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, draft);
  }

  void _updateDraft(VoidCallback update) {
    setState(() {
      update();
      _previewRequest += 1;
      _preview = null;
      _previewing = false;
    });
  }

  Future<void> _loadPreview() async {
    final draft = _draft();
    final error = draft.validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final request = ++_previewRequest;
    setState(() {
      _previewing = true;
      _error = null;
    });
    try {
      final preview = await widget.onPreview(draft);
      if (!mounted || request != _previewRequest) return;
      setState(() => _preview = preview);
    } catch (error) {
      if (!mounted || request != _previewRequest) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted && request == _previewRequest) {
        setState(() => _previewing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final employees = _availableEmployees;
    final employeeValue =
        employees.any((item) => item.id == _employeeId) ? _employeeId : null;
    return AlertDialog(
      title: Text(widget.editing ? '근무 수정' : '빠른 근무 등록'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                key: const Key('shift-workplace'),
                initialValue: _workplaceId,
                decoration: const InputDecoration(labelText: '근무지 *'),
                items: widget.workplaces
                    .map((item) => DropdownMenuItem(
                        value: item.id, child: Text(item.name)))
                    .toList(growable: false),
                onChanged: (value) => _updateDraft(() {
                  _workplaceId = value;
                  _employeeId = null;
                }),
              ),
              DropdownButtonFormField<int>(
                key: ValueKey('shift-employee-$employeeValue'),
                initialValue: employeeValue,
                decoration: const InputDecoration(labelText: '직원 *'),
                items: employees
                    .map((item) => DropdownMenuItem(
                        value: item.id, child: Text(item.name)))
                    .toList(growable: false),
                onChanged: (value) => _updateDraft(() => _employeeId = value),
              ),
              TextFormField(
                key: const Key('shift-date'),
                initialValue: _date,
                decoration: const InputDecoration(
                    labelText: '날짜 *', hintText: 'YYYY-MM-DD'),
                onChanged: (value) => _updateDraft(() => _date = value),
              ),
              ResponsiveWrapGrid(
                minItemWidth: 180,
                maxColumns: 2,
                children: [
                  _textField('시작 *', _startTime,
                      (value) => _updateDraft(() => _startTime = value),
                      key: 'shift-start'),
                  _textField('종료 *', _endTime,
                      (value) => _updateDraft(() => _endTime = value),
                      key: 'shift-end'),
                ],
              ),
              ResponsiveWrapGrid(
                minItemWidth: 160,
                maxColumns: 3,
                children: [
                  _numberField('휴게(분)', _breakMinutes,
                      (value) => _updateDraft(() => _breakMinutes = value)),
                  _numberField('추가 지급', _extraAmount,
                      (value) => _updateDraft(() => _extraAmount = value)),
                  _numberField(
                    '추가 차감',
                    _deductionAmount,
                    (value) => _updateDraft(() => _deductionAmount = value),
                  ),
                ],
              ),
              ResponsiveWrapGrid(
                minItemWidth: 180,
                maxColumns: 2,
                children: [_leaveDropdown(), _holidayDropdown()],
              ),
              TextFormField(
                initialValue: _memo,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '메모'),
                onChanged: (value) => _updateDraft(() => _memo = value),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.red),
                      key: const Key('shift-form-error')),
                ),
              if (_preview != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '예상 급여 ${_preview!.grossPay}원 · 공제 ${_preview!.taxEstimate}원 · 실수령 ${_preview!.netEstimate}원',
                    key: const Key('shift-preview-result'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('취소')),
        OutlinedButton(
          onPressed: _previewing ? null : _loadPreview,
          child: Text(_previewing ? '계산 중' : '급여 미리보기'),
        ),
        FilledButton(onPressed: _submit, child: const Text('저장')),
      ],
    );
  }

  Widget _textField(String label, String value, ValueChanged<String> changed,
      {String? key}) {
    return TextFormField(
      key: key == null ? null : Key(key),
      initialValue: value,
      decoration: InputDecoration(labelText: label, hintText: 'HH:mm'),
      onChanged: changed,
    );
  }

  Widget _numberField(
          String label, String value, ValueChanged<String> changed) =>
      TextFormField(
        initialValue: value,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
        onChanged: changed,
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
        onChanged: (value) => _updateDraft(() => _leaveType = value ?? 'none'),
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
        onChanged: (value) =>
            _updateDraft(() => _holidayType = value ?? 'none'),
      );
}

class EmployeePayPreviewDialog extends StatefulWidget {
  final Employee employee;
  final DateTime date;
  final EmployeePayPreviewLoader onPreview;

  const EmployeePayPreviewDialog({
    super.key,
    required this.employee,
    required this.date,
    required this.onPreview,
  });

  @override
  State<EmployeePayPreviewDialog> createState() =>
      _EmployeePayPreviewDialogState();
}

class _EmployeePayPreviewDialogState extends State<EmployeePayPreviewDialog> {
  String _startAt = '09:00';
  String _endAt = '18:00';
  int _breakMinutes = 60;
  String _leaveType = 'none';
  String _holidayType = 'none';
  int _extraAmount = 0;
  int _deductionAmount = 0;
  EmployeePayPreviewData? _preview;
  String? _error;
  bool _isLoading = false;
  int _requestGeneration = 0;

  String get _date =>
      '${widget.date.year.toString().padLeft(4, '0')}-${widget.date.month.toString().padLeft(2, '0')}-${widget.date.day.toString().padLeft(2, '0')}';

  WorkforceShiftDraft _draft() => WorkforceShiftDraft(
        workplaceId: widget.employee.workplaceId,
        employeeId: widget.employee.id,
        date: _date,
        startTime: _startAt,
        endTime: _endAt,
        breakMinutes: _breakMinutes,
        leaveType: _leaveType,
        holidayType: _holidayType,
        extraAmount: _extraAmount,
        deductionAmount: _deductionAmount,
      );

  void _updateInputs(VoidCallback update) {
    setState(() {
      update();
      _requestGeneration += 1;
      _preview = null;
      _error = null;
      _isLoading = false;
    });
  }

  Future<void> _loadPreview() async {
    final draft = _draft();
    final validationError = draft.validate();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    final request = ++_requestGeneration;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final preview = await widget.onPreview(draft);
      if (!mounted || request != _requestGeneration) return;
      setState(() => _preview = preview);
    } catch (error) {
      if (!mounted || request != _requestGeneration) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted && request == _requestGeneration) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.employee.name} 급여 미리보기'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ResponsiveWrapGrid(
                minItemWidth: 180,
                maxColumns: 2,
                children: [
                  _timeField(
                    '시작',
                    _startAt,
                    (value) => _updateInputs(() => _startAt = value),
                  ),
                  _timeField(
                    '종료',
                    _endAt,
                    (value) => _updateInputs(() => _endAt = value),
                  ),
                ],
              ),
              ResponsiveWrapGrid(
                minItemWidth: 180,
                maxColumns: 2,
                children: [
                  _numberField(
                    '휴게(분)',
                    _breakMinutes,
                    (value) => _updateInputs(() => _breakMinutes = value),
                  ),
                  _numberField(
                    '추가 지급',
                    _extraAmount,
                    (value) => _updateInputs(() => _extraAmount = value),
                  ),
                ],
              ),
              ResponsiveWrapGrid(
                minItemWidth: 180,
                maxColumns: 2,
                children: [
                  _numberField(
                    '추가 차감',
                    _deductionAmount,
                    (value) => _updateInputs(() => _deductionAmount = value),
                  ),
                  _leaveDropdown(),
                ],
              ),
              _holidayDropdown(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              if (_preview != null) ...[
                const SizedBox(height: 12),
                ResponsiveWrapGrid(
                  minItemWidth: 140,
                  maxColumns: 3,
                  children: [
                    StatCard(
                      label: '세전',
                      value: '${_preview!.preview.grossPay}원',
                      accent: true,
                    ),
                    StatCard(
                      label: '세금',
                      value: '${_preview!.preview.taxEstimate}원',
                    ),
                    StatCard(
                      label: '세후',
                      value: '${_preview!.preview.netEstimate}원',
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _loadPreview,
          child: Text(_isLoading ? '계산 중...' : '계산'),
        ),
      ],
    );
  }

  Widget _timeField(
    String label,
    String value,
    ValueChanged<String> onChanged,
  ) {
    return TextFormField(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      onChanged: onChanged,
    );
  }

  Widget _numberField(
    String label,
    int value,
    ValueChanged<int> onChanged,
  ) {
    return TextFormField(
      initialValue: value.toString(),
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      onChanged: (text) => onChanged(int.tryParse(text) ?? value),
    );
  }

  Widget _leaveDropdown() => DropdownButtonFormField<String>(
        initialValue: _leaveType,
        decoration: const InputDecoration(labelText: '휴무 타입'),
        items: const [
          DropdownMenuItem(value: 'none', child: Text('정상근무')),
          DropdownMenuItem(value: 'vacation', child: Text('휴가')),
          DropdownMenuItem(value: 'absent', child: Text('결근')),
          DropdownMenuItem(value: 'day_off', child: Text('휴무')),
          DropdownMenuItem(value: 'paid_day_off', child: Text('유급휴무')),
          DropdownMenuItem(value: 'substitute', child: Text('대타')),
        ],
        onChanged: (value) =>
            _updateInputs(() => _leaveType = value ?? _leaveType),
      );

  Widget _holidayDropdown() => DropdownButtonFormField<String>(
        initialValue: _holidayType,
        decoration: const InputDecoration(labelText: '휴일 타입'),
        items: const [
          DropdownMenuItem(value: 'none', child: Text('일반일')),
          DropdownMenuItem(value: 'weekend', child: Text('주말')),
          DropdownMenuItem(value: 'public', child: Text('공휴일')),
          DropdownMenuItem(value: 'custom', child: Text('기타 휴일')),
        ],
        onChanged: (value) =>
            _updateInputs(() => _holidayType = value ?? _holidayType),
      );
}

class WorkforcePresetFormDialog extends StatefulWidget {
  final List<Workplace> workplaces;
  final WorkforcePresetDraft initialValue;
  final bool editing;

  const WorkforcePresetFormDialog({
    super.key,
    required this.workplaces,
    required this.initialValue,
    required this.editing,
  });

  @override
  State<WorkforcePresetFormDialog> createState() =>
      _WorkforcePresetFormDialogState();
}

class _WorkforcePresetFormDialogState extends State<WorkforcePresetFormDialog> {
  late int? _workplaceId;
  late String _name;
  late String _start;
  late String _end;
  late String _break;
  late String _extra;
  late String _deduction;
  late String _memo;
  late String _leaveType;
  late String _holidayType;
  late bool _favorite;
  String? _error;

  @override
  void initState() {
    super.initState();
    final value = widget.initialValue;
    _workplaceId = value.workplaceId;
    _name = value.name;
    _start = value.startTime;
    _end = value.endTime;
    _break = value.breakMinutes.toString();
    _extra = value.extraAmount.toString();
    _deduction = value.deductionAmount.toString();
    _memo = value.memo;
    _leaveType = value.leaveType;
    _holidayType = value.holidayType;
    _favorite = value.isFavorite;
  }

  void _submit() {
    final value = WorkforcePresetDraft(
      workplaceId: _workplaceId,
      name: _name,
      startTime: _start,
      endTime: _end,
      breakMinutes: int.tryParse(_break.trim()) ?? -1,
      leaveType: _leaveType,
      holidayType: _holidayType,
      memo: _memo,
      extraAmount: int.tryParse(_extra.trim()) ?? -1,
      deductionAmount: int.tryParse(_deduction.trim()) ?? -1,
      isFavorite: _favorite,
    );
    final error = value.validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.editing ? '프리셋 수정' : '프리셋 추가'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int>(
                initialValue: _workplaceId,
                decoration: const InputDecoration(labelText: '근무지 *'),
                items: widget.workplaces
                    .map((item) => DropdownMenuItem(
                        value: item.id, child: Text(item.name)))
                    .toList(growable: false),
                onChanged: (value) => setState(() => _workplaceId = value),
              ),
              _field('이름 *', _name, (value) => _name = value,
                  key: 'preset-name'),
              Row(children: [
                Expanded(child: _field('시작 *', _start, (v) => _start = v)),
                const SizedBox(width: 12),
                Expanded(child: _field('종료 *', _end, (v) => _end = v)),
              ]),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _leaveType,
                    decoration: const InputDecoration(labelText: '근무 구분'),
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('정상근무')),
                      DropdownMenuItem(value: 'vacation', child: Text('휴가')),
                      DropdownMenuItem(value: 'absent', child: Text('결근')),
                      DropdownMenuItem(value: 'day_off', child: Text('휴무')),
                      DropdownMenuItem(
                          value: 'paid_day_off', child: Text('유급휴무')),
                      DropdownMenuItem(value: 'substitute', child: Text('대타')),
                    ],
                    onChanged: (value) =>
                        setState(() => _leaveType = value ?? 'none'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _holidayType,
                    decoration: const InputDecoration(labelText: '휴일 구분'),
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('일반일')),
                      DropdownMenuItem(value: 'weekend', child: Text('주말')),
                      DropdownMenuItem(value: 'public', child: Text('공휴일')),
                      DropdownMenuItem(value: 'custom', child: Text('기타 휴일')),
                    ],
                    onChanged: (value) =>
                        setState(() => _holidayType = value ?? 'none'),
                  ),
                ),
              ]),
              Row(children: [
                Expanded(child: _number('휴게(분)', _break, (v) => _break = v)),
                const SizedBox(width: 12),
                Expanded(child: _number('추가 지급', _extra, (v) => _extra = v)),
                const SizedBox(width: 12),
                Expanded(
                    child: _number('추가 차감', _deduction, (v) => _deduction = v)),
              ]),
              TextFormField(
                initialValue: _memo,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '메모'),
                onChanged: (value) => _memo = value,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('즐겨찾기'),
                value: _favorite,
                onChanged: (value) => setState(() => _favorite = value),
              ),
              if (_error != null)
                Text(_error!,
                    key: const Key('preset-form-error'),
                    style: const TextStyle(color: Colors.red)),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(onPressed: _submit, child: const Text('저장')),
        ],
      );

  Widget _field(String label, String value, ValueChanged<String> changed,
          {String? key}) =>
      TextFormField(
        key: key == null ? null : Key(key),
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        onChanged: changed,
      );

  Widget _number(String label, String value, ValueChanged<String> changed) =>
      TextFormField(
        initialValue: value,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
        onChanged: changed,
      );
}
