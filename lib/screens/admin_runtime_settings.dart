import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/admin_runtime_settings.dart';
import '../services/api.dart';
import '../services/cache_store.dart';
import '../state/app_state.dart';
import '../widgets/app_screen.dart';
import '../widgets/panel.dart';

enum _RuntimeActionKind { prepare, test, apply, cancel, rollback }

class _PendingRuntimeAction {
  const _PendingRuntimeAction(this.kind, {this.version});

  final _RuntimeActionKind kind;
  final int? version;

  String get apiAction => switch (kind) {
        _RuntimeActionKind.prepare => 'prepare',
        _RuntimeActionKind.test => 'test',
        _RuntimeActionKind.apply => 'apply',
        _RuntimeActionKind.cancel => 'cancel',
        _RuntimeActionKind.rollback => 'rollback',
      };
  String get label => switch (kind) {
        _RuntimeActionKind.prepare => '변경 준비',
        _RuntimeActionKind.test => '연결 테스트',
        _RuntimeActionKind.apply => '설정 적용',
        _RuntimeActionKind.cancel => '변경 취소',
        _RuntimeActionKind.rollback => '버전 롤백',
      };
}

/// Secret-safe administrator editor for managed runtime settings.
///
/// Navigation is intentionally owned by the caller. Both this UI and the
/// backend continue to enforce the administrator role.
class AdminRuntimeSettingsScreen extends StatefulWidget {
  const AdminRuntimeSettingsScreen({super.key});

  @override
  State<AdminRuntimeSettingsScreen> createState() =>
      _AdminRuntimeSettingsScreenState();
}

