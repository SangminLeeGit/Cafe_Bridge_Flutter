import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/async_request_guard.dart';
import '../models/api_contracts.dart';
import '../models/dashboard_model.dart';
import '../services/api.dart';
import 'service_health.dart';
import '../state/app_state.dart';
import '../widgets/access_gate.dart';
import '../widgets/app_update_banner.dart';
import '../widgets/responsive_wrap_grid.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with AsyncRequestGuard<SettingsScreen> {
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final apiBaseUrl = context.read<AppState>().apiBaseUrl;
    if (_lastSyncedApiBaseUrl == apiBaseUrl) {
      return;
    }
    _lastSyncedApiBaseUrl = apiBaseUrl;
    if (_controller.text != apiBaseUrl) {
      _controller.value = TextEditingValue(
        text: apiBaseUrl,
        selection: TextSelection.collapsed(offset: apiBaseUrl.length),
      );
    }
  }

  Future<void> _checkConnection() async {
    if (!mounted) return;
    final request = beginAsyncRequest();
    setState(() {
      _isChecking = true;
      _statusMessage = '';
    });

    try {
      final isHealthy = await context.read<AppState>().checkConnection(
            _controller.text,
          );
      if (!isCurrentAsyncRequest(request)) {
        return;
      }
      setState(() {
        _statusOk = isHealthy;
        _statusMessage = _statusOk ? '백엔드 연결 성공' : '헬스체크 응답이 비정상입니다.';
        _isChecking = false;
      });
    } catch (error) {
      if (!isCurrentAsyncRequest(request)) {
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
    final canEditServer = kDebugMode || appState.hasAdminAccess;

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
          readOnly: !canEditServer,
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
                onPressed: !canEditServer
                    ? null
                    : () async {
                        final appState = context.read<AppState>();
                        final messenger = ScaffoldMessenger.of(context);

                        try {
                          await appState.updateApiBaseUrl(_controller.text);
                          if (!context.mounted) {
                            return;
                          }
                          messenger.showSnackBar(
                            const SnackBar(
                                content: Text('서버 주소를 저장하고 적용했습니다.')),
                          );
                        } on FormatException catch (error) {
                          if (!context.mounted) {
                            return;
                          }
                          messenger.showSnackBar(
                            SnackBar(content: Text(error.message)),
                          );
                        }
                      },
                child: const Text('적용'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: !canEditServer
                    ? null
                    : () async {
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
          onPressed: _isChecking || !canEditServer ? null : _checkConnection,
          icon: const Icon(Icons.health_and_safety_outlined),
          label: Text(_isChecking ? '확인 중...' : '연결 테스트'),
        ),
        if (!canEditServer) ...[
          const SizedBox(height: 8),
          const Text(
            '운영 서버 주소 변경은 admin 또는 디버그 빌드에서만 가능합니다.',
            style: TextStyle(color: Color(0xFF64748B)),
          ),
        ],
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
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ServiceHealthScreen()),
          ),
          icon: const Icon(Icons.monitor_heart_outlined),
          label: const Text('외부 서버 상태 관리'),
        ),
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
          appState.updateInfo == null ? '-' : appState.updateInfo!.displayLabel,
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
                Icon(Icons.admin_panel_settings_outlined,
                    color: Color(0xFF0F172A)),
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
              color: _passwordOk
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFDC2626),
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
          UiFormat.weekday(ApiService.formatDate(ApiService.kstNow())),
        ),
        if (appState.hasAdminAccess) ...[
          const SizedBox(height: 32),
          const AdminDeployMonitor(),
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
              MaterialPageRoute(
                builder: (_) => const AccessGate(
                  minimumRole: UserRole.admin,
                  fullScreen: true,
                  child: _UserManagementScreen(),
                ),
              ),
            ),
            icon: const Icon(Icons.manage_accounts_outlined),
            label: const Text('계정 관리'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const AccessGate(
                  minimumRole: UserRole.admin,
                  fullScreen: true,
                  child: _AuditLogScreen(),
                ),
              ),
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

