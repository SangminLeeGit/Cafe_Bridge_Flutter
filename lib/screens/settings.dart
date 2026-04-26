import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/api_contracts.dart';
import '../models/dashboard_model.dart';
import '../services/api.dart';
import '../state/app_state.dart';
import '../widgets/app_update_banner.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _controller;
  bool _isChecking = false;
  bool _statusOk = false;
  String _statusMessage = '';
  String _lastSyncedApiBaseUrl = '';
  bool _isClearingCache = false;
  bool _isLoggingOut = false;
  late final TextEditingController _currentPasswordController;
  late final TextEditingController _newPasswordController;
  late final TextEditingController _confirmPasswordController;
  bool _isChangingPassword = false;
  String _passwordMessage = '';
  bool _passwordOk = false;

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return '-';
    }
    String two(int v) => v.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _currentPasswordController = TextEditingController();
    _newPasswordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _checkConnection() async {
    final baseUrl = ApiService.normalizeBaseUrl(_controller.text);
    setState(() {
      _isChecking = true;
      _statusMessage = '';
    });

    try {
      final response = await ApiService.fetchJson(baseUrl, '/healthz');
      if (!mounted) {
        return;
      }
      setState(() {
        _statusOk = response.data['ok'] == true;
        _statusMessage = _statusOk ? '백엔드 연결 성공' : '헬스체크 응답이 비정상입니다.';
        _isChecking = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusOk = false;
        _statusMessage = error.toString();
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    if (_lastSyncedApiBaseUrl != appState.apiBaseUrl) {
      _lastSyncedApiBaseUrl = appState.apiBaseUrl;
      _controller.text = appState.apiBaseUrl;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '앱 설정',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
        ),
        const SizedBox(height: 6),
        const Text(
          '기본 서버 주소는 pos.cafe-bridge.org 입니다.',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 24),
        const Text(
          '백엔드 서버 주소',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'https://pos.cafe-bridge.org',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: () async {
                  final appState = context.read<AppState>();
                  final messenger = ScaffoldMessenger.of(context);

                  await appState.updateApiBaseUrl(_controller.text);
                  if (!context.mounted) {
                    return;
                  }
                  messenger.showSnackBar(
                    const SnackBar(content: Text('서버 주소를 저장하고 적용했습니다.')),
                  );
                },
                child: const Text('적용'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final appState = context.read<AppState>();
                  final messenger = ScaffoldMessenger.of(context);

                  await appState.resetApiBaseUrl();
                  if (!context.mounted) {
                    return;
                  }
                  setState(() {
                    _statusMessage = '';
                  });
                  messenger.showSnackBar(
                    const SnackBar(
                        content: Text('기본 서버 주소로 되돌리고 저장값을 삭제했습니다.')),
                  );
                },
                child: const Text('기본값'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _isChecking ? null : _checkConnection,
          icon: const Icon(Icons.health_and_safety_outlined),
          label: Text(_isChecking ? '확인 중...' : '연결 테스트'),
        ),
        if (_statusMessage.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            _statusMessage,
            style: TextStyle(
              color:
                  _statusOk ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 32),
        const Text(
          '앱 업데이트',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 8),
        _buildInfoRow('현재 버전', appState.currentAppVersionLabel),
        _buildInfoRow(
          '배포 버전',
          appState.updateInfo == null
              ? '-'
              : appState.updateInfo!.displayLabel,
        ),
        _buildInfoRow(
          '최근 배포 시각',
          _formatDateTime(appState.deployNotice?.publishedAt),
        ),
        _buildInfoRow(
          '배포 실행자',
          appState.deployNotice?.requestedBy.trim().isNotEmpty == true
              ? appState.deployNotice!.requestedBy
              : '-',
        ),
        _buildInfoRow('최근 확인 시각', _formatDateTime(appState.lastUpdateCheckAt)),
        _buildInfoRow(
          '최근 확인 상태',
          appState.lastUpdateCheckOk == null
              ? '미확인'
              : (appState.lastUpdateCheckOk! ? '성공' : '실패'),
        ),
        if (appState.lastUpdateCheckMessage.isNotEmpty)
          _buildInfoRow('확인 결과', appState.lastUpdateCheckMessage),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: appState.isUpdateActionInProgress
              ? null
              : () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await context
                        .read<AppState>()
                        .checkForAppUpdate(ignoreErrors: false);
                  } catch (_) {
                    // AppState already stores the error message for UI display.
                  }
                  if (!context.mounted) {
                    return;
                  }
                  final refreshed = context.read<AppState>();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(refreshed.lastUpdateCheckMessage.isNotEmpty
                          ? refreshed.lastUpdateCheckMessage
                          : (refreshed.hasRecommendedUpdate
                              ? '새 권장 업데이트를 확인했습니다.'
                              : '현재 최신 버전입니다.')),
                    ),
                  );
                },
          icon: const Icon(Icons.system_update_alt_outlined),
          label: const Text('업데이트 확인'),
        ),
        if (appState.hasUnreadDeployNotice) ...[
          const SizedBox(height: 12),
          _DeployNoticeCard(
            notice: appState.deployNotice!,
            onConfirm: () async {
              await context.read<AppState>().markDeployNoticeSeen();
            },
          ),
        ],
        if (appState.hasRecommendedUpdate) ...[
          const SizedBox(height: 12),
          const AppUpdateBanner(),
        ],
        const SizedBox(height: 32),
        const Text(
          '인증 상태',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 8),
        _buildInfoRow(
          '로그인 상태',
          appState.isAuthenticated
              ? (appState.offlineMode ? '오프라인 세션 유지' : '로그인됨')
              : '로그아웃됨',
        ),
        _buildInfoRow('계정', appState.loginId ?? '-'),
        _buildInfoRow('권한', appState.role ?? '-'),
        _buildInfoRow(
          '접근 범위',
          appState.hasAdminAccess
              ? 'admin · operator · viewer'
              : appState.hasOperatorAccess
                  ? 'operator · viewer'
                  : 'viewer',
        ),
        if (appState.hasAdminAccess) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.admin_panel_settings_outlined, color: Color(0xFF0F172A)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '관리자 전용 배포 상태, 버전 정보, 업데이트 지표가 아래에 표시됩니다.',
                    style: TextStyle(
                      color: Color(0xFF334155),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '관리자 권한이 있어야 배포 상태, 이력, 버전 정보, 업데이트 지표를 확인할 수 있습니다.',
              style: TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        _buildInfoRow('캐시 항목', '${appState.cacheEntryCount}개'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isClearingCache
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        setState(() {
                          _isClearingCache = true;
                        });
                        final removed = await appState.clearCache();
                        if (!mounted) {
                          return;
                        }
                        setState(() {
                          _isClearingCache = false;
                        });
                        messenger.showSnackBar(
                          SnackBar(content: Text('캐시 $removed건을 삭제했습니다.')),
                        );
                      },
                icon: const Icon(Icons.cleaning_services_outlined),
                label: Text(_isClearingCache ? '삭제 중...' : '캐시 비우기'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _isLoggingOut || !appState.isAuthenticated
                    ? null
                    : () async {
                        setState(() {
                          _isLoggingOut = true;
                        });
                        await appState.logout();
                        if (!mounted) {
                          return;
                        }
                        setState(() {
                          _isLoggingOut = false;
                        });
                      },
                icon: const Icon(Icons.logout),
                label: Text(_isLoggingOut ? '정리 중...' : '로그아웃'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        const Text(
          '비밀번호 변경',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _currentPasswordController,
          decoration: const InputDecoration(
            labelText: '현재 비밀번호',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _newPasswordController,
          decoration: const InputDecoration(
            labelText: '새 비밀번호',
            helperText: '최소 12자 이상',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPasswordController,
          decoration: const InputDecoration(
            labelText: '새 비밀번호 확인',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _isChangingPassword || !appState.isAuthenticated
              ? null
              : () async {
                  final messenger = ScaffoldMessenger.of(context);
                  if (_newPasswordController.text !=
                      _confirmPasswordController.text) {
                    setState(() {
                      _passwordOk = false;
                      _passwordMessage = '새 비밀번호가 일치하지 않습니다.';
                    });
                    return;
                  }

                  setState(() {
                    _isChangingPassword = true;
                    _passwordMessage = '';
                  });

                  try {
                    await appState.changePassword(
                      currentPassword: _currentPasswordController.text,
                      newPassword: _newPasswordController.text,
                    );
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      _passwordOk = true;
                      _passwordMessage = '비밀번호가 변경되었습니다. 다시 로그인해 주세요.';
                      _currentPasswordController.clear();
                      _newPasswordController.clear();
                      _confirmPasswordController.clear();
                    });
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('비밀번호가 변경되어 세션이 종료되었습니다.'),
                      ),
                    );
                  } catch (error) {
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      _passwordOk = false;
                      _passwordMessage = error.toString();
                    });
                  } finally {
                    if (mounted) {
                      setState(() {
                        _isChangingPassword = false;
                      });
                    }
                  }
                },
          icon: const Icon(Icons.key_outlined),
          label: Text(_isChangingPassword ? '변경 중...' : '비밀번호 변경'),
        ),
        if (_passwordMessage.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            _passwordMessage,
            style: TextStyle(
              color:
                  _passwordOk ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 32),
        const Text(
          '실행 정보',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 8),
        _buildInfoRow('앱 버전', appState.currentAppVersionLabel),
        _buildInfoRow('현재 서버', appState.apiBaseUrl),
        _buildInfoRow(
          '세션 확인',
          UiFormat.compactDateTime(
            appState.lastSessionSyncAt?.toIso8601String(),
          ),
        ),
        _buildInfoRow(
          '오늘 날짜',
          UiFormat.weekday(ApiService.formatDate(DateTime.now())),
        ),
        if (appState.hasAdminAccess) ...[
          const SizedBox(height: 32),
          const _AdminDeployPanel(),
        ],
        if (appState.hasAdminAccess) ...[
          const SizedBox(height: 32),
          const Text(
            '관리자',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _UserManagementScreen()),
            ),
            icon: const Icon(Icons.manage_accounts_outlined),
            label: const Text('계정 관리'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _AuditLogScreen()),
            ),
            icon: const Icon(Icons.history_outlined),
            label: const Text('감사 로그'),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, color: Color(0xFF475569)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeployNoticeCard extends StatelessWidget {
  final DeployNoticeInfo notice;
  final Future<void> Function() onConfirm;

  const _DeployNoticeCard({
    required this.notice,
    required this.onConfirm,
  });

  String _publishedLabel() {
    final value = notice.publishedAt;
    if (value == null) {
      return '방금 반영된 최신 배포';
    }
    String two(int v) => v.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)} 배포';
  }

  @override
  Widget build(BuildContext context) {
    final summary = notice.reason.trim().isNotEmpty
        ? notice.reason.trim()
        : (notice.releaseNotes.trim().isNotEmpty
            ? notice.releaseNotes.trim()
            : '새 Flutter 앱 빌드가 배포되었습니다.');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.campaign_outlined, color: Color(0xFF1D4ED8)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '새 배포 알림 · ${notice.versionLabel}',
                      style: const TextStyle(
                        color: Color(0xFF1E3A8A),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _publishedLabel(),
                      style: const TextStyle(
                        color: Color(0xFF1D4ED8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            summary,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          if (notice.requestedBy.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '실행자: ${notice.requestedBy}',
              style: const TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  notice.downloadReady
                      ? '다운로드 가능한 배포가 준비되었습니다.'
                      : '배포는 반영되었지만 다운로드 주소는 아직 비어 있습니다.',
                  style: TextStyle(
                    color: notice.downloadReady
                        ? const Color(0xFF0F766E)
                        : const Color(0xFF9A3412),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed: () async {
                  await onConfirm();
                },
                child: const Text('확인'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Admin: User Management ───────────────────────────────────────────────────

class _UserManagementScreen extends StatefulWidget {
  const _UserManagementScreen();

  @override
  State<_UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<_UserManagementScreen> {
  List<AdminUserContract> _users = [];
  bool _loading = true;
  String _error = '';

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
      final result = await appState.fetchListParsed<List<AdminUserContract>>(
        '/api/auth/users',
        parser: (json) => json
            .map((e) => AdminUserContract.fromJson(e as Map<String, dynamic>))
            .toList(),
        cacheTtl: Duration.zero,
      );
      if (!mounted) return;
      setState(() {
        _users = result.data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _editRole(AdminUserContract user) async {
    final appState = context.read<AppState>();
    final roles = ['viewer', 'operator', 'admin'];
    String selected = user.role;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('${user.loginId} 권한 변경'),
          content: RadioGroup<String>(
            groupValue: selected,
            onChanged: (v) {
              if (v != null) setDialogState(() => selected = v);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: roles
                  .map(
                    (r) => RadioListTile<String>(
                      value: r,
                      title: Text(r),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('적용'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      await appState.postJson(
        '/api/auth/users/${user.id}',
        body: {'role': selected},
        method: 'PATCH',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user.loginId} 권한이 $selected로 변경되었습니다.')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('계정 관리', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error,
                        style: const TextStyle(color: Color(0xFFDC2626))),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _users.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final u = _users[i];
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              u.loginId.isNotEmpty
                                  ? u.loginId[0].toUpperCase()
                                  : '?',
                            ),
                          ),
                          title: Text(u.loginId,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '${u.role}  ·  ${u.isActive ? '활성' : '비활성'}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _editRole(u),
                            tooltip: '권한 변경',
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ─── Admin: Audit Log ─────────────────────────────────────────────────────────

class _AuditLogScreen extends StatefulWidget {
  const _AuditLogScreen();

  @override
  State<_AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<_AuditLogScreen> {
  List<AuditLogEntryContract> _entries = [];
  bool _loading = true;
  String _error = '';

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
      final result = await appState.fetchListParsed<List<AuditLogEntryContract>>(
        '/api/auth/audit-logs',
        parser: (json) => json
            .map((e) => AuditLogEntryContract.fromJson(e as Map<String, dynamic>))
            .toList(),
        cacheTtl: Duration.zero,
      );
      if (!mounted) return;
      setState(() {
        _entries = result.data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('감사 로그', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error,
                        style: const TextStyle(color: Color(0xFFDC2626))),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final e = _entries[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.receipt_long_outlined,
                            size: 18, color: Color(0xFF64748B)),
                        title: Text(
                          e.action,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${e.loginId}${e.detail != null ? '  ·  ${e.detail}' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: e.createdAt != null
                            ? Text(
                                UiFormat.compactDateTime(e.createdAt),
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xFF94A3B8)),
                              )
                            : null,
                      );
                    },
                  ),
                ),
    );
  }
}

class _DeployTask {
  final String taskId;
  final String target;
  final String requestedBy;
  final String reason;
  final bool dryRun;
  final String status;
  final String currentStep;
  final String logPath;
  final String resolvedCommit;
  final bool? healthCheckOk;
  final String errorMessage;
  final String? startedAt;
  final String? finishedAt;

  const _DeployTask({
    required this.taskId,
    required this.target,
    required this.requestedBy,
    required this.reason,
    required this.dryRun,
    required this.status,
    required this.currentStep,
    required this.logPath,
    required this.resolvedCommit,
    required this.errorMessage,
    this.healthCheckOk,
    this.startedAt,
    this.finishedAt,
  });

  factory _DeployTask.fromJson(Map<String, dynamic> json) {
    return _DeployTask(
      taskId: json['task_id']?.toString() ?? '',
      target: json['target']?.toString() ?? '',
      requestedBy: json['requested_by']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
      dryRun: json['dry_run'] == true,
      status: json['status']?.toString() ?? '',
      currentStep: json['current_step']?.toString() ?? '',
      logPath: json['log_path']?.toString() ?? '',
      resolvedCommit: json['resolved_commit']?.toString() ?? '',
      healthCheckOk: json['health_check_ok'] as bool?,
      errorMessage: json['error_message']?.toString() ?? '',
      startedAt: json['started_at']?.toString(),
      finishedAt: json['finished_at']?.toString(),
    );
  }

  bool get isActive => status == 'pending' || status == 'running';
}

class _VersionInfo {
  final String pubspecVersionRaw;
  final String pubspecVersion;
  final int pubspecBuild;
  final String pubspecPath;
  final String latestVersion;
  final int latestBuild;
  final String downloadUrl;
  final String sha256;
  final String releaseNotes;
  final String publishedAt;
  final int fileSize;
  final String? policySource;
  final String? policyWarning;
  final bool? downloadReady;
  final String releaseDir;
  final String latestJsonPath;
  final bool latestReleaseExists;
  final String? latestReleaseReadError;
  final String? latestReleaseVersion;
  final int? latestReleaseBuild;
  final String? latestReleaseFileName;
  final String? latestReleasePublishedAt;
  final String? latestReleaseArtifactPath;
  final String? latestReleaseDownloadUrl;
  final String? latestReleaseSha256;
  final int? latestReleaseFileSize;

  const _VersionInfo({
    required this.pubspecVersionRaw,
    required this.pubspecVersion,
    required this.pubspecBuild,
    required this.pubspecPath,
    required this.latestVersion,
    required this.latestBuild,
    required this.downloadUrl,
    required this.sha256,
    required this.releaseNotes,
    required this.publishedAt,
    required this.fileSize,
    required this.releaseDir,
    required this.latestJsonPath,
    required this.latestReleaseExists,
    this.policySource,
    this.policyWarning,
    this.downloadReady,
    this.latestReleaseReadError,
    this.latestReleaseVersion,
    this.latestReleaseBuild,
    this.latestReleaseFileName,
    this.latestReleasePublishedAt,
    this.latestReleaseArtifactPath,
    this.latestReleaseDownloadUrl,
    this.latestReleaseSha256,
    this.latestReleaseFileSize,
  });

  factory _VersionInfo.fromJson(Map<String, dynamic> json) {
    final pubspec = (json['pubspec'] as Map?)?.cast<String, dynamic>() ?? const {};
    final updatePolicy = (json['update_policy'] as Map?)?.cast<String, dynamic>() ?? const {};
    final latestRelease = (json['latest_release'] as Map?)?.cast<String, dynamic>() ?? const {};
    final latest = (latestRelease['latest'] as Map?)?.cast<String, dynamic>() ?? const {};

    return _VersionInfo(
      pubspecVersionRaw: pubspec['version_raw']?.toString() ?? '',
      pubspecVersion: pubspec['version']?.toString() ?? '',
      pubspecBuild: int.tryParse(pubspec['build']?.toString() ?? '') ?? 0,
      pubspecPath: pubspec['pubspec_path']?.toString() ?? '',
      latestVersion: updatePolicy['latest_version']?.toString() ?? '',
      latestBuild: int.tryParse(updatePolicy['latest_build']?.toString() ?? '') ?? 0,
      downloadUrl: updatePolicy['download_url']?.toString() ?? '',
      sha256: updatePolicy['sha256']?.toString() ?? '',
      releaseNotes: updatePolicy['release_notes']?.toString() ?? '',
      publishedAt: updatePolicy['published_at']?.toString() ?? '',
      fileSize: int.tryParse(updatePolicy['file_size']?.toString() ?? '') ?? 0,
      policySource: updatePolicy['policy_source']?.toString(),
      policyWarning: updatePolicy['policy_warning']?.toString(),
      downloadReady: updatePolicy['download_ready'] as bool?,
      releaseDir: latestRelease['release_dir']?.toString() ?? '',
      latestJsonPath: latestRelease['latest_json_path']?.toString() ?? '',
      latestReleaseExists: latestRelease['exists'] == true,
      latestReleaseReadError: latestRelease['read_error']?.toString(),
      latestReleaseVersion: latest['latest_version']?.toString(),
      latestReleaseBuild: int.tryParse(latest['latest_build']?.toString() ?? ''),
      latestReleaseFileName: latest['file_name']?.toString(),
      latestReleasePublishedAt: latest['published_at']?.toString(),
      latestReleaseArtifactPath: latest['artifact_path']?.toString(),
      latestReleaseDownloadUrl: latest['download_url']?.toString(),
      latestReleaseSha256: latest['sha256']?.toString(),
      latestReleaseFileSize: int.tryParse(latest['file_size']?.toString() ?? ''),
    );
  }

    String get policyLabel => formatVersionDisplay(latestVersion, latestBuild);
    String get pubspecLabel => formatVersionDisplay(pubspecVersion, pubspecBuild);
    String get releaseLabel => latestReleaseExists
      ? formatVersionDisplay(latestReleaseVersion ?? '', latestReleaseBuild)
      : '-';
}

class _AppUpdateMetrics {
  final int appUpdateCheckTotal;
  final int appUpdateCheckFailedTotal;
  final int downloadUrlEmptyTotal;
  final Map<String, int> policySourceTotal;

  const _AppUpdateMetrics({
    required this.appUpdateCheckTotal,
    required this.appUpdateCheckFailedTotal,
    required this.downloadUrlEmptyTotal,
    required this.policySourceTotal,
  });

  factory _AppUpdateMetrics.fromJson(Map<String, dynamic> json) {
    final rawPolicySourceTotal = (json['policy_source_total'] as Map?)?.cast<String, dynamic>() ?? const {};
    return _AppUpdateMetrics(
      appUpdateCheckTotal: int.tryParse(json['app_update_check_total']?.toString() ?? '') ?? 0,
      appUpdateCheckFailedTotal: int.tryParse(json['app_update_check_failed_total']?.toString() ?? '') ?? 0,
      downloadUrlEmptyTotal: int.tryParse(json['download_url_empty_total']?.toString() ?? '') ?? 0,
      policySourceTotal: rawPolicySourceTotal.map((key, value) => MapEntry(key, int.tryParse(value.toString()) ?? 0)),
    );
  }

  String get topPolicySource {
    if (policySourceTotal.isEmpty) {
      return '-';
    }
    final entries = policySourceTotal.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries.first.key;
  }
}

class _AdminDeployPanel extends StatefulWidget {
  const _AdminDeployPanel();

  @override
  State<_AdminDeployPanel> createState() => _AdminDeployPanelState();
}

class _AdminDeployPanelState extends State<_AdminDeployPanel> {
  List<_DeployTask> _history = [];
  _DeployTask? _currentTask;
  _VersionInfo? _versionInfo;
  _AppUpdateMetrics? _metrics;
  bool _loading = true;
  bool _refreshing = false;
  String _error = '';
  String _scopeKey = '';
  Timer? _pollTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = context.watch<AppState>();
    final nextScopeKey = '${appState.apiBaseUrl}|${appState.loginId}|${appState.role}|${appState.hasAdminAccess}';
    if (nextScopeKey != _scopeKey) {
      _scopeKey = nextScopeKey;
      if (appState.hasAdminAccess) {
        unawaited(_refresh());
      } else {
        _stopPolling();
        setState(() {
          _history = [];
          _currentTask = null;
          _versionInfo = null;
          _metrics = null;
          _loading = false;
          _refreshing = false;
          _error = '';
        });
      }
    }
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  Future<void> _refresh() async {
    final appState = context.read<AppState>();
    if (!appState.hasAdminAccess) {
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _refreshing = true;
        _error = '';
      });
    }

    final errors = <String>[];

    try {
      final history = await appState.fetchListParsed<List<_DeployTask>>(
        '/api/deploy-history',
        params: const {'limit': 20},
        parser: (json) => json.map((e) => _DeployTask.fromJson(e as Map<String, dynamic>)).toList(),
        cacheTtl: Duration.zero,
      );
      if (mounted) {
        setState(() {
          _history = history.data;
          _currentTask = _history.where((task) => task.isActive).isNotEmpty
              ? _history.where((task) => task.isActive).first
              : null;
        });
      }
    } catch (error) {
      errors.add('배포 이력: $error');
    }

    final activeTaskId = _currentTask?.taskId;
    if (activeTaskId != null && activeTaskId.isNotEmpty) {
      try {
        final status = await appState.fetchMapParsed<_DeployTask>(
          '/api/deploy/$activeTaskId',
          parser: (json) => _DeployTask.fromJson(json),
          cacheTtl: Duration.zero,
        );
        if (mounted) {
          setState(() {
            _currentTask = status.data;
            final index = _history.indexWhere((task) => task.taskId == status.data.taskId);
            if (index >= 0) {
              _history[index] = status.data;
            }
          });
        }
      } catch (error) {
        errors.add('배포 상태: $error');
      }
    }

    try {
      final version = await appState.fetchMapParsed<_VersionInfo>(
        '/api/deploy/flutter-apk/version-info',
        parser: (json) => _VersionInfo.fromJson(json),
        cacheTtl: Duration.zero,
      );
      if (mounted) {
        setState(() {
          _versionInfo = version.data;
        });
      }
    } catch (error) {
      errors.add('버전 정보: $error');
    }

    try {
      final metrics = await appState.fetchMapParsed<_AppUpdateMetrics>(
        '/api/app-update/metrics',
        parser: (json) => _AppUpdateMetrics.fromJson(json),
        cacheTtl: Duration.zero,
      );
      if (mounted) {
        setState(() {
          _metrics = metrics.data;
        });
      }
    } catch (error) {
      errors.add('업데이트 지표: $error');
    }

    if (mounted) {
      setState(() {
        _error = errors.join(' · ');
        _loading = false;
        _refreshing = false;
      });
    }

    _syncPolling();
  }

  void _syncPolling() {
    final activeTask = _currentTask;
    if (activeTask == null || !activeTask.isActive) {
      _stopPolling();
      return;
    }
    if (_pollTimer != null) {
      return;
    }
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted) {
        return;
      }
      final appState = context.read<AppState>();
      if (!appState.hasAdminAccess || _currentTask == null || !_currentTask!.isActive) {
        _stopPolling();
        return;
      }
      try {
        final status = await appState.fetchMapParsed<_DeployTask>(
          '/api/deploy/${_currentTask!.taskId}',
          parser: (json) => _DeployTask.fromJson(json),
          cacheTtl: Duration.zero,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _currentTask = status.data;
          final index = _history.indexWhere((task) => task.taskId == status.data.taskId);
          if (index >= 0) {
            _history[index] = status.data;
          }
        });
        if (!_currentTask!.isActive) {
          _stopPolling();
        }
      } catch (_) {
        _stopPolling();
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final currentTask = _currentTask;
    final versionInfo = _versionInfo;
    final metrics = _metrics;
    final runningCount = _history.where((task) => task.isActive).length;
    final successCount = _history.where((task) => task.status == 'succeeded').length;
    final failedCount = _history.where((task) => task.status == 'failed').length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.admin_panel_settings_outlined, color: Color(0xFF0F172A)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '관리자 배포/업데이트',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _refreshing ? null : () => unawaited(_refresh()),
                icon: const Icon(Icons.refresh),
                label: Text(_refreshing ? '갱신 중...' : '새로고침'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '배포 상태, 최근 이력, 버전 정책, 앱 업데이트 지표를 한 곳에서 확인합니다.',
            style: TextStyle(color: Color(0xFF64748B)),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _error,
              style: const TextStyle(
                color: Color(0xFFDC2626),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_loading && _history.isEmpty && versionInfo == null && metrics == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _AdminStatCard(label: '최근 작업', value: '${_history.length}건'),
                _AdminStatCard(label: '진행 중', value: '$runningCount건', accent: runningCount > 0),
                _AdminStatCard(label: '성공', value: '$successCount건'),
                _AdminStatCard(label: '실패', value: '$failedCount건', accent: failedCount > 0),
              ],
            ),
            const SizedBox(height: 16),
            if (currentTask != null) ...[
              const _SectionTitle('현재 작업'),
              const SizedBox(height: 8),
              _DetailGrid(
                items: [
                  _DetailItem('대상', currentTask.target),
                  _DetailItem('상태', currentTask.status),
                  _DetailItem('단계', currentTask.currentStep),
                  _DetailItem(
                    '검증',
                    currentTask.target == 'flutter-apk'
                        ? 'artifact'
                        : currentTask.healthCheckOk == null
                            ? (currentTask.dryRun ? 'skip' : 'pending')
                            : (currentTask.healthCheckOk == true ? 'ok' : 'fail'),
                  ),
                  _DetailItem('시작', UiFormat.compactDateTime(currentTask.startedAt)),
                  _DetailItem('종료', UiFormat.compactDateTime(currentTask.finishedAt)),
                  _DetailItem('요청자', currentTask.requestedBy.isEmpty ? '-' : currentTask.requestedBy),
                  _DetailItem('로그', currentTask.logPath.isEmpty ? '-' : currentTask.logPath, mono: true),
                ],
              ),
              if (currentTask.reason.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '사유: ${currentTask.reason}',
                  style: const TextStyle(color: Color(0xFF475569)),
                ),
              ],
              if (currentTask.errorMessage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  currentTask.errorMessage,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],
            if (versionInfo != null) ...[
              const _SectionTitle('버전 정보'),
              const SizedBox(height: 8),
              _DetailGrid(
                items: [
                  _DetailItem('현재 업데이트 정책', versionInfo.policyLabel),
                  _DetailItem('배포 시 빌드', versionInfo.pubspecLabel),
                  _DetailItem('최근 산출물', versionInfo.releaseLabel),
                  _DetailItem('pubspec 버전', versionInfo.pubspecVersionRaw.isEmpty ? '-' : versionInfo.pubspecVersionRaw, mono: true),
                  _DetailItem('정책 소스', versionInfo.policySource ?? '-'),
                  _DetailItem('다운로드 URL', versionInfo.downloadUrl.isEmpty ? '-' : versionInfo.downloadUrl, mono: true),
                  _DetailItem('최근 배포 시각', versionInfo.latestReleasePublishedAt ?? versionInfo.publishedAt),
                  _DetailItem('release 디렉토리', versionInfo.releaseDir.isEmpty ? '-' : versionInfo.releaseDir, mono: true),
                ],
              ),
              if ((versionInfo.policyWarning ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  versionInfo.policyWarning!.trim(),
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if ((versionInfo.latestReleaseReadError ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  versionInfo.latestReleaseReadError!,
                  style: const TextStyle(color: Color(0xFFDC2626)),
                ),
              ],
              const SizedBox(height: 16),
            ],
            if (metrics != null) ...[
              const _SectionTitle('업데이트 지표'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _AdminStatCard(label: '체크 총량', value: '${metrics.appUpdateCheckTotal}'),
                  _AdminStatCard(label: '체크 실패', value: '${metrics.appUpdateCheckFailedTotal}', accent: metrics.appUpdateCheckFailedTotal > 0),
                  _AdminStatCard(label: 'URL 누락', value: '${metrics.downloadUrlEmptyTotal}', accent: metrics.downloadUrlEmptyTotal > 0),
                  _AdminStatCard(label: '주 정책 소스', value: metrics.topPolicySource),
                ],
              ),
              if (metrics.policySourceTotal.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: (metrics.policySourceTotal.entries.toList()
                        ..sort((a, b) => a.key.compareTo(b.key)))
                      .map(
                        (entry) => Chip(
                          label: Text('${entry.key}: ${entry.value}'),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                          backgroundColor: const Color(0xFFF8FAFC),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 16),
            ],
            const _SectionTitle('최근 배포 이력'),
            const SizedBox(height: 8),
            if (_history.isEmpty)
              const Text(
                '배포 이력이 없습니다.',
                style: TextStyle(color: Color(0xFF64748B)),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('시각')),
                    DataColumn(label: Text('대상')),
                    DataColumn(label: Text('상태')),
                    DataColumn(label: Text('단계')),
                    DataColumn(label: Text('dry-run')),
                    DataColumn(label: Text('요청자')),
                    DataColumn(label: Text('사유')),
                  ],
                  rows: _history
                      .map(
                        (task) => DataRow(
                          cells: [
                            DataCell(Text(UiFormat.compactDateTime(task.startedAt ?? task.finishedAt))),
                            DataCell(Text(task.target)),
                            DataCell(Text(task.status)),
                            DataCell(Text(task.currentStep)),
                            DataCell(Text(task.dryRun ? 'yes' : 'no')),
                            DataCell(Text(task.requestedBy.isEmpty ? '-' : task.requestedBy)),
                            DataCell(Text(task.reason.isEmpty ? '-' : task.reason)),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _AdminStatCard extends StatelessWidget {
  final String label;
  final String value;
  final bool accent;

  const _AdminStatCard({
    required this.label,
    required this.value,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              color: accent ? const Color(0xFFB45309) : const Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: Color(0xFF475569),
      ),
    );
  }
}

class _DetailItem {
  final String label;
  final String value;
  final bool mono;

  const _DetailItem(this.label, this.value, {this.mono = false});
}

class _DetailGrid extends StatelessWidget {
  final List<_DetailItem> items;

  const _DetailGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: items
          .map(
            (item) => Container(
              width: 260,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                color: const Color(0xFFF8FAFC),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.value.isEmpty ? '-' : item.value,
                    style: TextStyle(
                      fontSize: 13,
                      color: const Color(0xFF0F172A),
                      fontWeight: FontWeight.w600,
                      fontFamily: item.mono ? 'monospace' : null,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}
