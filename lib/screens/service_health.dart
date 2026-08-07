import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/api_contracts.dart';
import '../models/service_health_models.dart';
import '../state/app_state.dart';
import '../widgets/empty_state.dart';

class ServiceHealthScreen extends StatefulWidget {
  const ServiceHealthScreen({super.key});

  @override
  State<ServiceHealthScreen> createState() => _ServiceHealthScreenState();
}

class _ServiceHealthScreenState extends State<ServiceHealthScreen> {
  List<ServiceHealthSetting> _settings = const [];
  Map<String, ServiceHealthTarget> _targets = const {};
  bool _loading = true;
  String _error = '';
  String _message = '';
  String? _checkingKey;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = '';
      _message = '';
    });
    try {
      final result =
          await context.read<AppState>().fetchMapParsed<ServiceHealthSnapshot>(
                '/api/service-health',
                params: force ? const {'force': true} : null,
                parser: ServiceHealthSnapshot.fromJson,
                cacheTtl: Duration.zero,
                allowStaleOnError: false,
              );
      if (!mounted) return;
      _applySnapshot(result.data);
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _applySnapshot(ServiceHealthSnapshot snapshot) {
    _settings = snapshot.settings;
    _targets = {
      for (final target in snapshot.targets) target.key: target,
    };
  }

  void _patchSetting(String key, ServiceHealthSetting next) {
    setState(() {
      _settings = [
        for (final setting in _settings)
          if (setting.key == key) next else setting,
      ];
    });
  }

  Future<void> _check([String? key]) async {
    if (_checkingKey != null) return;
    setState(() {
      _checkingKey = key ?? 'all';
      _error = '';
      _message = '';
    });
    try {
      final data = await context.read<AppState>().postJson(
            '/api/service-health/check',
            body: key == null ? null : {'target': key},
          );
      final snapshot = ServiceHealthSnapshot.fromJson(data);
      if (!mounted) return;
      _applySnapshot(snapshot);
      setState(() {
        _message = key == null ? '전체 상태를 확인했습니다.' : '상태를 확인했습니다.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _checkingKey = null);
    }
  }

  Future<void> _save() async {
    if (_saving || !context.read<AppState>().hasAdminAccess) return;
    setState(() {
      _saving = true;
      _error = '';
      _message = '';
    });
    try {
      final data = await context.read<AppState>().postJson(
        '/api/service-health/settings',
        method: 'PUT',
        body: {
          'targets': _settings.map((setting) => setting.toJson()).toList()
        },
      );
      final rows = requireListOfMaps(data, 'settings');
      if (!mounted) return;
      setState(() {
        _settings =
            rows.map(ServiceHealthSetting.fromJson).toList(growable: false);
        _message = '상태 확인 설정을 저장했습니다.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AppState>().hasAdminAccess;
    return Scaffold(
      appBar: AppBar(
        title: const Text('외부 서버 상태',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _loading ? null : () => _load(force: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading && _settings.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _error.isNotEmpty && _settings.isEmpty
                ? EmptyState(
                    title: '상태 정보를 불러오지 못했습니다.',
                    message: _error,
                    icon: Icons.health_and_safety_outlined,
                    action: FilledButton(
                      onPressed: _load,
                      child: const Text('다시 시도'),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _load(force: true),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          '메뉴판 서버와 연결된 타임서버 상태를 확인합니다.',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: const Color(0xFF64748B),
                                  ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed:
                              _checkingKey == null ? () => _check() : null,
                          icon: const Icon(Icons.sync),
                          label: Text(_checkingKey == 'all'
                              ? '전체 확인 중...'
                              : '전체 수동 확인'),
                        ),
                        if (_error.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _MessageBox(
                              text: _error, color: const Color(0xFFB91C1C)),
                        ],
                        if (_message.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _MessageBox(
                              text: _message, color: const Color(0xFF15803D)),
                        ],
                        const SizedBox(height: 16),
                        for (final setting in _settings)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _TargetCard(
                              setting: setting,
                              target: _targets[setting.key],
                              editable: isAdmin,
                              checking: _checkingKey == setting.key,
                              onChanged: (next) =>
                                  _patchSetting(setting.key, next),
                              onCheck: () => _check(setting.key),
                            ),
                          ),
                        if (isAdmin) ...[
                          const SizedBox(height: 4),
                          OutlinedButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(_saving ? '저장 중...' : '설정 저장'),
                          ),
                        ] else
                          const Text(
                            '엔드포인트와 확인 주기 변경은 admin 권한이 필요합니다.',
                            style: TextStyle(color: Color(0xFF64748B)),
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _TargetCard extends StatelessWidget {
  final ServiceHealthSetting setting;
  final ServiceHealthTarget? target;
  final bool editable;
  final bool checking;
  final ValueChanged<ServiceHealthSetting> onChanged;
  final VoidCallback onCheck;

  const _TargetCard({
    required this.setting,
    required this.target,
    required this.editable,
    required this.checking,
    required this.onChanged,
    required this.onCheck,
  });

  Color _stateColor(String state) {
    if (state == 'Alive') return const Color(0xFF15803D);
    if (state == 'Unavailable') return const Color(0xFFB91C1C);
    return const Color(0xFF64748B);
  }

  @override
  Widget build(BuildContext context) {
    final state = target?.state ?? 'Unknown';
    final dependent = setting.componentKey != null;
    final endpoint =
        dependent ? '메뉴판 서버 /healthz의 checks.time_server' : setting.endpoint;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(setting.label,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _stateColor(state).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    state,
                    style: TextStyle(
                        color: _stateColor(state),
                        fontWeight: FontWeight.w700,
                        fontSize: 12),
                  ),
                ),
                IconButton(
                  tooltip: '상태 확인',
                  onPressed: checking ? null : onCheck,
                  icon: checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh, size: 20),
                ),
              ],
            ),
            Text(
              target?.message.isNotEmpty == true
                  ? target!.message
                  : '아직 확인하지 않았습니다.',
              style: TextStyle(color: _stateColor(state), fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text('접속 경로',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: const Color(0xFF64748B))),
            const SizedBox(height: 4),
            Text(endpoint,
                style: const TextStyle(fontSize: 12, color: Color(0xFF334155))),
            if (editable) ...[
              const SizedBox(height: 6),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(dependent ? '메뉴판 서버 상태에 종속' : '상태 확인 사용'),
                value: setting.enabled,
                onChanged: dependent
                    ? null
                    : (value) => onChanged(setting.copyWith(enabled: value)),
              ),
              if (!dependent)
                TextFormField(
                  initialValue: setting.endpoint,
                  decoration: const InputDecoration(labelText: '헬스체크 URL'),
                  keyboardType: TextInputType.url,
                  onChanged: (value) =>
                      onChanged(setting.copyWith(endpoint: value)),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: setting.timeoutMs.toString(),
                      decoration: const InputDecoration(labelText: '타임아웃 (ms)'),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        final parsed = int.tryParse(value);
                        if (parsed != null) {
                          onChanged(setting.copyWith(timeoutMs: parsed));
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: setting.intervalSeconds.toString(),
                      decoration: const InputDecoration(labelText: '주기 (초)'),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        final parsed = int.tryParse(value);
                        if (parsed != null) {
                          onChanged(setting.copyWith(intervalSeconds: parsed));
                        }
                      },
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                '마지막 확인: ${target?.lastCheckedAt ?? '-'} · 응답: ${target?.responseTimeMs == null ? '-' : '${target!.responseTimeMs!.round()} ms'}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessageBox extends StatelessWidget {
  final String text;
  final Color color;

  const _MessageBox({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      color: color.withValues(alpha: 0.08),
      child: Text(text, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}
