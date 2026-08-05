import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/async_request_guard.dart';
import '../models/dashboard_model.dart';
import '../services/api.dart';
import '../services/task_poller.dart';
import '../state/app_state.dart';
import '../widgets/cache_notice.dart';
import '../widgets/empty_state.dart';
import '../widgets/panel.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen>
    with AsyncRequestGuard<SyncScreen> {
  static const String _activeTaskPrefix = 'active_sync_task';
  SyncRunsData? _runs;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String _error = '';
  SyncTaskStatusData? _task;
  late DateTime _targetDate;
  TaskPoller<SyncTaskStatusData>? _poller;
  int _pollGeneration = 0;
  bool _fromCache = false;
  DateTime? _cachedAt;

  @override
  void initState() {
    super.initState();
    _targetDate = ApiService.kstNow();
    _loadRuns();
    unawaited(_restoreActiveTask());
  }

  @override
  void dispose() {
    _pollGeneration += 1;
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _loadRuns() async {
    if (!mounted) return;
    final request = beginAsyncRequest();
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
      if (!isCurrentAsyncRequest(request)) {
        return;
      }
      setState(() {
        _runs = response.data;
        _error = response.data.error;
        _fromCache = response.fromCache;
        _cachedAt = response.cachedAt;
        _isLoading = false;
      });
    } catch (error) {
      if (!isCurrentAsyncRequest(request)) {
        return;
      }
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _restoreActiveTask() async {
    final appState = context.read<AppState>();
    final taskId =
        (await appState.readActiveTask(_activeTaskPrefix))?.trim() ?? '';
    if (taskId.isEmpty || !mounted) return;
    setState(() {
      _isSubmitting = true;
      _task = SyncTaskStatusData(
        taskId: taskId,
        targetDate: '',
        status: 'pending',
        errorMessage: '',
        headerCount: 0,
        itemCount: 0,
        summaryCount: 0,
        loadedCount: 0,
        startedAt: '',
        finishedAt: '',
      );
    });
    try {
      await _pollTask(taskId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isSubmitting = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate,
      firstDate: DateTime(2024),
      lastDate: ApiService.kstNow(),
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
      final payloadError = (response['error'] ?? '').toString().trim();
      if (payloadError.isNotEmpty) {
        throw StateError(payloadError);
      }
      if (taskId.isEmpty) {
        throw const FormatException('동기화 작업 ID가 없는 응답입니다.');
      }
      await appState.saveActiveTask(_activeTaskPrefix, taskId);

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

      unawaited(_pollTask(taskId));
    } catch (error) {
      if (error is ApiException && error.statusCode == 404) {
        await appState.clearActiveTask(_activeTaskPrefix);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _isSubmitting = false;
      });
    }
  }

  Future<void> _pollTask(String taskId) async {
    final appState = context.read<AppState>();
    final pollGeneration = ++_pollGeneration;
    final poller = TaskPoller<SyncTaskStatusData>(
      interval: const Duration(seconds: 2),
      timeout: const Duration(minutes: 11),
      adapter: TaskStatusAdapter<SyncTaskStatusData>(
        statusOf: (task) => task.status,
      ),
      fetch: () async {
        final response = await appState.fetchMapParsed(
          '/api/sync/$taskId',
          parser: SyncTaskStatusData.fromJson,
          cacheTtl: Duration.zero,
          allowStaleOnError: false,
        );
        if (mounted && pollGeneration == _pollGeneration) {
          setState(() {
            _task = response.data;
            if (response.data.responseError.isNotEmpty) {
              _error = response.data.responseError;
            }
          });
        }
        if (response.data.responseError.isNotEmpty) {
          throw ApiException(response.data.responseError);
        }
        return response.data;
      },
    );
    _poller?.cancel();
    _poller = poller;
    try {
      await poller.poll();
      await appState.clearActiveTask(_activeTaskPrefix);
      if (mounted) setState(() => _isSubmitting = false);
      await _loadRuns();
    } on TaskPollingFailedException<SyncTaskStatusData> catch (error) {
      await appState.clearActiveTask(_activeTaskPrefix);
      if (mounted) {
        setState(() {
          _task = error.value;
          _error = error.value.errorMessage.isNotEmpty
              ? error.value.errorMessage
              : '동기화 작업이 ${error.status} 상태로 종료되었습니다.';
          _isSubmitting = false;
        });
      }
      await _loadRuns();
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _error = '동기화 작업이 11분 이상 지연되고 있습니다. 서버 작업 이력을 확인해 주세요.';
          _isSubmitting = false;
        });
      }
    } on TaskPollingCancelledException {
      // Screen disposal or a replacement task intentionally cancels polling.
    } catch (error) {
      if (error is ApiException && error.statusCode == 404) {
        await appState.clearActiveTask(_activeTaskPrefix);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _isSubmitting = false;
      });
    } finally {
      if (identical(_poller, poller)) {
        _poller = null;
      }
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
      case 'partial_failed':
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
          if (task.overdue) ...[
            const SizedBox(height: 6),
            const Text(
              '예상 실행 시간을 초과했습니다. 현재 작업이 끝날 때까지 새 동기화를 시작할 수 없습니다.',
              style: TextStyle(
                color: Color(0xFFB45309),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
