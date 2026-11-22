import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../state/app_state.dart';

const _auditLogLimit = 30;
const _roles = <String>['viewer', 'operator', 'admin'];

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _loginIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _auditFilterController = TextEditingController();

  List<_AdminUser> _users = const [];
  List<_AdminAuditLog> _auditLogs = const [];
  String _newRole = 'viewer';
  String _mutationMessage = '';
  String _mutationError = '';
  String _usersError = '';
  String _auditLogsError = '';
  bool _usersLoading = true;
  bool _auditLogsLoading = true;
  bool _mutationBusy = false;
  bool _initialLoadStarted = false;
  int _usersRequestSequence = 0;
  int _auditRequestSequence = 0;

  @override
  void dispose() {
    _loginIdController.dispose();
    _passwordController.dispose();
    _auditFilterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    if (appState.hasAdminAccess && !_initialLoadStarted) {
      _initialLoadStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadAll();
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '사용자 관리',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: !appState.hasAdminAccess || _mutationBusy
                ? null
                : _loadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: !appState.hasAdminAccess
            ? const _AdminAccessDenied()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  const Text(
                    '운영 콘솔 계정, 권한과 최근 보안 이벤트를 관리합니다.',
                    style: TextStyle(color: Color(0xFF64748B), height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  _buildSummary(),
                  if (_mutationMessage.isNotEmpty ||
                      _mutationError.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _Notice(
                      message: _mutationError.isNotEmpty
                          ? _mutationError
                          : _mutationMessage,
                      isError: _mutationError.isNotEmpty,
                    ),
                  ],
                  const SizedBox(height: 20),
                  _buildCreateUser(),
                  const SizedBox(height: 20),
                  _buildUsers(),
                  const SizedBox(height: 20),
                  _buildAuditLogs(),
                ],
              ),
      ),
    );
  }

  Widget _buildSummary() {
    final activeCount = _users.where((user) => user.isActive).length;
    final activeAdminCount = _users
        .where((user) => user.isActive && user.role == 'admin')
        .length;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SummaryChip(label: '전체 사용자', value: '${_users.length}'),
        _SummaryChip(label: '활성 사용자', value: '$activeCount'),
        _SummaryChip(label: '활성 관리자', value: '$activeAdminCount'),
        _SummaryChip(label: '최근 이벤트', value: '${_auditLogs.length}'),
      ],
    );
  }

  Widget _buildCreateUser() {
    return _SectionCard(
      title: '사용자 생성',
      subtitle: '초기 비밀번호는 최소 12자 이상이어야 합니다.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('admin-users-login-id'),
            controller: _loginIdController,
            textInputAction: TextInputAction.next,
            maxLength: 128,
            decoration: const InputDecoration(
              labelText: '로그인 아이디',
              border: OutlineInputBorder(),
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('admin-users-initial-password'),
            controller: _passwordController,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            maxLength: 1024,
            decoration: const InputDecoration(
              labelText: '초기 비밀번호',
              helperText: '최소 12자 · 입력한 비밀번호는 저장하거나 기록하지 않습니다.',
              border: OutlineInputBorder(),
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const ValueKey('admin-users-create-role'),
            value: _newRole,
            decoration: const InputDecoration(
              labelText: '역할',
              border: OutlineInputBorder(),
            ),
            items: _roles
                .map(
                  (role) => DropdownMenuItem<String>(
                    value: role,
                    child: Text(_roleLabel(role)),
                  ),
                )
                .toList(growable: false),
            onChanged: _mutationBusy
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _newRole = value);
                    }
                  },
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const ValueKey('admin-users-create'),
            onPressed: _mutationBusy ? null : _createUser,
            icon: _mutationBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add_alt_1),
            label: Text(_mutationBusy ? '처리 중...' : '사용자 생성'),
          ),
        ],
      ),
    );
  }

  Widget _buildUsers() {
    return _SectionCard(
      title: '사용자 목록',
      subtitle: '역할과 활성 상태를 변경할 수 있습니다. 계정 삭제는 지원하지 않습니다.',
      trailing: IconButton(
        tooltip: '사용자 다시 불러오기',
        onPressed: _usersLoading || _mutationBusy ? null : _loadUsers,
        icon: const Icon(Icons.refresh),
      ),
      child: _usersLoading && _users.isEmpty
          ? const _LoadingState(label: '사용자 목록을 불러오는 중...')
          : _usersError.isNotEmpty
              ? _RetryState(
                  message: _usersError,
                  onRetry: _loadUsers,
                )
              : _users.isEmpty
                  ? const _EmptyState(
                      icon: Icons.people_outline,
                      message: '등록된 사용자가 없습니다.',
                    )
                  : Column(
                      children: [
                        if (_usersLoading) ...[
                          const LinearProgressIndicator(),
                          const SizedBox(height: 8),
                        ],
                        for (var index = 0; index < _users.length; index++) ...[
                          if (index > 0) const SizedBox(height: 10),
                          _AdminUserCard(
                            key: ValueKey(_users[index].id),
                            user: _users[index],
                            busy: _mutationBusy,
                            onSave: _updateUser,
                          ),
                        ],
                      ],
                    ),
    );
  }

  Widget _buildAuditLogs() {
    final query = _auditFilterController.text.trim().toLowerCase();
    final filteredLogs = _auditLogs.where((log) {
      if (query.isEmpty) {
        return true;
      }
      return [
        log.eventType,
        log.loginId,
        log.target ?? '',
        log.detailJson ?? '',
      ].any((value) => value.toLowerCase().contains(query));
    }).toList(growable: false);

    return _SectionCard(
      title: '최근 감사 로그',
      subtitle: 'API가 제공하는 최근 $_auditLogLimit건에서 검색합니다.',
      trailing: IconButton(
        tooltip: '감사 로그 다시 불러오기',
        onPressed: _auditLogsLoading || _mutationBusy ? null : _loadAuditLogs,
        icon: const Icon(Icons.refresh),
      ),
      child: _auditLogsLoading && _auditLogs.isEmpty
          ? const _LoadingState(label: '감사 로그를 불러오는 중...')
          : _auditLogsError.isNotEmpty
              ? _RetryState(
                  message: _auditLogsError,
                  onRetry: _loadAuditLogs,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const ValueKey('admin-users-audit-filter'),
                      controller: _auditFilterController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: '이벤트, 사용자, 대상 검색',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '검색 지우기',
                                onPressed: () {
                                  _auditFilterController.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.clear),
                              ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_auditLogsLoading) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                    ],
                    if (filteredLogs.isEmpty)
                      _EmptyState(
                        icon: Icons.receipt_long_outlined,
                        message: _auditLogs.isEmpty
                            ? '감사 로그가 없습니다.'
                            : '검색 결과가 없습니다.',
                      )
                    else
                      for (final log in filteredLogs) ...[
                        _AuditLogTile(log: log),
                        const Divider(height: 1),
                      ],
                  ],
                ),
    );
  }

  Future<void> _loadAll() async {
    if (!mounted || !context.read<AppState>().hasAdminAccess) {
      return;
    }
    await Future.wait<void>([_loadUsers(), _loadAuditLogs()]);
  }

  Future<void> _loadUsers() async {
    if (!mounted || !context.read<AppState>().hasAdminAccess) {
      return;
    }
    final request = ++_usersRequestSequence;
    setState(() {
      _usersLoading = true;
      _usersError = '';
    });
    try {
      final result = await context.read<AppState>().fetchMapParsed<
          List<_AdminUser>>(
        '/api/auth/users',
        parser: _parseUsers,
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      if (!mounted || request != _usersRequestSequence) {
        return;
      }
      setState(() {
        _users = result.data;
        _usersLoading = false;
      });
    } catch (error) {
      if (!mounted || request != _usersRequestSequence) {
        return;
      }
      setState(() {
        _usersError = _displayError(error, fallback: '사용자 목록을 불러오지 못했습니다.');
        _usersLoading = false;
      });
    }
  }

  Future<void> _loadAuditLogs() async {
    if (!mounted || !context.read<AppState>().hasAdminAccess) {
      return;
    }
    final request = ++_auditRequestSequence;
    setState(() {
      _auditLogsLoading = true;
      _auditLogsError = '';
    });
    try {
      final result = await context.read<AppState>().fetchMapParsed<
          List<_AdminAuditLog>>(
        '/api/auth/audit-logs',
        params: const <String, Object?>{'limit': _auditLogLimit},
        parser: _parseAuditLogs,
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      if (!mounted || request != _auditRequestSequence) {
        return;
      }
      setState(() {
        _auditLogs = result.data;
        _auditLogsLoading = false;
      });
    } catch (error) {
      if (!mounted || request != _auditRequestSequence) {
        return;
      }
      setState(() {
        _auditLogsError =
            _displayError(error, fallback: '감사 로그를 불러오지 못했습니다.');
        _auditLogsLoading = false;
      });
    }
  }

  Future<void> _createUser() async {
    final loginId = _loginIdController.text.trim();
    final password = _passwordController.text;
    final validationError = _validateLoginId(loginId) ??
        _validatePassword(password, loginId: loginId);
    if (validationError != null) {
      setState(() {
        _mutationError = validationError;
        _mutationMessage = '';
      });
      return;
    }

    setState(() {
      _mutationBusy = true;
      _mutationError = '';
      _mutationMessage = '';
    });
    try {
      final confirmed = await _confirmMutation(
        title: '사용자 생성 확인',
        message: [
          '$loginId 계정을 ${_roleLabel(_newRole)} 역할로 생성합니다.',
          '입력한 초기 비밀번호는 화면에 다시 표시되지 않습니다.',
        ].join(' '),
        confirmLabel: '확인하고 생성',
        confirmKey: const ValueKey('admin-user-create-confirm'),
      );
      if (!mounted || !confirmed) {
        return;
      }

      await context.read<AppState>().postJson(
        '/api/auth/users',
        body: <String, dynamic>{
          'login_id': loginId,
          'password': password,
          'role': _newRole,
        },
      );
      if (!mounted) {
        return;
      }
      _loginIdController.clear();
      _passwordController.clear();
      setState(() {
        _newRole = 'viewer';
        _mutationMessage = '사용자를 생성했습니다.';
      });
      await Future.wait<void>([_loadUsers(), _loadAuditLogs()]);
    } catch (error) {
      if (mounted) {
        setState(() {
          _mutationError = _displayError(error, fallback: '사용자를 생성하지 못했습니다.');
        });
      }
    } finally {
      if (mounted) {
        _passwordController.clear();
        setState(() => _mutationBusy = false);
      }
    }
  }

  Future<bool> _updateUser(
    _AdminUser user,
    String role,
    bool isActive,
    String? newPassword,
  ) async {
    if (_mutationBusy) {
      return false;
    }
    if (newPassword != null) {
      final validationError =
          _validatePassword(newPassword, loginId: user.loginId);
      if (validationError != null) {
        setState(() {
          _mutationError = validationError;
          _mutationMessage = '';
        });
        return false;
      }
    }

    setState(() {
      _mutationBusy = true;
      _mutationError = '';
      _mutationMessage = '';
    });
    try {
      final changes = <String>[
        '역할 ${_roleLabel(user.role)} → ${_roleLabel(role)}',
        '상태 ${user.isActive ? '활성' : '비활성'} → ${isActive ? '활성' : '비활성'}',
        if (newPassword != null) '비밀번호 재설정',
      ];
      final confirmed = await _confirmMutation(
        title: '계정 변경 확인',
        message: '${user.loginId} 계정의 ${changes.join(', ')}을(를) 적용합니다.',
        confirmLabel: '확인하고 저장',
        confirmKey: const ValueKey('admin-user-update-confirm'),
      );
      if (!mounted || !confirmed) {
        return false;
      }

      final body = <String, dynamic>{
        'role': role,
        'is_active': isActive,
        if (newPassword != null) 'new_password': newPassword,
      };
      await context.read<AppState>().postJson(
        '/api/auth/users/${user.id}',
        body: body,
        method: 'PATCH',
      );
      if (!mounted) {
        return false;
      }
      setState(() => _mutationMessage = '${user.loginId} 계정을 업데이트했습니다.');
      await Future.wait<void>([_loadUsers(), _loadAuditLogs()]);
      return true;
    } catch (error) {
      if (mounted) {
        setState(() {
          _mutationError = _displayError(error, fallback: '계정을 업데이트하지 못했습니다.');
        });
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _mutationBusy = false);
      }
    }
  }

  Future<bool> _confirmMutation({
    required String title,
    required String message,
    required String confirmLabel,
    required Key confirmKey,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('취소'),
              ),
              FilledButton(
                key: confirmKey,
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  static String? _validateLoginId(String value) {
    if (value.isEmpty) {
      return '아이디는 필수입니다.';
    }
    if (value.runes.length > 128 ||
        value.runes.any((rune) => rune < 32 || rune == 127)) {
      return '아이디 형식이 올바르지 않습니다.';
    }
    return null;
  }

  static String? _validatePassword(String value, {required String loginId}) {
    if (value.isEmpty) {
      return '비밀번호는 필수입니다.';
    }
    final passwordLength = value.runes.length;
    if (passwordLength > 1024) {
      return '비밀번호는 1024자 이하여야 합니다.';
    }
    if (passwordLength < 12) {
      return '비밀번호는 최소 12자 이상이어야 합니다.';
    }
    if (loginId.isNotEmpty &&
        value.toLowerCase().contains(loginId.toLowerCase())) {
      return '비밀번호에 로그인 아이디를 포함할 수 없습니다.';
    }
    if (const {
      'password',
      '123456789012',
      'cafe-bridge1234!',
      'qwer1234!@#$',
    }.contains(value.toLowerCase())) {
      return '너무 약한 비밀번호는 사용할 수 없습니다.';
    }
    return null;
  }

  static String _displayError(Object error, {required String fallback}) {
    if (error is! ApiException) {
      final message = error.toString().trim();
      return message.isEmpty ? fallback : message;
    }
    final message = error.message.trim().isEmpty ? fallback : error.message;
    switch (error.statusCode) {
      case 400:
        final details = error.fieldErrors.entries
            .map((entry) => '${entry.key}: ${entry.value}')
            .join(' · ');
        return details.isEmpty
            ? '입력값을 확인해 주세요. $message'
            : '입력값을 확인해 주세요. $details';
      case 401:
        return '로그인이 만료되었습니다. 다시 로그인해 주세요. $message';
      case 403:
        return '권한이 없거나 요청을 확인할 수 없습니다. $message';
      case 404:
        return '대상 계정을 찾을 수 없습니다. $message';
      case 409:
        return '계정 충돌: $message';
      default:
        if (error.statusCode != null && error.statusCode! >= 500) {
          return '서버 오류 (${error.statusCode}). 잠시 후 다시 시도해 주세요. $message';
        }
        return message;
    }
  }
}

class _AdminUserCard extends StatefulWidget {
  const _AdminUserCard({
    super.key,
    required this.user,
    required this.busy,
    required this.onSave,
  });

  final _AdminUser user;
  final bool busy;
  final Future<bool> Function(
    _AdminUser user,
    String role,
    bool isActive,
    String? newPassword,
  ) onSave;

  @override
  State<_AdminUserCard> createState() => _AdminUserCardState();
}

class _AdminUserCardState extends State<_AdminUserCard> {
  late String _role;
  late bool _isActive;
  final _newPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _role = widget.user.role;
    _isActive = widget.user.isActive;
  }

  @override
  void didUpdateWidget(covariant _AdminUserCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.role != widget.user.role ||
        oldWidget.user.isActive != widget.user.isActive ||
        oldWidget.user.updatedAt != widget.user.updatedAt) {
      _role = widget.user.role;
      _isActive = widget.user.isActive;
      _newPasswordController.clear();
    }
  }

  @override
  void dispose() {
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final password = _newPasswordController.text;
    final saved = await widget.onSave(
      widget.user,
      _role,
      _isActive,
      password.isEmpty ? null : password,
    );
    if (mounted) {
      _newPasswordController.clear();
      if (!saved) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final activeLabel = _isActive ? '활성' : '비활성';
    final hasChanges = _role != user.role ||
        _isActive != user.isActive ||
        _newPasswordController.text.isNotEmpty;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  child: Text(
                    user.loginId.isEmpty ? '?' : user.loginId[0].toUpperCase(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.loginId,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '#${user.id} · $activeLabel · 실패 ${user.failedAttempts}회',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _isActive
                      ? Icons.check_circle_outline
                      : Icons.pause_circle_outline,
                  color: _isActive
                      ? const Color(0xFF15803D)
                      : const Color(0xFF64748B),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '마지막 로그인: ${_shortDate(user.lastLoginAt) ?? '없음'}',
              style: const TextStyle(color: Color(0xFF475569), fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              '생성: ${_shortDate(user.createdAt) ?? '-'}',
              style: const TextStyle(color: Color(0xFF475569), fontSize: 12),
            ),
            if (user.lockedUntil != null) ...[
              const SizedBox(height: 4),
              Text(
                '잠금 상태: ${_shortDate(user.lockedUntil)}',
                style: const TextStyle(
                  color: Color(0xFFB45309),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
          key: ValueKey('admin-user-role-${user.id}'),
              value: _role,
              decoration: const InputDecoration(
                labelText: '역할',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _roles
                  .map(
                    (role) => DropdownMenuItem<String>(
                      value: role,
                      child: Text(_roleLabel(role)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: widget.busy
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _role = value);
                      }
                    },
            ),
            SwitchListTile.adaptive(
              key: ValueKey('admin-user-active-${user.id}'),
              contentPadding: EdgeInsets.zero,
              title: const Text('계정 활성화'),
              subtitle: Text(_isActive ? '로그인 가능' : '로그인 차단'),
              value: _isActive,
              onChanged: widget.busy
                  ? null
                  : (value) => setState(() => _isActive = value),
            ),
            TextField(
              key: ValueKey('admin-user-password-${user.id}'),
              controller: _newPasswordController,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              maxLength: 1024,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '새 비밀번호 (선택)',
                helperText: '입력 시 비밀번호를 재설정합니다. 최소 12자.',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: ValueKey('admin-user-save-${user.id}'),
              onPressed: widget.busy || !hasChanges ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(widget.busy ? '처리 중...' : '변경 저장'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminAuditLog {
  const _AdminAuditLog({
    required this.loginId,
    required this.eventType,
    this.target,
    this.createdAt,
    this.detailJson,
  });

  final String loginId;
  final String eventType;
  final String? target;
  final String? createdAt;
  final String? detailJson;

  factory _AdminAuditLog.fromJson(Map<String, dynamic> json) {
    return _AdminAuditLog(
      loginId: json['login_id']?.toString() ?? '',
      eventType: json['event_type']?.toString() ?? '',
      target: json['target']?.toString(),
      createdAt: json['created_at']?.toString(),
      detailJson: json['detail_json']?.toString(),
    );
  }
}

class _AdminUser {
  const _AdminUser({
    required this.id,
    required this.loginId,
    required this.role,
    required this.isActive,
    required this.failedAttempts,
    required this.createdAt,
    required this.updatedAt,
    this.lockedUntil,
    this.lastLoginAt,
  });

  final int id;
  final String loginId;
  final String role;
  final bool isActive;
  final int failedAttempts;
  final String? lockedUntil;
  final String? lastLoginAt;
  final String createdAt;
  final String updatedAt;

  factory _AdminUser.fromJson(Map<String, dynamic> json) {
    final role = json['role']?.toString() ?? '';
    if (!_roles.contains(role)) {
      throw const FormatException('사용자 역할 형식이 올바르지 않습니다.');
    }
    return _AdminUser(
      id: _asInt(json['id']),
      loginId: json['login_id']?.toString() ?? '',
      role: role,
      isActive: json['is_active'] == true || _asInt(json['is_active']) != 0,
      failedAttempts: _asInt(json['failed_attempts']),
      lockedUntil: json['locked_until']?.toString(),
      lastLoginAt: json['last_login_at']?.toString(),
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }
}

List<_AdminUser> _parseUsers(Map<String, dynamic> json) {
  final rawUsers = json['users'];
  if (rawUsers is! List) {
    throw const FormatException('사용자 응답에 users 목록이 없습니다.');
  }
  return rawUsers.map((raw) {
    if (raw is! Map) {
      throw const FormatException('사용자 정보 형식이 올바르지 않습니다.');
    }
    return _AdminUser.fromJson(Map<String, dynamic>.from(raw));
  }).toList(growable: false);
}

List<_AdminAuditLog> _parseAuditLogs(Map<String, dynamic> json) {
  final rawLogs = json['logs'];
  if (rawLogs is! List) {
    throw const FormatException('감사 로그 응답에 logs 목록이 없습니다.');
  }
  return rawLogs.map((raw) {
    if (raw is! Map) {
      throw const FormatException('감사 로그 형식이 올바르지 않습니다.');
    }
    return _AdminAuditLog.fromJson(Map<String, dynamic>.from(raw));
  }).toList(growable: false);
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _roleLabel(String role) {
  switch (role) {
    case 'viewer':
      return '읽기 전용';
    case 'operator':
      return '운영자';
    case 'admin':
      return '관리자';
    default:
      return role;
  }
}

String? _shortDate(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  return value.length > 19 ? value.substring(0, 19) : value;
}

class _AdminAccessDenied extends StatelessWidget {
  const _AdminAccessDenied();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.lock_outline, size: 38, color: Color(0xFF64748B)),
            SizedBox(height: 12),
            Text(
              '권한 없음: 관리자 권한이 필요합니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF475569), fontSize: 12),
          ),
          const SizedBox(width: 8),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? const Color(0xFFB91C1C) : const Color(0xFF166534);
    final background =
        isError ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4);
    final border = isError ? const Color(0xFFFECACA) : const Color(0xFFBBF7D0);
    return Container(
      key: const ValueKey('admin-users-message'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, style: TextStyle(color: color, height: 1.4)),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(color: Color(0xFF64748B))),
        ],
      ),
    );
  }
}

class _RetryState extends StatelessWidget {
  const _RetryState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.cloud_off_outlined, color: Color(0xFFB91C1C)),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('다시 불러오기'),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(icon, size: 30, color: const Color(0xFF94A3B8)),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(color: Color(0xFF64748B))),
        ],
      ),
    );
  }
}

class _AuditLogTile extends StatelessWidget {
  const _AuditLogTile({required this.log});

  final _AdminAuditLog log;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (log.loginId.isNotEmpty) log.loginId,
      if (log.target?.isNotEmpty == true) log.target!,
      if (log.detailJson?.isNotEmpty == true) log.detailJson!,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.receipt_long_outlined,
              size: 18,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.eventType.isEmpty ? '이벤트' : log.eventType,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    details.join(' · '),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (log.createdAt != null) ...[
            const SizedBox(width: 8),
            Text(
              _shortDate(log.createdAt) ?? '',
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