class _AdminRuntimeSettingsScreenState
    extends State<AdminRuntimeSettingsScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  final Map<String, TextEditingController> _secretControllers =
      <String, TextEditingController>{};

  List<RuntimeSettingsGroup> _groups = const <RuntimeSettingsGroup>[];
  RuntimeSettingsGroup? _group;
  RuntimeSettingsChange? _change;
  RuntimeSettingsDiagnostics? _diagnostics;
  List<RuntimeSettingsHistoryItem> _history =
      const <RuntimeSettingsHistoryItem>[];
  Map<String, Object?> _draft = <String, Object?>{};
  Map<String, Object?> _baseline = <String, Object?>{};
  final Map<String, RuntimeSecretOperation> _secretOperations =
      <String, RuntimeSecretOperation>{};
  Map<String, String> _fieldErrors = <String, String>{};
  String? _selectedGroupKey;
  String _overviewError = '';
  String _detailError = '';
  String _diagnosticsError = '';
  RuntimeSettingsNotice? _notice;
  _PendingRuntimeAction? _pendingAction;
  int _baselineVersion = 0;
  int _draftGeneration = 0;
  int _detailRequest = 0;
  bool _initialLoading = true;
  bool _groupsLoading = false;
  bool _detailLoading = false;
  bool _diagnosticsLoading = false;
  bool _busy = false;
  bool _initialLoadStarted = false;
  bool _controllersDisposed = false;
  bool _lastAdminAccess = false;
  bool _actionDialogOpen = false;
  int _groupPickerGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _initialLoadStarted) return;
      if (context.read<AppState>().hasAdminAccess) {
        _initialLoadStarted = true;
        unawaited(_loadInitial());
      } else {
        setState(() => _initialLoading = false);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hasAdminAccess = context.watch<AppState>().hasAdminAccess;
    if (!hasAdminAccess && _lastAdminAccess) {
      final closeActionDialog = _actionDialogOpen;
      _detailRequest += 1;
      _initialLoadStarted = false;
      _initialLoading = false;
      _groups = const <RuntimeSettingsGroup>[];
      _group = null;
      _change = null;
      _diagnostics = null;
      _history = const <RuntimeSettingsHistoryItem>[];
      _selectedGroupKey = null;
      _draft = <String, Object?>{};
      _baseline = <String, Object?>{};
      _fieldErrors = <String, String>{};
      _notice = null;
      _pendingAction = null;
      _actionDialogOpen = false;
      _clearSensitiveInputs();
      if (closeActionDialog) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context, rootNavigator: true).pop();
          }
        });
      }
    }
    if (hasAdminAccess && !_initialLoadStarted) {
      _initialLoadStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadInitial());
      });
    }
    _lastAdminAccess = hasAdminAccess;
  }

  @override
  void dispose() {
    _clearSensitiveInputs();
    _controllersDisposed = true;
    _passwordController.dispose();
    _reasonController.dispose();
    for (final controller in _secretControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _isDirty => runtimeSettingsDraftChanged(
        config: _draft,
        baseline: _baseline,
        secretOperations: _secretOperations,
      );

  bool get _isStale {
    final group = _group;
    if (group == null || group.activeVersion != _baselineVersion) return true;
    for (final listed in _groups) {
      if (listed.groupKey == group.groupKey) {
        return listed.activeVersion != group.activeVersion;
      }
    }
    return false;
  }

  bool get _hasOpenChange {
    final status = _change?.status;
    return status != null &&
        const <String>{
          'prepared',
          'testing',
          'ready',
          'queued_drain',
          'test_failed',
        }.contains(status);
  }

  Future<void> _loadInitial() async {
    if (!_hasAdminAccess) return;
    await Future.wait<void>(<Future<void>>[
      _loadGroups(),
      _loadDiagnostics(),
    ]);
    final key = _selectedGroupKey;
    if (key != null) {
      await _loadDetail(key, resetDraft: true);
    }
    if (mounted) setState(() => _initialLoading = false);
  }

  bool get _hasAdminAccess =>
      mounted && context.read<AppState>().hasAdminAccess;

  Future<Map<String, dynamic>> _getJson(
    String endpoint, {
    Map<String, Object?>? params,
  }) async {
    if (!_hasAdminAccess) {
      throw const ApiException('Administrator access is required.');
    }
    final result = await context.read<AppState>().fetchMapParsed<
        Map<String, dynamic>>(
      endpoint,
      params: params,
      parser: (json) => json,
      cacheTtl: Duration.zero,
      allowStaleOnError: false,
      cachePolicy: ApiCachePolicy.none,
    );
    return result.data;
  }

  Future<Map<String, dynamic>> _postJson(
    String endpoint, {
    required Map<String, dynamic> body,
  }) async {
    if (!_hasAdminAccess) {
      throw const ApiException('Administrator access is required.');
    }
    return context.read<AppState>().postJson(endpoint, body: body);
  }

  Future<void> _loadGroups() async {
    if (!_hasAdminAccess) return;
    setState(() {
      _groupsLoading = true;
      _overviewError = '';
    });
    try {
      final response = await _getJson('/api/admin/runtime-settings/groups');
      final parsed = _mapList(response['groups'])
          .map(RuntimeSettingsGroup.fromJson)
          .toList(growable: false);
      if (!mounted) return;
      final currentKey = _selectedGroupKey;
      final nextKey = parsed.any((item) => item.groupKey == currentKey)
          ? currentKey
          : parsed.isEmpty
              ? null
              : parsed.first.groupKey;
      setState(() {
        _groups = parsed;
        _selectedGroupKey = nextKey;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _overviewError = _safeReadError(
            error,
            fallback: '설정 그룹을 불러오지 못했습니다.',
          ));
    } finally {
      if (mounted) setState(() => _groupsLoading = false);
    }
  }

  Future<void> _loadDiagnostics() async {
    if (!_hasAdminAccess) return;
    setState(() {
      _diagnosticsLoading = true;
      _diagnosticsError = '';
    });
    try {
      final response =
          await _getJson('/api/admin/runtime-settings/diagnostics');
      final parsed = RuntimeSettingsDiagnostics.fromJson(response);
      if (!mounted) return;
      setState(() {
        _diagnostics = parsed;
        _diagnosticsError = '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _diagnosticsError = _safeReadError(
            error,
            fallback: 'Worker 진단을 불러오지 못했습니다.',
          ));
    } finally {
      if (mounted) setState(() => _diagnosticsLoading = false);
    }
  }

  Future<void> _loadDetail(
    String groupKey, {
    required bool resetDraft,
  }) async {
    if (!_hasAdminAccess || groupKey.isEmpty) return;
    final request = ++_detailRequest;
    setState(() {
      _detailLoading = true;
      _detailError = '';
    });
    try {
      final encodedKey = Uri.encodeComponent(groupKey);
      final values = await Future.wait<Map<String, dynamic>>(<
          Future<Map<String, dynamic>>>[
        _getJson('/api/admin/runtime-settings/groups/$encodedKey'),
        _getJson(
          '/api/admin/runtime-settings/groups/$encodedKey/history',
          params: const <String, Object?>{'limit': 50},
        ),
      ]);
      final groupResponse = values[0];
      final rawGroup = groupResponse['group'];
      if (rawGroup is! Map) {
        throw const FormatException('Invalid runtime settings group.');
      }
      final parsedGroup = RuntimeSettingsGroup.fromJson(
        Map<String, dynamic>.from(rawGroup),
      );
      final rawChange = groupResponse['open_change'];
      final parsedChange = rawChange is Map
          ? RuntimeSettingsChange.fromJson(
              Map<String, dynamic>.from(rawChange),
            )
          : null;
      final parsedHistory = _mapList(values[1]['items'])
          .map(RuntimeSettingsHistoryItem.fromJson)
          .toList(growable: false);
      if (!mounted ||
          request != _detailRequest ||
          _selectedGroupKey != groupKey) {
        return;
      }
      setState(() {
        _group = parsedGroup;
        _change = parsedChange;
        _history = parsedHistory;
        if (resetDraft) {
          _draft = Map<String, Object?>.of(parsedGroup.config);
          _baseline = Map<String, Object?>.of(parsedGroup.config);
          _baselineVersion = parsedGroup.activeVersion;
          _fieldErrors = <String, String>{};
          _clearSecretDraft();
          _draftGeneration += 1;
        }
        _detailError = '';
      });
    } catch (error) {
      if (!mounted ||
          request != _detailRequest ||
          _selectedGroupKey != groupKey) {
        return;
      }
      setState(() => _detailError = _safeReadError(
            error,
            fallback: '설정 상세와 변경 이력을 불러오지 못했습니다.',
          ));
    } finally {
      if (mounted && request == _detailRequest) {
        setState(() => _detailLoading = false);
      }
    }
  }

  Future<void> _refreshAll() async {
    if (!_hasAdminAccess) return;
    await Future.wait<void>(<Future<void>>[
      _loadGroups(),
      _loadDiagnostics(),
    ]);
    final key = _selectedGroupKey;
    if (key != null) {
      await _loadDetail(key, resetDraft: false);
    }
  }

  Future<void> _reloadCurrentGroup() async {
    final key = _group?.groupKey;
    if (key == null) return;
    await _loadGroups();
    await _loadDetail(key, resetDraft: true);
  }

  void _selectGroup(String? groupKey) {
    if (groupKey == null || groupKey == _selectedGroupKey || _busy) return;
    if (_isDirty) {
      setState(() {
        _groupPickerGeneration += 1;
        _notice = const RuntimeSettingsNotice(
          text: '저장하지 않은 변경사항이 있어 설정 그룹을 바꿀 수 없습니다.',
          isError: true,
        );
      });
      return;
    }
    _detailRequest += 1;
    setState(() {
      _selectedGroupKey = groupKey;
      _group = null;
      _change = null;
      _history = const <RuntimeSettingsHistoryItem>[];
      _detailError = '';
      _notice = null;
      _draft = <String, Object?>{};
      _baseline = <String, Object?>{};
      _fieldErrors = <String, String>{};
      _clearSecretDraft();
    });
    unawaited(_loadDetail(groupKey, resetDraft: true));
  }

  void _setField(RuntimeSettingField field, Object? value) {
    setState(() {
      _draft[field.field] = value;
      _fieldErrors.remove(field.field);
    });
  }

  TextEditingController _secretController(String field) {
    return _secretControllers.putIfAbsent(
      field,
      TextEditingController.new,
    );
  }

  void _setSecretOperation(
    RuntimeSettingField field,
    RuntimeSecretOperation operation,
  ) {
    final controller = _secretController(field.field);
    if (operation != RuntimeSecretOperation.replace) controller.clear();
    setState(() {
      if (operation == RuntimeSecretOperation.keep) {
        _secretOperations.remove(field.field);
      } else {
        _secretOperations[field.field] = operation;
      }
      _fieldErrors.remove(field.field);
    });
  }

  void _setSecretValue(RuntimeSettingField field) {
    setState(() => _fieldErrors.remove(field.field));
  }

  Map<String, String> _currentSecretValues() {
    return <String, String>{
      for (final entry in _secretOperations.entries)
        if (entry.value == RuntimeSecretOperation.replace)
          entry.key: _secretControllers[entry.key]?.text ?? '',
    };
  }

  Map<String, dynamic> _secretPayload() {
    final payload = <String, dynamic>{};
    for (final entry in _secretOperations.entries) {
      if (entry.value == RuntimeSecretOperation.keep) continue;
      if (entry.value == RuntimeSecretOperation.replace) {
        payload[entry.key] = <String, Object?>{
          'operation': entry.value.apiValue,
          'value': _secretControllers[entry.key]?.text ?? '',
        };
      } else {
        payload[entry.key] = <String, Object?>{
          'operation': entry.value.apiValue,
        };
      }
    }
    return payload;
  }

  void _clearSecretDraft() {
    for (final controller in _secretControllers.values) {
      controller.clear();
    }
    _secretOperations.clear();
  }

  void _clearSensitiveInputs() {
    if (_controllersDisposed) return;
    _passwordController.clear();
    _reasonController.clear();
    _clearSecretDraft();
  }

  RuntimeSettingsValidation _validateDraft() {
    final group = _group;
    if (group == null) {
      return const RuntimeSettingsValidation(<String, String>{
        '_form': '설정 그룹을 다시 불러오세요.',
      });
    }
    return validateRuntimeSettingsDraft(
      fields: group.fields,
      config: _draft,
      secretOperations: _secretOperations,
      secretValues: _currentSecretValues(),
    );
  }

  void _requestAction(_PendingRuntimeAction action) {
    if (_busy || !_hasAdminAccess) return;
    if (action.kind == _RuntimeActionKind.prepare) {
      final validation = _validateDraft();
      if (!validation.isValid) {
        setState(() {
          _fieldErrors = Map<String, String>.of(validation.errors);
          _notice = const RuntimeSettingsNotice(
            text: '입력값을 확인한 뒤 다시 시도하세요.',
            isError: true,
          );
        });
        return;
      }
    }
    if (action.kind != _RuntimeActionKind.cancel && _isStale) {
      _showNotice(
        const RuntimeSettingsNotice(
          text: '현재 설정 버전이 변경되었습니다. 새로고침 후 다시 시도하세요.',
          isError: true,
        ),
      );
      return;
    }
    _passwordController.clear();
    _reasonController.text = action.kind == _RuntimeActionKind.rollback
        ? '버전 ${action.version}으로 되돌림'
        : '';
    setState(() {
      _notice = null;
      _pendingAction = action;
    });
    unawaited(_showReauthenticationDialog());
  }

  Future<void> _showReauthenticationDialog() async {
    final action = _pendingAction;
    if (action == null || !mounted) return;
    _actionDialogOpen = true;
    final outcomeNotice = await showDialog<RuntimeSettingsNotice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        var dialogBusy = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('${action.label} · 관리자 재인증'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      switch (action.kind) {
                        _RuntimeActionKind.prepare =>
                          '입력값을 다시 검증하고 새 변경을 준비합니다.',
                        _RuntimeActionKind.test =>
                          '비파괴 연결 검증을 실행합니다.',
                        _RuntimeActionKind.apply =>
                          '준비된 변경을 적용합니다. EasyPOS는 drain 절차를 따릅니다.',
                        _RuntimeActionKind.cancel =>
                          '현재 준비된 변경을 취소합니다.',
                        _RuntimeActionKind.rollback =>
                          '활성 설정을 v${action.version}으로 롤백합니다. 새 버전으로 기록됩니다.',
                      },
                    ),
                    if (action.kind == _RuntimeActionKind.prepare ||
                        action.kind == _RuntimeActionKind.rollback) ...[
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('runtime-settings-reason'),
                        controller: _reasonController,
                        enabled: !dialogBusy,
                        maxLength: 500,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '변경 사유',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('runtime-settings-password'),
                      controller: _passwordController,
                      enabled: !dialogBusy,
                      obscureText: true,
                      autofillHints: const <String>[
                        AutofillHints.password,
                      ],
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: '현재 관리자 비밀번호',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                      onSubmitted: (_) {
                        if (!dialogBusy &&
                            _passwordController.text.isNotEmpty) {
                          setDialogState(() => dialogBusy = true);
                          unawaited(_executePendingAction());
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '비밀번호와 새 보안 값은 저장하거나 표시하지 않습니다.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: dialogBusy ? null : _dismissActionDialog,
                  child: const Text('취소'),
                ),
                FilledButton(
                  key: const Key('runtime-settings-confirm-action'),
                  onPressed: dialogBusy || _passwordController.text.isEmpty
                      ? null
                      : () {
                          setDialogState(() => dialogBusy = true);
                          unawaited(_executePendingAction());
                        },
                  child: Text(dialogBusy ? '처리 중…' : '확인'),
                ),
              ],
            );
          },
        );
      },
    );
    debugPrint(
      'Runtime action dialog returned ${action.apiAction}: '
      '${outcomeNotice?.text ?? "no notice"}',
    );
    _actionDialogOpen = false;
    if (mounted && _hasAdminAccess && outcomeNotice != null) {
      _showNotice(outcomeNotice);
    } else {
      debugPrint(
        'Runtime action notice skipped: mounted=$mounted '
        'admin=$_hasAdminAccess',
      );
    }
  }

  void _dismissActionDialog() {
    if (_busy) return;
    _clearSensitiveInputs();
    if (mounted) {
      setState(() => _pendingAction = null);
      if (_actionDialogOpen) {
        _actionDialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<void> _executePendingAction() async {
    final pending = _pendingAction;
    final group = _group;
    if (pending == null || _busy) return;
    if (!_hasAdminAccess || group == null) {
      _showNotice(
        const RuntimeSettingsNotice(
          text: '관리자 권한이 필요합니다. 다시 로그인한 뒤 시도하세요.',
          isError: true,
        ),
      );
      _dismissActionDialog();
      return;
    }
    if (_passwordController.text.isEmpty) return;
    if (pending.kind != _RuntimeActionKind.cancel && _isStale) {
      _showNotice(
        const RuntimeSettingsNotice(
          text: '현재 설정 버전이 변경되었습니다. 새로고침 후 다시 시도하세요.',
          isError: true,
        ),
      );
      _dismissActionDialog();
      return;
    }

    setState(() => _busy = true);
    final password = _passwordController.text;
    RuntimeSettingsNotice? outcomeNotice;
    try {
      final actionResult = await _performAction(
        pending: pending,
        group: group,
        password: password,
      );
      outcomeNotice = runtimeSettingsActionNotice(
        pending.apiAction,
        actionResult,
      );
      debugPrint(
        'Runtime action ${pending.apiAction} produced '
        '${outcomeNotice.text}',
      );
      await Future.wait<void>(<Future<void>>[
        _loadGroups(),
        _loadDiagnostics(),
      ]);
      if (mounted && _selectedGroupKey == group.groupKey) {
        await _loadDetail(group.groupKey, resetDraft: true);
      }
    } catch (error) {
      if (mounted) {
        outcomeNotice = RuntimeSettingsNotice(
          text: _safeMutationError(error, pending.kind),
          isError: true,
        );
      }
    } finally {
      _clearSensitiveInputs();
      if (mounted) {
        setState(() {
          _busy = false;
          _pendingAction = null;
        });
        if (_actionDialogOpen) {
          _actionDialogOpen = false;
          debugPrint(
            'Runtime action ${pending.apiAction} closing dialog with '
            '${outcomeNotice?.text ?? "no notice"}',
          );
          Navigator.of(context, rootNavigator: true).pop(outcomeNotice);
        } else {
          debugPrint(
            'Runtime action ${pending.apiAction} did not find an open dialog',
          );
        }
      }
    }
  }

  Future<Map<String, dynamic>> _performAction({
    required _PendingRuntimeAction pending,
    required RuntimeSettingsGroup group,
    required String password,
  }) async {
    final encodedGroup = Uri.encodeComponent(group.groupKey);
    final requestId = _newRequestId();
    switch (pending.kind) {
      case _RuntimeActionKind.prepare:
        final reason = _reasonController.text.trim().isEmpty
            ? '시스템 설정 변경'
            : _reasonController.text.trim();
        final config = Map<String, dynamic>.of(_draft);
        final secrets = _secretPayload();
        final validation = await _postJson(
          '/api/admin/runtime-settings/groups/$encodedGroup/validate',
          body: <String, dynamic>{
            'config': config,
            'secrets': secrets,
            'reauth_password': password,
          },
        );
        if (validation['valid'] != true) {
          throw const ApiException(
            'Runtime settings validation was unsuccessful.',
            statusCode: 422,
          );
        }
        return _postJson(
          '/api/admin/runtime-settings/groups/$encodedGroup/prepare',
          body: <String, dynamic>{
            'base_version': _baselineVersion,
            'config': config,
            'secrets': secrets,
            'request_id': requestId,
            'reason': reason,
            'reauth_password': password,
          },
        );
      case _RuntimeActionKind.test:
        final change = _change;
        if (change == null) {
          throw const ApiException('Change not found.', statusCode: 404);
        }
        return _postJson(
          '/api/admin/runtime-settings/changes/${Uri.encodeComponent(change.changeId)}/test',
          body: <String, dynamic>{'reauth_password': password},
        );
      case _RuntimeActionKind.apply:
        final change = _change;
        if (change == null) {
          throw const ApiException('Change not found.', statusCode: 404);
        }
        return _postJson(
          '/api/admin/runtime-settings/changes/${Uri.encodeComponent(change.changeId)}/apply',
          body: <String, dynamic>{'reauth_password': password},
        );
      case _RuntimeActionKind.cancel:
        final change = _change;
        if (change == null) {
          throw const ApiException('Change not found.', statusCode: 404);
        }
        return _postJson(
          '/api/admin/runtime-settings/changes/${Uri.encodeComponent(change.changeId)}/cancel',
          body: <String, dynamic>{'reauth_password': password},
        );
      case _RuntimeActionKind.rollback:
        final targetVersion = pending.version;
        if (targetVersion == null) {
          throw const ApiException('Rollback version is missing.');
        }
        final reason = _reasonController.text.trim().isEmpty
            ? '시스템 설정 롤백'
            : _reasonController.text.trim();
        return _postJson(
          '/api/admin/runtime-settings/groups/$encodedGroup/rollback',
          body: <String, dynamic>{
            'target_version': targetVersion,
            'request_id': requestId,
            'reason': reason,
            'reauth_password': password,
          },
        );
    }
  }

  Future<void> _refreshChangeStatus() async {
    final change = _change;
    if (change == null || _busy || !_hasAdminAccess) return;
    try {
      final response = await _getJson(
        '/api/admin/runtime-settings/changes/${Uri.encodeComponent(change.changeId)}',
      );
      final rawChange = response['change'];
      if (rawChange is! Map) {
        throw const FormatException('Invalid runtime settings change.');
      }
      final updated = RuntimeSettingsChange.fromJson(
        Map<String, dynamic>.from(rawChange),
      );
      if (!mounted || _change?.changeId != change.changeId) return;
      setState(() => _change = updated);
    } catch (error) {
      if (mounted) {
        _showNotice(
          RuntimeSettingsNotice(
            text: _safeReadError(
              error,
              fallback: '변경 상태를 새로고침하지 못했습니다.',
            ),
            isError: true,
          ),
        );
      }
    }
  }

  void _showNotice(RuntimeSettingsNotice notice) {
    if (!mounted) return;
    setState(() => _notice = notice);
  }

  String _safeReadError(Object error, {required String fallback}) {
    if (error is ApiException) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        return '권한이 없거나 세션이 만료되었습니다. 관리자 계정으로 다시 로그인하세요.';
      }
      if (error.statusCode == 409) {
        return '설정 버전 또는 변경 상태가 달라졌습니다. 새로고침 후 다시 시도하세요.';
      }
    }
    // Never surface raw response bodies or exception text in this screen.
    return fallback;
  }

  String _safeMutationError(Object error, _RuntimeActionKind action) {
    if (error is ApiException) {
      if (error.statusCode == 401) {
        return '세션이 만료되었습니다. 관리자 계정으로 다시 로그인하세요.';
      }
      if (error.statusCode == 403) {
        return '재인증에 실패했거나 관리자 권한이 없습니다. 비밀번호를 확인하세요.';
      }
      if (error.statusCode == 409) {
        return '설정 버전 또는 변경 상태가 달라졌습니다. 새로고침 후 다시 시도하세요.';
      }
      if (error.statusCode == 422) {
        return action == _RuntimeActionKind.prepare
            ? '설정값 또는 변경 사유를 확인하세요.'
            : '요청 조건을 확인한 뒤 다시 시도하세요.';
      }
    }
    return switch (action) {
      _RuntimeActionKind.prepare =>
        '설정 변경을 준비하지 못했습니다. 설정 상태를 새로고침하세요.',
      _RuntimeActionKind.test =>
        '연결 테스트를 완료하지 못했습니다. 변경 상태를 확인하세요.',
      _RuntimeActionKind.apply =>
        '설정을 적용하지 못했습니다. 변경 상태를 새로고침하세요.',
      _RuntimeActionKind.cancel =>
        '변경을 취소하지 못했습니다. 변경 상태를 새로고침하세요.',
      _RuntimeActionKind.rollback =>
        '버전을 롤백하지 못했습니다. 현재 설정을 새로고침하세요.',
    };
  }

  Widget _buildNotice(RuntimeSettingsNotice notice) {
    final colorScheme = Theme.of(context).colorScheme;
    final color =
        notice.isError ? colorScheme.error : colorScheme.primary;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            notice.isError ? Icons.error_outline : Icons.info_outline,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                notice.text,
                key: const Key('runtime-settings-notice'),
              ),
            ),
          ),
          IconButton(
            tooltip: '알림 닫기',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _notice = null),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAdminAccess = context.watch<AppState>().hasAdminAccess;
    return AppScreen(
      title: '시스템 설정',
      subtitle: '관리형 런타임 설정과 적용 상태를 관리합니다.',
      actions: <Widget>[
        IconButton(
          tooltip: '새로고침',
          onPressed: hasAdminAccess && !_groupsLoading && !_busy
              ? _refreshAll
              : null,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: !hasAdminAccess
          ? const PermissionState(
              requiredRole: 'admin',
              message: '시스템 런타임 설정은 관리자 전용입니다.',
            )
          : _buildAdminBody(),
    );
  }

  Widget _buildAdminBody() {
    if (_initialLoading && _groups.isEmpty) {
      return const LoadingState(message: '런타임 설정을 불러오는 중입니다.');
    }
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (_notice case final notice?) _buildNotice(notice),
          _buildDiagnosticsPanel(),
          _buildGroupPicker(),
          if (_overviewError.isNotEmpty)
            _buildErrorPanel(
              title: '설정 그룹을 불러오지 못했습니다.',
              description: _overviewError,
              onRetry: _loadInitial,
            ),
          if (_detailLoading && _group == null)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_detailError.isNotEmpty)
            _buildErrorPanel(
              title: '설정 상세를 불러오지 못했습니다.',
              description: _detailError,
              onRetry: _reloadCurrentGroup,
            ),
          if (_group != null) ...<Widget>[
            if (_isStale) _buildStaleNotice(),
            _buildSettingsPanel(_group!),
            _buildWorkflowPanel(),
            _buildHistoryPanel(_group!),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsPanel() {
    final diagnostics = _diagnostics;
    return Panel(
      title: 'Worker 수렴 상태',
      subtitle: diagnostics == null
          ? '현재 런타임 설정 revision을 관찰하는 worker 진단입니다.'
          : '환경 ${diagnostics.environment} · ${_formatDate(diagnostics.checkedAt)} 확인',
      child: _diagnosticsLoading && diagnostics == null
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          : _diagnosticsError.isNotEmpty
              ? _inlineError(
                  _diagnosticsError,
                  onRetry: _loadDiagnostics,
                )
              : diagnostics == null
                  ? const Text('진단 정보가 없습니다.')
                  : _buildDiagnosticsContents(diagnostics),
    );
  }

  Widget _buildDiagnosticsContents(
    RuntimeSettingsDiagnostics diagnostics,
  ) {
    final convergenceOk = diagnostics.normalWorkers > 0 &&
        diagnostics.allNormalWorkersConverged;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _diagnosticChip(
              '스키마',
              'v${diagnostics.schemaCurrentVersion} / v${diagnostics.schemaExpectedVersion}',
              diagnostics.schemaCurrent,
            ),
            _diagnosticChip(
              '정상 worker',
              '${diagnostics.normalWorkers}',
              diagnostics.normalWorkers > 0,
            ),
            _diagnosticChip(
              '수렴 worker',
              '${diagnostics.convergedNormalWorkers} / ${diagnostics.normalWorkers}',
              convergenceOk,
            ),
            _diagnosticChip(
              '적용 대기 그룹',
              '${diagnostics.pendingGroups}',
              diagnostics.pendingGroups == 0,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (diagnostics.workers.isEmpty)
          const Text('관찰된 worker가 없습니다.')
        else
          ...diagnostics.workers.map(_buildWorkerRow),
        if (!diagnostics.ok) ...<Widget>[
          const SizedBox(height: 8),
          const Text(
            '진단 결과 확인이 필요합니다.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }

  Widget _diagnosticChip(String label, String value, bool ok) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = ok ? colorScheme.primary : colorScheme.error;
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildWorkerRow(RuntimeSettingsWorker worker) {
    final normal = worker.freshness == 'normal';
    final stale = worker.freshness == 'stale';
    final color = normal
        ? Theme.of(context).colorScheme.primary
        : stale
            ? Theme.of(context).colorScheme.tertiary
            : Theme.of(context).colorScheme.error;
    final sha = worker.releaseSha.length > 12
        ? worker.releaseSha.substring(0, 12)
        : worker.releaseSha;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          _statusChip(worker.freshness, color),
          Text(
            worker.role.isEmpty ? worker.workerId : worker.role,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (sha.isNotEmpty)
            Text(
              sha,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          Text(
            '${worker.converged ? "revision 수렴" : "revision 지연"} · ${worker.ageSeconds.round()}초 전',
          ),
        ],
      ),
    );
  }

  Widget _buildGroupPicker() {
    return Panel(
      title: '설정 그룹',
      subtitle: '변경은 선택한 그룹의 소유 필드에만 적용됩니다.',
      child: _groupsLoading && _groups.isEmpty
          ? const LinearProgressIndicator()
          : _groups.isEmpty
              ? const Text('사용 가능한 설정 그룹이 없습니다.')
              : DropdownButtonFormField<String>(
                  key: ValueKey(
                    'runtime-settings-group-picker-${_selectedGroupKey ?? "none"}-$_groupPickerGeneration',
                  ),
                  initialValue: _selectedGroupKey,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '관리형 설정 그룹',
                    border: OutlineInputBorder(),
                  ),
                  items: _groups
                      .map(
                        (group) => DropdownMenuItem<String>(
                          value: group.groupKey,
                          child: Text(
                            '${group.label} · ${group.adopted ? "v${group.activeVersion}" : "관리 도입 필요"}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _busy ? null : _selectGroup,
                ),
    );
  }

  Widget _buildStaleNotice() {
    final group = _group;
    var current = group?.activeVersion;
    for (final listed in _groups) {
      if (listed.groupKey == group?.groupKey) {
        current = listed.activeVersion;
        break;
      }
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '다른 변경으로 활성 버전이 v$current로 바뀌었습니다. 초안을 덮어쓰지 않도록 새로고침이 필요합니다.',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _reloadCurrentGroup,
            icon: const Icon(Icons.refresh),
            label: const Text('최신 설정 불러오기'),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsPanel(RuntimeSettingsGroup group) {
    final unavailable = group.safeErrorCode != null ||
        group.source == 'unavailable';
    final canPrepare = !unavailable &&
        !_isStale &&
        !_busy &&
        !_hasOpenChange &&
        (!group.adopted || _isDirty);
    return Panel(
      title: '${group.label} 설정',
      subtitle:
          '환경 ${group.source} · 활성 버전 v${group.activeVersion} · session epoch ${group.sessionEpoch} · ${group.adopted ? "관리형" : "초기 관리 도입"}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (!group.adopted && !unavailable)
            _infoBox(
              '초기 도입은 현재 값을 변경하지 않고 관리형 ledger로 옮깁니다. 먼저 도입한 뒤 별도 변경을 준비하고 테스트하세요.',
            ),
          if (unavailable)
            _inlineError(
              '현재 설정 저장소에서 이 그룹을 사용할 수 없습니다.',
              onRetry: _reloadCurrentGroup,
            )
          else if (group.fields.isEmpty)
            const Text('편집 가능한 설정 필드가 없습니다.')
          else
            ...group.fields.map(
              (field) => Padding(
                key: ValueKey(
                  '${group.groupKey}:${field.field}:$_draftGeneration',
                ),
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildSettingField(
                  field,
                  enabled: group.adopted && !_busy && !_isStale,
                ),
              ),
            ),
          const Divider(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                _isDirty ? '변경사항 있음' : '저장된 상태',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (canPrepare)
                FilledButton.icon(
                  key: const Key('runtime-settings-prepare'),
                  onPressed: () => _requestAction(
                    const _PendingRuntimeAction(_RuntimeActionKind.prepare),
                  ),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(
                    group.adopted ? '검증 후 준비' : '현재 설정 관리 도입',
                  ),
                ),
            ],
          ),
          if (_fieldErrors.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _fieldErrors.values.first,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingField(
    RuntimeSettingField field, {
    required bool enabled,
  }) {
    final error = _fieldErrors[field.field];
    final label = field.secret
        ? '${field.label} · ${field.configured == true ? "설정됨" : "미설정"}'
        : field.label;
    if (field.secret) {
      final operation =
          _secretOperations[field.field] ?? RuntimeSecretOperation.keep;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          DropdownButtonFormField<RuntimeSecretOperation>(
            key: Key('runtime-secret-operation-${field.field}'),
            initialValue: operation,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '보안 값 작업',
              border: OutlineInputBorder(),
            ),
            items: const <DropdownMenuItem<RuntimeSecretOperation>>[
              DropdownMenuItem(
                value: RuntimeSecretOperation.keep,
                child: Text('유지'),
              ),
              DropdownMenuItem(
                value: RuntimeSecretOperation.replace,
                child: Text('교체'),
              ),
              DropdownMenuItem(
                value: RuntimeSecretOperation.clear,
                child: Text('삭제'),
              ),
            ],
            onChanged: enabled
                ? (next) {
                    if (next != null) _setSecretOperation(field, next);
                  }
                : null,
          ),
          if (operation == RuntimeSecretOperation.replace) ...<Widget>[
            const SizedBox(height: 8),
            TextField(
              controller: _secretController(field.field),
              enabled: enabled,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: '${field.label} 새 값',
                hintText: '새 보안 값 (표시하지 않음)',
                border: const OutlineInputBorder(),
                errorText: error,
              ),
              onChanged: (_) => _setSecretValue(field),
            ),
          ] else if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      );
    }

    final value = _draft[field.field] ?? field.value;
    switch (field.kind) {
      case 'boolean':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(field.label),
          subtitle: error == null ? null : Text(error),
          value: value == true,
          onChanged: enabled ? (next) => _setField(field, next) : null,
        );
      case 'enum':
        final choices = field.choices;
        final selected = choices.contains(value?.toString())
            ? value.toString()
            : null;
        return DropdownButtonFormField<String>(
          initialValue: selected,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: field.label,
            border: const OutlineInputBorder(),
            errorText: error,
          ),
          items: choices
              .map(
                (choice) => DropdownMenuItem<String>(
                  value: choice,
                  child: Text(choice, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(growable: false),
          onChanged:
              enabled ? (next) => _setField(field, next ?? '') : null,
        );
      case 'object':
        return TextFormField(
          key: ValueKey('object:${field.field}:$_draftGeneration'),
          initialValue: _formatJson(value ?? <String, Object?>{}),
          enabled: enabled,
          minLines: 4,
          maxLines: 8,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: field.label,
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
            errorText: error,
          ),
          onChanged: (text) {
            try {
              _setField(field, _decodeJson(text));
            } on FormatException {
              _setField(field, text);
            }
          },
        );
      case 'integer':
      case 'string':
      case 'url':
        return TextFormField(
          key: ValueKey('text:${field.field}:$_draftGeneration'),
          initialValue: value?.toString() ?? '',
          enabled: enabled,
          keyboardType: field.kind == 'integer'
              ? const TextInputType.numberWithOptions(signed: true)
              : TextInputType.text,
          decoration: InputDecoration(
            labelText: field.label,
            border: const OutlineInputBorder(),
            errorText: error,
            helperText: _fieldHelper(field),
          ),
          onChanged: (text) {
            if (field.kind == 'integer') {
              _setField(field, int.tryParse(text) ?? text);
            } else {
              _setField(field, text);
            }
          },
        );
      default:
        return InputDecorator(
          decoration: InputDecoration(
            labelText: field.label,
            border: const OutlineInputBorder(),
            errorText: error,
          ),
          child: const Text('지원하지 않는 설정 형식'),
        );
    }
  }

  Widget _buildWorkflowPanel() {
    final change = _change;
    if (change == null) {
      return const Panel(
        title: '현재 변경 흐름',
        subtitle: '검증·테스트·적용은 항상 최신 변경 ID를 사용합니다.',
        child: Text('진행 중인 설정 변경이 없습니다.'),
      );
    }
    final steps = <String>['초안', '준비', '테스트', '적용 대기', '적용'];
    final activeIndex = switch (change.status) {
      'prepared' => 1,
      'testing' || 'test_failed' => 2,
      'ready' || 'queued_drain' => 3,
      'applied' => 4,
      _ => -1,
    };
    final isOpen = _hasOpenChange;
    final canTest = isOpen && change.status != 'queued_drain' && !_busy;
    final canApply = !_busy &&
        (change.status == 'ready' ||
            (_group?.groupKey == 'easypos' &&
                <String>{'prepared', 'queued_drain'}
                    .contains(change.status)));
    final canCancel = isOpen && !_busy;
    final probe = change.probe;
    return Panel(
      title: '현재 변경 흐름',
      subtitle: '변경 ID ${change.changeId}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildWorkflowSteps(steps, activeIndex),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              _statusChip(
                _statusLabel(change.status),
                _statusColor(change.status),
              ),
              Text('기준 버전 v${change.baseVersion}'),
              if (change.appliedVersion != null)
                Text('적용 버전 v${change.appliedVersion}'),
              if (change.actor.isNotEmpty) Text('요청자 ${change.actor}'),
            ],
          ),
          if (change.createdAt != null || change.expiresAt != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              '생성 ${_formatDate(change.createdAt)} · 만료 ${_formatDate(change.expiresAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (change.safeErrorCode != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '안전 오류 코드: ${change.safeErrorCode}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (probe != null) ...<Widget>[
            const SizedBox(height: 12),
            _buildProbeSummary(probe),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: _busy ? null : _refreshChangeStatus,
                icon: const Icon(Icons.sync),
                label: const Text('상태 새로고침'),
              ),
              if (canTest)
                OutlinedButton.icon(
                  onPressed: _isStale
                      ? null
                      : () => _requestAction(
                            const _PendingRuntimeAction(
                              _RuntimeActionKind.test,
                            ),
                          ),
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('연결 테스트'),
                ),
              if (canApply)
                FilledButton.icon(
                  onPressed: _isStale
                      ? null
                      : () => _requestAction(
                            const _PendingRuntimeAction(
                              _RuntimeActionKind.apply,
                            ),
                          ),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('적용'),
                ),
              if (canCancel)
                OutlinedButton.icon(
                  onPressed: () => _requestAction(
                    const _PendingRuntimeAction(_RuntimeActionKind.cancel),
                  ),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('취소'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowSteps(
    List<String> steps,
    int activeIndex,
  ) {
    return Wrap(
      spacing: 0,
      runSpacing: 8,
      children: <Widget>[
        for (var index = 0; index < steps.length; index += 1)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CircleAvatar(
                  radius: 12,
                  backgroundColor: index <= activeIndex
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  foregroundColor: index <= activeIndex
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  child: Text('${index + 1}', style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 5),
                Text(
                  steps[index],
                  style: TextStyle(
                    fontWeight:
                        index == activeIndex ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildProbeSummary(RuntimeSettingsProbe probe) {
    final resultLabel = switch (probe.status) {
      'passed' => '성공',
      'partial' => '일부 검증',
      'deferred' => '적용 단계에서 검증',
      'failed' => '실패',
      _ => '결과 없음',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '연결 검증 · $resultLabel${probe.latencyMs == null ? "" : " · ${probe.latencyMs!.round()}ms"}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (probe.scope.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text('검증 범위: ${probe.scope.join(", ")}'),
          ],
          if (probe.unchecked.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text('미검증: ${probe.unchecked.join(", ")}'),
          ],
          if (probe.safeErrorCode != null) ...<Widget>[
            const SizedBox(height: 4),
            Text('안전 오류 코드: ${probe.safeErrorCode}'),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryPanel(RuntimeSettingsGroup group) {
    return Panel(
      title: '변경 이력',
      subtitle: '비밀 값은 표시하지 않고 변경 필드와 버전만 기록합니다.',
      child: _history.isEmpty
          ? const Text('변경 이력이 없습니다.')
          : Column(
              children: _history
                  .map((item) => _buildHistoryRow(group, item))
                  .toList(growable: false),
            ),
    );
  }

  Widget _buildHistoryRow(
    RuntimeSettingsGroup group,
    RuntimeSettingsHistoryItem item,
  ) {
    final canRollback = group.adopted &&
        item.version != null &&
        item.version != group.activeVersion &&
        !_isStale &&
        !_busy;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                item.version == null ? '-' : 'v${item.version}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
              _statusChip(
                item.action,
                item.action == 'rollback'
                    ? Theme.of(context).colorScheme.tertiary
                    : Theme.of(context).colorScheme.outline,
              ),
              if (item.actor.isNotEmpty) Text(item.actor),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            item.changedFields.isEmpty
                ? '변경 필드 없음'
                : item.changedFields.join(', '),
          ),
          if (item.createdAt != null) ...<Widget>[
            const SizedBox(height: 3),
            Text(
              _formatDate(item.createdAt),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (canRollback) ...<Widget>[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: Key('runtime-settings-rollback-${item.version}'),
                onPressed: () => _requestAction(
                  _PendingRuntimeAction(
                    _RuntimeActionKind.rollback,
                    version: item.version,
                  ),
                ),
                icon: const Icon(Icons.settings_backup_restore),
                label: Text('v${item.version}으로 롤백'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorPanel({
    required String title,
    required String description,
    required VoidCallback onRetry,
  }) {
    return Panel(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(description),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('다시 불러오기'),
          ),
        ],
      ),
    );
  }

  Widget _inlineError(String message, {required VoidCallback onRetry}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(message),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: _busy ? null : onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('다시 시도'),
        ),
      ],
    );
  }

  Widget _infoBox(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text),
    );
  }

  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: TextStyle(color: color)),
    );
  }

  Color _statusColor(String status) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      'ready' || 'applied' => scheme.primary,
      'queued_drain' || 'prepared' || 'testing' => scheme.tertiary,
      'test_failed' || 'activation_failed' || 'failed' => scheme.error,
      _ => scheme.outline,
    };
  }

  String _statusLabel(String status) {
    return switch (status) {
      'prepared' => '준비됨',
      'testing' => '테스트 중',
      'ready' => '적용 승인됨',
      'queued_drain' => 'POS 작업 대기',
      'applied' => '적용 완료',
      'cancelled' => '취소됨',
      'expired' => '만료됨',
      'test_failed' => '테스트 실패',
      'activation_failed' => '적용 실패',
      _ => '상태 확인 필요',
    };
  }

  String? _fieldHelper(RuntimeSettingField field) {
    if (field.kind == 'url') return 'HTTPS 주소를 입력하세요.';
    if (field.kind != 'integer') return null;
    if (field.minimum == null && field.maximum == null) return null;
    if (field.minimum != null && field.maximum != null) {
      return '범위 ${field.minimum}–${field.maximum}';
    }
    if (field.minimum != null) return '최소 ${field.minimum}';
    return '최대 ${field.maximum}';
  }
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

Object? _decodeJson(String text) {
  return jsonDecode(text);
}

String _formatJson(Object? value) {
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } on JsonUnsupportedObjectError {
    return '{}';
  }
}

String _formatDate(String? value) {
  if (value == null || value.isEmpty) return '-';
  return value.replaceFirst('T', ' ').split('.').first;
}

String _newRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