class DeployManagementScreen extends StatelessWidget {
  const DeployManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('배포 관리', style: TextStyle(fontWeight: FontWeight.w700)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE2E8F0)),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (appState.hasAdminAccess)
              const _AdminDeployPanel()
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: Color(0xFF64748B),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '배포 관리는 admin 권한 계정에서만 사용할 수 있습니다.',
                        style: TextStyle(
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Read-only admin deployment monitor, also exposed for focused widget tests.
class AdminDeployMonitor extends StatelessWidget {
  const AdminDeployMonitor({super.key});

  @override
  Widget build(BuildContext context) {
    if (context.watch<AppState>().hasAdminAccess) {
      return const _AdminDeployPanel();
    }
    return const _AdminAccessMessage(
      message: '배포 상태와 APK CI 작업은 관리자 권한 계정에서만 확인할 수 있습니다.',
    );
  }
}

class _AdminAccessMessage extends StatelessWidget {
  final String message;

  const _AdminAccessMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        border: Border.all(color: const Color(0xFFFED7AA)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF9A3412),
          fontWeight: FontWeight.w600,
        ),
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
      final result = await appState.fetchMapParsed<List<AdminUserContract>>(
        '/api/auth/users',
        parser: (json) {
          return requireListOfMaps(json, 'users')
              .map(AdminUserContract.fromJson)
              .toList(growable: false);
        },
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('계정 관리', style: TextStyle(fontWeight: FontWeight.w700)),
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
                    itemCount: _users.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      if (i == 0) {
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED),
                            border: Border.all(color: const Color(0xFFFED7AA)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            '모바일에서는 계정을 조회만 할 수 있습니다. 생성, 권한 변경, 활성화 변경은 웹 관리자 화면을 이용하세요.',
                            style: TextStyle(
                              color: Color(0xFF9A3412),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }
                      final u = _users[i - 1];
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
                          trailing: const Icon(Icons.visibility_outlined),
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
      final result = await appState.fetchMapParsed<List<AuditLogEntryContract>>(
        '/api/auth/audit-logs',
        parser: (json) {
          return requireListOfMaps(json, 'logs')
              .map(AuditLogEntryContract.fromJson)
              .toList(growable: false);
        },
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
                          e.eventType.isEmpty ? '이벤트' : e.eventType,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          [
                            e.loginId,
                            e.target,
                            e.detailJson,
                          ]
                              .whereType<String>()
                              .where((value) => value.isNotEmpty)
                              .join('  ·  '),
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
    final pubspec =
        (json['pubspec'] as Map?)?.cast<String, dynamic>() ?? const {};
    final updatePolicy =
        (json['update_policy'] as Map?)?.cast<String, dynamic>() ?? const {};
    final latestRelease =
        (json['latest_release'] as Map?)?.cast<String, dynamic>() ?? const {};
    final latest =
        (latestRelease['latest'] as Map?)?.cast<String, dynamic>() ?? const {};

    return _VersionInfo(
      pubspecVersionRaw: pubspec['version_raw']?.toString() ?? '',
      pubspecVersion: pubspec['version']?.toString() ?? '',
      pubspecBuild: int.tryParse(pubspec['build']?.toString() ?? '') ?? 0,
      pubspecPath: pubspec['pubspec_path']?.toString() ?? '',
      latestVersion: updatePolicy['latest_version']?.toString() ?? '',
      latestBuild:
          int.tryParse(updatePolicy['latest_build']?.toString() ?? '') ?? 0,
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
      latestReleaseBuild:
          int.tryParse(latest['latest_build']?.toString() ?? ''),
      latestReleaseFileName: latest['file_name']?.toString(),
      latestReleasePublishedAt: latest['published_at']?.toString(),
      latestReleaseArtifactPath: latest['artifact_path']?.toString(),
      latestReleaseDownloadUrl: latest['download_url']?.toString(),
      latestReleaseSha256: latest['sha256']?.toString(),
      latestReleaseFileSize:
          int.tryParse(latest['file_size']?.toString() ?? ''),
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
    final rawPolicySourceTotal =
        (json['policy_source_total'] as Map?)?.cast<String, dynamic>() ??
            const {};
    return _AppUpdateMetrics(
      appUpdateCheckTotal:
          int.tryParse(json['app_update_check_total']?.toString() ?? '') ?? 0,
      appUpdateCheckFailedTotal: int.tryParse(
              json['app_update_check_failed_total']?.toString() ?? '') ??
          0,
      downloadUrlEmptyTotal:
          int.tryParse(json['download_url_empty_total']?.toString() ?? '') ?? 0,
      policySourceTotal: rawPolicySourceTotal.map(
          (key, value) => MapEntry(key, int.tryParse(value.toString()) ?? 0)),
    );
  }

  String get topPolicySource {
    if (policySourceTotal.isEmpty) {
      return '-';
    }
    final entries = policySourceTotal.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.first.key;
  }
}

class _RuntimeStatus {
  final String service;
  final String status;
  final String observedAt;
  final String runtimeCommitSha;
  final String runtimeShortCommitSha;
  final String runtimeReleaseId;
  final String runtimeStartedAt;
  final int uptimeSeconds;
  final String deploymentStatus;
  final String deploymentCommitSha;
  final String deploymentShortCommitSha;
  final String deploymentReleaseId;
  final String deployedAt;
  final String deployStartedAt;
  final String deploymentSource;
  final bool? commitMatch;

  const _RuntimeStatus({
    required this.service,
    required this.status,
    required this.observedAt,
    required this.runtimeCommitSha,
    required this.runtimeShortCommitSha,
    required this.runtimeReleaseId,
    required this.runtimeStartedAt,
    required this.uptimeSeconds,
    required this.deploymentStatus,
    required this.deploymentCommitSha,
    required this.deploymentShortCommitSha,
    required this.deploymentReleaseId,
    required this.deployedAt,
    required this.deployStartedAt,
    required this.deploymentSource,
    required this.commitMatch,
  });

  factory _RuntimeStatus.fromJson(Map<String, dynamic> json) {
    final runtime = asMap(json['runtime']);
    final deployment = asMap(json['deployment']);
    return _RuntimeStatus(
      service: asString(json['service']),
      status: asString(json['status']).trim().toLowerCase(),
      observedAt: asString(json['observed_at']),
      runtimeCommitSha: asString(runtime['commit_sha']),
      runtimeShortCommitSha: asString(runtime['short_commit_sha']),
      runtimeReleaseId: asString(runtime['release_id']),
      runtimeStartedAt: asString(runtime['started_at']),
      uptimeSeconds: asInt(runtime['uptime_seconds']),
      deploymentStatus: asString(deployment['status']).trim().toLowerCase(),
      deploymentCommitSha: asString(deployment['commit_sha']),
      deploymentShortCommitSha: asString(deployment['short_commit_sha']),
      deploymentReleaseId: asString(deployment['release_id']),
      deployedAt: asString(deployment['deployed_at']),
      deployStartedAt: asString(deployment['deploy_started_at']),
      deploymentSource: asString(deployment['source']),
      commitMatch: deployment['commit_match'] is bool
          ? deployment['commit_match'] as bool
          : null,
    );
  }
}

class _FlutterApkCiJob {
  final String jobId;
  final String status;
  final String repoFullName;
  final String branch;
  final String ref;
  final String commitSha;
  final String requestedBy;
  final String deployTaskId;
  final String versionName;
  final int buildNumber;
  final String fileName;
  final String sha256;
  final int fileSize;
  final String downloadUrl;
  final String releaseNotes;
  final String errorMessage;
  final String createdAt;
  final String updatedAt;
  final String registeredAt;

  const _FlutterApkCiJob({
    required this.jobId,
    required this.status,
    required this.repoFullName,
    required this.branch,
    required this.ref,
    required this.commitSha,
    required this.requestedBy,
    required this.deployTaskId,
    required this.versionName,
    required this.buildNumber,
    required this.fileName,
    required this.sha256,
    required this.fileSize,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
    required this.registeredAt,
  });

  factory _FlutterApkCiJob.fromJson(Map<String, dynamic> json) {
    return _FlutterApkCiJob(
      jobId: asString(json['job_id']),
      status: asString(json['status']).trim().toLowerCase(),
      repoFullName: asString(json['repo_full_name']),
      branch: asString(json['branch']),
      ref: asString(json['ref']),
      commitSha: asString(json['commit_sha']),
      requestedBy: asString(json['requested_by']),
      deployTaskId: asString(json['deploy_task_id']),
      versionName: asString(json['version_name']),
      buildNumber: asInt(json['build_number']),
      fileName: asString(json['file_name']),
      sha256: asString(json['sha256']),
      fileSize: asInt(json['file_size']),
      downloadUrl: asString(json['download_url']),
      releaseNotes: asString(json['release_notes']),
      errorMessage: asString(json['error_message']),
      createdAt: asString(json['created_at']),
      updatedAt: asString(json['updated_at']),
      registeredAt: asString(json['registered_at']),
    );
  }

  String get shortCommitSha {
    if (commitSha.startsWith('manual-dispatch:')) return 'manual-dispatch';
    if (commitSha.length <= 8) return commitSha.isEmpty ? '-' : commitSha;
    return commitSha.substring(0, 8);
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
  _RuntimeStatus? _runtimeStatus;
  List<_FlutterApkCiJob> _ciJobs = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _runtimeLoading = true;
  bool _runtimeRefreshing = false;
  bool _ciJobsLoading = true;
  bool _ciJobsLoaded = false;
  bool _ciJobsRefreshing = false;
  String _message = '';
  String _error = '';
  String _runtimeError = '';
  String _ciJobsError = '';
  String _scopeKey = '';
  Timer? _pollTimer;
  bool _pollInFlight = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = context.watch<AppState>();
    final nextScopeKey =
        '${appState.apiBaseUrl}|${appState.loginId}|${appState.role}|${appState.hasAdminAccess}';
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
          _runtimeStatus = null;
          _ciJobs = [];
          _loading = false;
          _refreshing = false;
          _runtimeLoading = false;
          _runtimeRefreshing = false;
          _ciJobsLoading = false;
          _ciJobsLoaded = false;
          _ciJobsRefreshing = false;
          _message = '';
          _error = '';
          _runtimeError = '';
          _ciJobsError = '';
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
    if (!appState.hasAdminAccess ||
        _refreshing ||
        _runtimeRefreshing ||
        _ciJobsRefreshing) {
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _refreshing = true;
        _error = '';
        _runtimeLoading = _runtimeStatus == null;
        _runtimeRefreshing = true;
        _runtimeError = '';
        _ciJobsLoading = !_ciJobsLoaded;
        _ciJobsRefreshing = true;
        _ciJobsError = '';
      });
    }

    final errors = <String>[];
    final previousTask = _currentTask;

    try {
      final history = await appState.fetchMapParsed<List<_DeployTask>>(
        '/api/deploy-history',
        params: const {'limit': 20},
        parser: (json) {
          return requireListOfMaps(json, 'tasks')
              .map(_DeployTask.fromJson)
              .toList(growable: false);
        },
        cacheTtl: Duration.zero,
      );
      if (mounted) {
        final nextHistory = history.data;
        _DeployTask? nextCurrentTask;
        for (final task in nextHistory) {
          if (task.isActive) {
            nextCurrentTask = task;
            break;
          }
        }
        setState(() {
          _history = nextHistory;
          _currentTask = nextCurrentTask ??
              (previousTask?.isActive == true ? previousTask : null);
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
          parser: _parseDeployTaskResponse,
          cacheTtl: Duration.zero,
        );
        if (mounted) {
          setState(() {
            _currentTask = status.data;
            final index = _history
                .indexWhere((task) => task.taskId == status.data.taskId);
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

    await Future.wait([
      _fetchRuntimeStatus(),
      _fetchCiJobs(),
    ]);

    if (mounted) {
      setState(() {
        _error = errors.join(' · ');
        _loading = false;
        _refreshing = false;
        _runtimeLoading = false;
        _runtimeRefreshing = false;
        _ciJobsLoading = false;
        _ciJobsRefreshing = false;
      });
    }

    _syncPolling();
  }

  Future<void> _fetchRuntimeStatus() async {
    final appState = context.read<AppState>();
    final requestScope = _scopeKey;
    try {
      final response = await appState.fetchMapParsed<_RuntimeStatus>(
        '/api/admin/runtime-status',
        parser: _RuntimeStatus.fromJson,
        cacheTtl: Duration.zero,
      );
      if (!mounted ||
          !context.read<AppState>().hasAdminAccess ||
          requestScope != _scopeKey) {
        return;
      }
      setState(() {
        _runtimeStatus = response.data;
        _runtimeError = '';
        _runtimeLoading = false;
      });
    } catch (error) {
      if (!mounted || requestScope != _scopeKey) return;
      setState(() {
        if (error is ApiException && error.statusCode == 403) {
          _runtimeStatus = null;
        }
        _runtimeError = _adminRequestError(error, '운영 상태를 불러오지 못했습니다.');
        _runtimeLoading = false;
      });
    }
  }

  Future<void> _fetchCiJobs() async {
    final appState = context.read<AppState>();
    final requestScope = _scopeKey;
    try {
      final response = await appState.fetchMapParsed<List<_FlutterApkCiJob>>(
        '/api/ci/flutter-apk/jobs',
        params: const {'limit': 20},
        parser: (json) => requireListOfMaps(json, 'jobs')
            .map(_FlutterApkCiJob.fromJson)
            .toList(growable: false),
        cacheTtl: Duration.zero,
      );
      if (!mounted ||
          !context.read<AppState>().hasAdminAccess ||
          requestScope != _scopeKey) {
        return;
      }
      setState(() {
        _ciJobs = response.data;
        _ciJobsError = '';
        _ciJobsLoading = false;
        _ciJobsLoaded = true;
      });
    } catch (error) {
      if (!mounted || requestScope != _scopeKey) return;
      setState(() {
        if (error is ApiException && error.statusCode == 403) {
          _ciJobs = [];
          _ciJobsLoaded = true;
        }
        _ciJobsError = _adminRequestError(error, 'APK CI 작업을 불러오지 못했습니다.');
        _ciJobsLoading = false;
      });
    }
  }

  Future<void> _refreshRuntimeStatus() async {
    if (!context.read<AppState>().hasAdminAccess ||
        _refreshing ||
        _runtimeRefreshing) {
      return;
    }
    setState(() {
      _runtimeRefreshing = true;
      _runtimeLoading = _runtimeStatus == null;
      _runtimeError = '';
    });
    await _fetchRuntimeStatus();
    if (mounted) setState(() => _runtimeRefreshing = false);
  }

  Future<void> _refreshCiJobs() async {
    if (!context.read<AppState>().hasAdminAccess ||
        _refreshing ||
        _ciJobsRefreshing) {
      return;
    }
    setState(() {
      _ciJobsRefreshing = true;
      _ciJobsLoading = !_ciJobsLoaded;
      _ciJobsError = '';
    });
    await _fetchCiJobs();
    if (mounted) setState(() => _ciJobsRefreshing = false);
  }

  Future<void> _showCiJobDetail(_FlutterApkCiJob job) async {
    if (!context.read<AppState>().hasAdminAccess) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _CiJobDetailDialog(job: job),
    );
  }

  Widget _buildRuntimeMonitor() {
    final status = _runtimeStatus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionTitle('현재 런타임 상태')),
            TextButton.icon(
              onPressed: _runtimeRefreshing || _refreshing
                  ? null
                  : () => unawaited(_refreshRuntimeStatus()),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(_runtimeRefreshing ? '확인 중...' : '상태 새로고침'),
            ),
          ],
        ),
        if (_runtimeError.isNotEmpty) ...[
          const SizedBox(height: 8),
          _AdminInlineMessage(
            message: _runtimeError,
            isError: true,
          ),
        ],
        if (status == null && _runtimeLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (status == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '런타임 상태를 확인할 수 없습니다.',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          )
        else ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _AdminStatusTag(
                label: _runtimeStatusLabel(status.status),
                color: _runtimeStatusColor(status.status),
              ),
              _AdminStatusTag(
                label: _commitMatchLabel(status.commitMatch),
                color: _commitMatchColor(status.commitMatch),
              ),
              Text(
                '마지막 확인 ${UiFormat.compactDateTime(status.observedAt)}',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          if (status.status == 'drifted') ...[
            const SizedBox(height: 10),
            const _AdminInlineMessage(
              message:
                  '실행 중인 런타임과 마지막 배포 manifest의 commit이 다릅니다. 런타임과 배포 기록을 함께 확인하세요.',
              isError: true,
              warning: true,
            ),
          ],
          const SizedBox(height: 10),
          _DetailGrid(
            items: [
              _DetailItem(
                '런타임 commit',
                status.runtimeShortCommitSha.isEmpty
                    ? '확인 불가'
                    : status.runtimeShortCommitSha,
                mono: true,
              ),
              _DetailItem(
                '런타임 release ID',
                status.runtimeReleaseId.isEmpty ? '-' : status.runtimeReleaseId,
                mono: true,
              ),
              _DetailItem(
                '프로세스 시작',
                UiFormat.compactDateTime(status.runtimeStartedAt),
              ),
              _DetailItem(
                  '현재 uptime', _formatRuntimeUptime(status.uptimeSeconds)),
              _DetailItem(
                '배포 상태',
                _deploymentStatusLabel(status.deploymentStatus),
              ),
              _DetailItem(
                '배포 commit',
                status.deploymentShortCommitSha.isEmpty
                    ? '기록 없음'
                    : status.deploymentShortCommitSha,
                mono: true,
              ),
              _DetailItem(
                '배포 release ID',
                status.deploymentReleaseId.isEmpty
                    ? '기록 없음'
                    : status.deploymentReleaseId,
                mono: true,
              ),
              _DetailItem(
                '배포 시각',
                UiFormat.compactDateTime(status.deployedAt),
              ),
              _DetailItem(
                '배포 시작 시각',
                UiFormat.compactDateTime(status.deployStartedAt),
              ),
              _DetailItem(
                '배포 출처',
                status.deploymentSource.isEmpty ? '-' : status.deploymentSource,
              ),
              _DetailItem(
                '전체 런타임 commit',
                status.runtimeCommitSha.isEmpty
                    ? '확인 불가'
                    : status.runtimeCommitSha,
                mono: true,
              ),
              _DetailItem(
                '전체 배포 commit',
                status.deploymentCommitSha.isEmpty
                    ? '기록 없음'
                    : status.deploymentCommitSha,
                mono: true,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildCiJobsMonitor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionTitle('최근 Flutter APK CI 작업')),
            TextButton.icon(
              onPressed: _ciJobsRefreshing || _refreshing
                  ? null
                  : () => unawaited(_refreshCiJobs()),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(_ciJobsRefreshing ? '확인 중...' : '목록 새로고침'),
            ),
          ],
        ),
        if (_ciJobsError.isNotEmpty) ...[
          const SizedBox(height: 8),
          _AdminInlineMessage(message: _ciJobsError, isError: true),
        ],
        if (_ciJobsLoading && !_ciJobsLoaded)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_ciJobs.isEmpty && _ciJobsError.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '최근 APK CI 작업이 없습니다.',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          )
        else if (_ciJobs.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final job in _ciJobs) ...[
            _CiJobTile(
              job: job,
              onTap: () => unawaited(_showCiJobDetail(job)),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
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
      if (!mounted || _pollInFlight) {
        return;
      }
      final appState = context.read<AppState>();
      if (!appState.hasAdminAccess ||
          _currentTask == null ||
          !_currentTask!.isActive) {
        _stopPolling();
        return;
      }
      _pollInFlight = true;
      try {
        final status = await appState.fetchMapParsed<_DeployTask>(
          '/api/deploy/${_currentTask!.taskId}',
          parser: _parseDeployTaskResponse,
          cacheTtl: Duration.zero,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _currentTask = status.data;
          final index =
              _history.indexWhere((task) => task.taskId == status.data.taskId);
          if (index >= 0) {
            _history[index] = status.data;
          } else {
            _history = [status.data, ..._history];
          }
          if (status.data.status == 'succeeded') {
            _message = '${status.data.target} 배포가 완료되었습니다.';
            _error = '';
          } else if (status.data.status == 'failed') {
            _error = status.data.errorMessage.isNotEmpty
                ? status.data.errorMessage
                : '${status.data.target} 배포가 실패했습니다.';
          }
        });
        if (!_currentTask!.isActive) {
          _stopPolling();
          unawaited(_refresh());
        }
      } catch (_) {
        _stopPolling();
      } finally {
        _pollInFlight = false;
      }
    });
  }

  _DeployTask _parseDeployTaskResponse(Map<String, dynamic> json) {
    return _DeployTask.fromJson(asMap(json['task']));
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
    final successCount =
        _history.where((task) => task.status == 'succeeded').length;
    final failedCount =
        _history.where((task) => task.status == 'failed').length;

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
              const Icon(Icons.admin_panel_settings_outlined,
                  color: Color(0xFF0F172A)),
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
                onPressed:
                    _refreshing || _runtimeRefreshing || _ciJobsRefreshing
                        ? null
                        : () => unawaited(_refresh()),
                icon: const Icon(Icons.refresh),
                label: Text(_refreshing ? '갱신 중...' : '새로고침'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '배포 상태와 이력을 확인합니다.',
            style: TextStyle(color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              border: Border.all(color: const Color(0xFFFED7AA)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '모바일은 배포 상태를 조회하는 모니터입니다. 새 배포 실행은 웹 관리자 화면을 이용하세요.',
              style: TextStyle(
                color: Color(0xFF9A3412),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_message.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _message,
              style: const TextStyle(
                color: Color(0xFF0F766E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
          _buildRuntimeMonitor(),
          const SizedBox(height: 20),
          _buildCiJobsMonitor(),
          const SizedBox(height: 16),
          if (_loading &&
              _history.isEmpty &&
              versionInfo == null &&
              metrics == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            ResponsiveWrapGrid(
              minItemWidth: 140,
              maxColumns: 4,
              children: [
                _AdminStatCard(label: '최근 작업', value: '${_history.length}건'),
                _AdminStatCard(
                  label: '진행 중',
                  value: '$runningCount건',
                  accent: runningCount > 0,
                ),
                _AdminStatCard(label: '성공', value: '$successCount건'),
                _AdminStatCard(
                  label: '실패',
                  value: '$failedCount건',
                  accent: failedCount > 0,
                ),
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
                            : (currentTask.healthCheckOk == true
                                ? 'ok'
                                : 'fail'),
                  ),
                  _DetailItem(
                      '시작', UiFormat.compactDateTime(currentTask.startedAt)),
                  _DetailItem(
                      '종료', UiFormat.compactDateTime(currentTask.finishedAt)),
                  _DetailItem(
                      '요청자',
                      currentTask.requestedBy.isEmpty
                          ? '-'
                          : currentTask.requestedBy),
                  _DetailItem('로그',
                      currentTask.logPath.isEmpty ? '-' : currentTask.logPath,
                      mono: true),
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
                  _DetailItem(
                      'pubspec 버전',
                      versionInfo.pubspecVersionRaw.isEmpty
                          ? '-'
                          : versionInfo.pubspecVersionRaw,
                      mono: true),
                  _DetailItem('정책 소스', versionInfo.policySource ?? '-'),
                  _DetailItem(
                      '다운로드 URL',
                      versionInfo.downloadUrl.isEmpty
                          ? '-'
                          : versionInfo.downloadUrl,
                      mono: true),
                  _DetailItem(
                      '최근 배포 시각',
                      versionInfo.latestReleasePublishedAt ??
                          versionInfo.publishedAt),
                  _DetailItem(
                      'release 디렉토리',
                      versionInfo.releaseDir.isEmpty
                          ? '-'
                          : versionInfo.releaseDir,
                      mono: true),
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
              ResponsiveWrapGrid(
                minItemWidth: 140,
                maxColumns: 4,
                children: [
                  _AdminStatCard(
                    label: '체크 총량',
                    value: '${metrics.appUpdateCheckTotal}',
                  ),
                  _AdminStatCard(
                    label: '체크 실패',
                    value: '${metrics.appUpdateCheckFailedTotal}',
                    accent: metrics.appUpdateCheckFailedTotal > 0,
                  ),
                  _AdminStatCard(
                    label: 'URL 누락',
                    value: '${metrics.downloadUrlEmptyTotal}',
                    accent: metrics.downloadUrlEmptyTotal > 0,
                  ),
                  _AdminStatCard(
                    label: '주 정책 소스',
                    value: metrics.topPolicySource,
                  ),
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
                            DataCell(Text(UiFormat.compactDateTime(
                                task.startedAt ?? task.finishedAt))),
                            DataCell(Text(task.target)),
                            DataCell(Text(task.status)),
                            DataCell(Text(task.currentStep)),
                            DataCell(Text(task.dryRun ? 'yes' : 'no')),
                            DataCell(Text(task.requestedBy.isEmpty
                                ? '-'
                                : task.requestedBy)),
                            DataCell(
                                Text(task.reason.isEmpty ? '-' : task.reason)),
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
      width: double.infinity,
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
    return ResponsiveWrapGrid(
      minItemWidth: 220,
      maxColumns: 3,
      children: items
          .map(
            (item) => Container(
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
          .toList(growable: false),
    );
  }
}

String _adminRequestError(Object error, String fallback) {
  if (error is ApiException && error.statusCode == 403) {
    return '권한 없음: 관리자 권한이 필요합니다.';
  }
  if (error is ApiException && error.statusCode == 404) {
    return '요청한 정보를 찾을 수 없습니다 (404).';
  }
  final message = error.toString().trim();
  return message.isEmpty ? fallback : message;
}

String _runtimeStatusLabel(String status) => switch (status) {
      'running' => '정상',
      'drifted' => '런타임 불일치',
      'deploying' => '배포 중',
      _ => '알 수 없음',
    };

Color _runtimeStatusColor(String status) => switch (status) {
      'running' => const Color(0xFF15803D),
      'drifted' => const Color(0xFFB45309),
      'deploying' => const Color(0xFFB45309),
      _ => const Color(0xFF64748B),
    };

String _deploymentStatusLabel(String status) => switch (status) {
      'succeeded' => '배포 성공',
      'deploying' => '배포 중',
      _ => status.isEmpty || status == 'unknown' ? '기록 없음' : status,
    };

String _commitMatchLabel(bool? matches) => switch (matches) {
      true => '일치',
      false => '불일치',
      null => '확인 불가',
    };

Color _commitMatchColor(bool? matches) => switch (matches) {
      true => const Color(0xFF15803D),
      false => const Color(0xFFB45309),
      null => const Color(0xFF64748B),
    };

String _formatRuntimeUptime(int seconds) {
  final total = seconds < 0 ? 0 : seconds;
  final days = total ~/ 86400;
  final hours = (total % 86400) ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  if (days > 0) return '$days일 $hours시간';
  if (hours > 0) return '$hours시간 $minutes분';
  if (minutes > 0) return '$minutes분';
  return '$total초';
}

String _ciStatusLabel(String status) => switch (status) {
      'received' => '접수',
      'queued' => '대기',
      'building' => '빌드 중',
      'succeeded' => '성공',
      'registered' => '등록 완료',
      'failed' => '실패',
      _ => status.isEmpty ? '알 수 없음' : status,
    };

Color _ciStatusColor(String status) => switch (status) {
      'succeeded' || 'registered' => const Color(0xFF15803D),
      'failed' => const Color(0xFFB91C1C),
      'building' || 'queued' || 'received' => const Color(0xFFB45309),
      _ => const Color(0xFF64748B),
    };

String _formatFileSize(int bytes) {
  if (bytes < 0) return '-';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

class _AdminStatusTag extends StatelessWidget {
  final String label;
  final Color color;

  const _AdminStatusTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _AdminInlineMessage extends StatelessWidget {
  final String message;
  final bool isError;
  final bool warning;

  const _AdminInlineMessage({
    required this.message,
    this.isError = false,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = warning
        ? const Color(0xFFB45309)
        : isError
            ? const Color(0xFFB91C1C)
            : const Color(0xFF475569);
    final background = warning
        ? const Color(0xFFFFF7ED)
        : isError
            ? const Color(0xFFFEF2F2)
            : const Color(0xFFF8FAFC);
    final border = warning
        ? const Color(0xFFFED7AA)
        : isError
            ? const Color(0xFFFECACA)
            : const Color(0xFFE2E8F0);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _CiJobTile extends StatelessWidget {
  final _FlutterApkCiJob job;
  final VoidCallback onTap;

  const _CiJobTile({required this.job, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final version = formatVersionDisplay(job.versionName, job.buildNumber);
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _AdminStatusTag(
                    label: _ciStatusLabel(job.status),
                    color: _ciStatusColor(job.status),
                  ),
                  Text(
                    job.branch.isEmpty ? '(브랜치 없음)' : job.branch,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    job.shortCommitSha,
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '버전 $version  ·  요청자 ${job.requestedBy.isEmpty ? '-' : job.requestedBy}',
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '생성 ${UiFormat.compactDateTime(job.createdAt)}  ·  갱신 ${UiFormat.compactDateTime(job.updatedAt)}  ·  등록 ${UiFormat.compactDateTime(job.registeredAt)}',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11,
                ),
              ),
              if (job.errorMessage.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  job.errorMessage.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              const Text(
                '상세 보기',
                style: TextStyle(
                  color: Color(0xFF2563EB),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CiJobDetailDialog extends StatefulWidget {
  final _FlutterApkCiJob job;

  const _CiJobDetailDialog({required this.job});

  @override
  State<_CiJobDetailDialog> createState() => _CiJobDetailDialogState();
}

class _CiJobDetailDialogState extends State<_CiJobDetailDialog> {
  _FlutterApkCiJob? _detail;
  String _error = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final appState = context.read<AppState>();
    if (!appState.hasAdminAccess) {
      setState(() {
        _error = '권한 없음: 관리자 권한이 필요합니다.';
        _loading = false;
      });
      return;
    }
    try {
      final result = await appState.fetchMapParsed<_FlutterApkCiJob>(
        '/api/ci/flutter-apk/jobs/${Uri.encodeComponent(widget.job.jobId)}',
        parser: (json) => _FlutterApkCiJob.fromJson(asMap(json['job'])),
        cacheTtl: Duration.zero,
      );
      if (!mounted) return;
      setState(() {
        _detail = result.data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _adminRequestError(error, 'CI 작업 상세를 불러오지 못했습니다.');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return AlertDialog(
      title: const Text('APK CI 작업 상세'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _error.isNotEmpty
                  ? _AdminInlineMessage(message: _error, isError: true)
                  : detail == null
                      ? const Text('작업 상세가 없습니다.')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _AdminStatusTag(
                                  label: _ciStatusLabel(detail.status),
                                  color: _ciStatusColor(detail.status),
                                ),
                                _AdminStatusTag(
                                  label: formatVersionDisplay(
                                    detail.versionName,
                                    detail.buildNumber,
                                  ),
                                  color: const Color(0xFF475569),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _DetailGrid(
                              items: [
                                _DetailItem(
                                    '파일',
                                    detail.fileName.isEmpty
                                        ? '-'
                                        : detail.fileName,
                                    mono: true),
                                _DetailItem(
                                    '파일 크기', _formatFileSize(detail.fileSize)),
                                _DetailItem('SHA-256',
                                    detail.sha256.isEmpty ? '-' : detail.sha256,
                                    mono: true),
                                _DetailItem(
                                    '배포 작업 ID',
                                    detail.deployTaskId.isEmpty
                                        ? '-'
                                        : detail.deployTaskId,
                                    mono: true),
                                _DetailItem(
                                    '저장소',
                                    detail.repoFullName.isEmpty
                                        ? '-'
                                        : detail.repoFullName),
                                _DetailItem('ref',
                                    detail.ref.isEmpty ? '-' : detail.ref,
                                    mono: true),
                                _DetailItem(
                                    'branch',
                                    detail.branch.isEmpty
                                        ? '-'
                                        : detail.branch),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              '다운로드 URL',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                border:
                                    Border.all(color: const Color(0xFFE2E8F0)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: SelectableText(
                                detail.downloadUrl.isEmpty
                                    ? '-'
                                    : detail.downloadUrl,
                                style: const TextStyle(
                                  color: Color(0xFF334155),
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (detail.releaseNotes.trim().isNotEmpty) ...[
                              const SizedBox(height: 12),
                              const Text(
                                '릴리즈 노트',
                                style: TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(detail.releaseNotes.trim()),
                            ],
                            if (detail.errorMessage.trim().isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _AdminInlineMessage(
                                message: detail.errorMessage.trim(),
                                isError: true,
                              ),
                            ],
                          ],
                        ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}
