import 'package:flutter/material.dart';

import '../models/workforce_models.dart';

typedef ShiftPreviewLoader = Future<EmployeePayPreview> Function(
    WorkforceShiftDraft draft);

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

  Future<void> _loadPreview() async {
    final draft = _draft();
    final error = draft.validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _previewing = true;
      _error = null;
    });
    try {
      final preview = await widget.onPreview(draft);
      if (!mounted) return;
      setState(() => _preview = preview);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _previewing = false);
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
                onChanged: (value) => setState(() {
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
                onChanged: (value) => setState(() => _employeeId = value),
              ),
              TextFormField(
                key: const Key('shift-date'),
                initialValue: _date,
                decoration: const InputDecoration(
                    labelText: '날짜 *', hintText: 'YYYY-MM-DD'),
                onChanged: (value) => _date = value,
              ),
              Row(children: [
                Expanded(
                    child: _textField(
                        '시작 *', _startTime, (value) => _startTime = value,
                        key: 'shift-start')),
                const SizedBox(width: 12),
                Expanded(
                    child: _textField(
                        '종료 *', _endTime, (value) => _endTime = value,
                        key: 'shift-end')),
              ]),
              Row(children: [
                Expanded(
                    child: _numberField('휴게(분)', _breakMinutes,
                        (value) => _breakMinutes = value)),
                const SizedBox(width: 12),
                Expanded(
                    child: _numberField('추가 지급', _extraAmount,
                        (value) => _extraAmount = value)),
                const SizedBox(width: 12),
                Expanded(
                    child: _numberField('추가 차감', _deductionAmount,
                        (value) => _deductionAmount = value)),
              ]),
              Row(children: [
                Expanded(child: _leaveDropdown()),
                const SizedBox(width: 12),
                Expanded(child: _holidayDropdown()),
              ]),
              TextFormField(
                initialValue: _memo,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '메모'),
                onChanged: (value) => _memo = value,
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
