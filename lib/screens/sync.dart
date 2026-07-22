import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dashboard_model.dart';
import '../services/api.dart';
import '../state/app_state.dart';
import '../widgets/cache_notice.dart';
import '../widgets/empty_state.dart';
import '../widgets/panel.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  SyncRunsData? _runs;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String _error = '';
  SyncTaskStatusData? _task;
  late DateTime _targetDate;
  Timer? _pollingTimer;
  bool _fromCache = false;
  DateTime? _cachedAt;

  @override
  void initState() {
    super.initState();
    _targetDate = DateTime.now();
    _loadRuns();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRuns() async {
    final appState = context.read<AppState>();
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final response = await appState.fetchMapParsed(
        '/api/sync/runs',
        parser: SyncRunsData.fromJson,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _runs = response.data;
        _fromCache = response.fromCache;
        _cachedAt = response.cachedAt;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _targetDate = picked;
      });
    }
  }

  Future<void> _startSync() async {
    final appState = context.read<AppState>();
    setState(() {
      _isSubmitting = true;
      _error = '';
    });

    try {
      final response = await appState.postJson(
        '/api/sync',
        body: {
          'target_date': ApiService.formatDate(_targetDate),
        },
      );
      final taskId = (response['task_id'] ?? '').toString();

      if (!mounted) {
        return;
      }

      setState(() {
        _task = SyncTaskStatusData(
          taskId: taskId,
          targetDate: ApiService.formatDate(_targetDate),
          status: (response['status'] ?? '').toString(),
          errorMessage: '',
          headerCount: 0,
          itemCount: 0,
          summaryCount: 0,
          loadedCount: 0,
          startedAt: '',
          finishedAt: '',
        );
      });

      _pollingTimer?.cancel();
      _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _pollTask();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _isSubmitting = false;
      });
    }
  }

  Future<void> _pollTask() async {
    final taskId = _task?.taskId ?? '';
    if (taskId.isEmpty) {
      return;
    }

    final appState = context.read<AppState>();
    try {
      final response = await appState.fetchMapParsed(
        '/api/sync/$taskId',
        parser: SyncTaskStatusData.fromJson,
        allowStaleOnError: false,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _task = response.data;
      });
      if (_task?.isFinished == true) {
        _pollingTimer?.cancel();
        setState(() {
          _isSubmitting = false;
        });
        await _loadRuns();
      }
    } catch (error) {
      _pollingTimer?.cancel();
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty && _runs == null) {
      return EmptyState(
        title: '동기화 화면을 불러오지 못했습니다.',
        message: _error,
        action: FilledButton(
          onPressed: _loadRuns,
          child: const Text('다시 시도'),
        ),
      );
    }

    final runs = _runs?.runs ?? const <SyncRun>[];
    return RefreshIndicator(
      onRefresh: _loadRuns,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '수집 동기화',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Cafe Bridge 백엔드에서 특정 날짜의 매출을 적재합니다.',
            style: TextStyle(color: Color(0xFF64748B)),
          ),
          if (_fromCache && _cachedAt != null) ...[
            const SizedBox(height: 8),
            CacheNotice(cachedAt: _cachedAt),
          ],
          const SizedBox(height: 16),
          Panel(
            title: '동기화 실행',
            subtitle: '당일 또는 과거 영업일을 선택하세요.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(ApiService.formatDate(_targetDate)),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _isSubmitting ? null : _startSync,
                  icon: const Icon(Icons.sync),
                  label: Text(_isSubmitting ? '동기화 중...' : '동기화 시작'),
                ),
                if (_task != null) ...[
                  const SizedBox(height: 12),
                  _buildTaskStatus(_task!),
                ],
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error,
                    style: const TextStyle(
                      color: Color(0xFFDC2626),
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Panel(
            title: '최근 적재 이력',
            subtitle: '최근 15건 기준',
            child: runs.isEmpty
                ? const Text(
                    '적재 이력이 없습니다.',
                    style: TextStyle(color: Color(0xFF64748B)),
                  )
                : Column(
                    children: runs.map((run) {
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    run.targetDate,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '시작 ${UiFormat.compactDateTime(run.startedAt)} · 완료 ${UiFormat.compactDateTime(run.finishedAt)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  run.status,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: _statusColor(run.status),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${UiFormat.number(run.loadedCount)} / ${UiFormat.number(run.sourceCount)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(growable: false),
                  ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'succeeded':
        return const Color(0xFF16A34A);
      case 'failed':
        return const Color(0xFFDC2626);
      case 'running':
      case 'pending':
        return const Color(0xFFB45309);
      default:
        return const Color(0xFF64748B);
    }
  }

  Widget _buildTaskStatus(SyncTaskStatusData task) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Task ${task.taskId} · ${task.status}',
            style: TextStyle(
              color: _statusColor(task.status),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '헤더 ${UiFormat.number(task.headerCount)} · 품목 ${UiFormat.number(task.itemCount)} · 일자요약 ${UiFormat.number(task.summaryCount)} · 적재 ${UiFormat.number(task.loadedCount)}',
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 13,
            ),
          ),
          if (task.errorMessage.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              task.errorMessage,
              style: const TextStyle(
                color: Color(0xFFDC2626),
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
