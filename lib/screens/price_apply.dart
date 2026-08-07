import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/async_request_guard.dart';
import '../models/api_contracts.dart';
import '../models/dashboard_model.dart';
import '../services/api.dart';
import '../services/task_poller.dart';
import '../state/app_state.dart';
import '../widgets/empty_state.dart';
import '../widgets/panel.dart';
import '../widgets/responsive_wrap_grid.dart';
import '../widgets/stat_card.dart';

const List<String> _priceColumns = <String>[
  '판매가',
  '가격1',
  '가격2',
  '가격3',
  '가격4',
  '가격5',
  '가격6',
  '가격7',
  '가격8',
  '가격9',
  '가격10',
];

class PriceApplyScreen extends StatefulWidget {
  final String initialProductCode;
  final String initialItemName;
  final int? initialCurrentPrice;
  final int? initialTargetPrice;
  final bool lockProductCode;

  const PriceApplyScreen({
    super.key,
    this.initialProductCode = '',
    this.initialItemName = '',
    this.initialCurrentPrice,
    this.initialTargetPrice,
    this.lockProductCode = false,
  });

  @override
  State<PriceApplyScreen> createState() => _PriceApplyScreenState();
}

class _PriceApplyScreenState extends State<PriceApplyScreen>
    with AsyncRequestGuard<PriceApplyScreen> {
  static const String _activeTaskPrefix = 'active_price_task';
  late final TextEditingController _productCodeController;
  late final TextEditingController _targetPriceController;
  late final TextEditingController _reasonController;
  String _targetColumn = _priceColumns.first;
  bool _isSubmitting = false;
  bool _isLoadingHistory = true;
  String _error = '';
  String _historyError = '';
  BrowserPriceApplyTask? _task;
  List<BrowserPriceApplyTask> _history = const [];
  TaskPoller<BrowserPriceApplyTask>? _poller;
  int _pollGeneration = 0;
  String? _lastPreviewSignature;

  bool get _requiresMenuSelection => widget.initialProductCode.trim().isEmpty;

  @override
  void initState() {
    super.initState();
    _productCodeController =
        TextEditingController(text: widget.initialProductCode);
    _targetPriceController = TextEditingController(
      text: widget.initialTargetPrice?.toString() ?? '',
    );
    _reasonController = TextEditingController();
    if (_requiresMenuSelection) {
      _isLoadingHistory = false;
    } else {
      unawaited(_loadHistory());
      unawaited(_restoreActiveTask());
    }
  }

  @override
  void dispose() {
    _pollGeneration += 1;
    _poller?.cancel();
    _productCodeController.dispose();
    _targetPriceController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    final request = beginAsyncRequest();
    final appState = context.read<AppState>();
    setState(() {
      _isLoadingHistory = true;
      _historyError = '';
    });
    try {
      final response =
          await appState.fetchMapParsed<List<BrowserPriceApplyTask>>(
        '/api/price/browser-apply-history',
        parser: (json) => requireListOfMaps(json, 'tasks')
            .map(BrowserPriceApplyTask.fromJson)
            .toList(growable: false),
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      if (!isCurrentAsyncRequest(request)) {
        return;
      }
      setState(() {
        _history = response.data;
        _isLoadingHistory = false;
      });
    } catch (error) {
      if (!isCurrentAsyncRequest(request)) {
        return;
      }
      setState(() {
        _historyError = _formatError(error);
        _isLoadingHistory = false;
      });
    }
  }

  Future<void> _restoreActiveTask() async {
    final appState = context.read<AppState>();
    final taskId =
        (await appState.readActiveTask(_activeTaskPrefix))?.trim() ?? '';
    if (taskId.isEmpty || !mounted) return;
    setState(() => _isSubmitting = true);
    try {
      final task = await _pollTask(taskId);
      if (task.isFinished) {
        await appState.clearActiveTask(_activeTaskPrefix);
      }
      if (mounted) await _loadHistory();
    } catch (error) {
      if (mounted && error is! TaskPollingCancelledException) {
        setState(() => _error = _formatError(error));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<BrowserPriceApplyTask> _pollTask(String taskId) async {
    final appState = context.read<AppState>();
    final pollGeneration = ++_pollGeneration;
    final poller = TaskPoller<BrowserPriceApplyTask>(
      interval: const Duration(seconds: 3),
      timeout: const Duration(minutes: 6),
      adapter: TaskStatusAdapter<BrowserPriceApplyTask>(
        statusOf: (task) => task.status,
      ),
      fetch: () async {
        final response = await appState.fetchMapParsed<BrowserPriceApplyTask>(
          '/api/price/browser-apply/$taskId',
          parser: BrowserPriceApplyTask.fromJson,
          cacheTtl: Duration.zero,
          allowStaleOnError: false,
        );
        if (mounted && pollGeneration == _pollGeneration) {
          setState(() => _task = response.data);
        }
        return response.data;
      },
    );
    _poller?.cancel();
    _poller = poller;
    try {
      return await poller.poll();
    } on TimeoutException {
      throw const ApiException(
        '가격 변경 작업 응답이 지연되고 있습니다. 잠시 후 다시 확인해 주세요.',
      );
    } on TaskPollingFailedException<BrowserPriceApplyTask> catch (error) {
      return error.value;
    } finally {
      if (identical(_poller, poller)) {
        _poller = null;
      }
    }
  }

  String _requestSignature(String productCode, int targetPrice) =>
      '$productCode|$targetPrice|$_targetColumn';

  void _invalidatePreview() {
    _lastPreviewSignature = null;
  }

  Future<void> _submit({required bool execute}) async {
    final appState = context.read<AppState>();
    final productCode = _normalizedProductCode();
    if (productCode.isEmpty) {
      setState(() {
        _error = '상품코드를 입력해 주세요.';
      });
      return;
    }

    final targetPrice =
        int.tryParse(_targetPriceController.text.replaceAll(',', '').trim());
    if (targetPrice == null || targetPrice < 0) {
      setState(() {
        _error = '올바른 변경 가격을 입력해 주세요.';
      });
      return;
    }
    final signature = _requestSignature(productCode, targetPrice);
    if (execute && _lastPreviewSignature != signature) {
      setState(() {
        _error = '현재 입력값으로 미리보기를 먼저 완료해 주세요.';
      });
      return;
    }

    setState(() {
      _error = '';
      _isSubmitting = true;
      _task = null;
    });

    try {
      final response = await appState.postJson(
        '/api/price/browser-apply',
        body: {
          'product_code': productCode,
          'target_price': targetPrice,
          'target_column': _targetColumn,
          'execute': execute,
          'reason': _reasonController.text.trim().isNotEmpty
              ? _reasonController.text.trim()
              : (execute ? 'mobile-browser-apply' : 'mobile-browser-preview'),
        },
      );
      final started = AsyncTaskStartResponse.fromJson(response);
      if (started.taskId.trim().isEmpty) {
        throw const ApiException('가격 변경 작업 ID를 받지 못했습니다.');
      }
      await appState.saveActiveTask(_activeTaskPrefix, started.taskId);
      final completed = await _pollTask(started.taskId);
      if (completed.isFinished) {
        await appState.clearActiveTask(_activeTaskPrefix);
      }
      if (!execute &&
          completed.status == 'succeeded' &&
          completed.result?.status == 'preview') {
        _lastPreviewSignature = signature;
      }
      if (!mounted) {
        return;
      }
      await _loadHistory();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _formatError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  String _normalizedProductCode() {
    var value = _productCodeController.text.trim();
    if (RegExp(r'^\d+$').hasMatch(value) && value.length < 6) {
      value = value.padLeft(6, '0');
    }
    return value;
  }

  String _formatError(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 401) {
        return '로그인이 만료되었습니다. 다시 로그인해 주세요.';
      }
      if (error.statusCode == 403) {
        return '권한이 없습니다. operator 이상 계정으로 시도해 주세요.';
      }
      if (error.statusCode == 409) {
        return '이미 가격 변경 작업이 실행 중입니다. 완료 후 다시 시도하세요.';
      }
      if (error.statusCode == 422) {
        return '입력 값을 다시 확인해 주세요.';
      }
      return error.message;
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    if (_requiresMenuSelection) {
      return Scaffold(
        appBar: AppBar(
          title:
              const Text('가격', style: TextStyle(fontWeight: FontWeight.w700)),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: const Color(0xFFE2E8F0)),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Panel(
              title: '메뉴 선택 필요',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '가격 변경은 상품 화면에서 메뉴를 고른 뒤 시작할 수 있습니다.',
                    style: TextStyle(color: Color(0xFF475569)),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('상품 조회로 돌아가기'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final appState = context.watch<AppState>();
    final history = _history;
    final successfulCount = history
        .where(
          (task) =>
              task.status == 'succeeded' && task.result?.status == 'applied',
        )
        .length;
    final lastTask = _task;

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('가격 변경', style: TextStyle(fontWeight: FontWeight.w700)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE2E8F0)),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadHistory,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              const _ScreenHeader(
                eyebrow: 'Price Management',
                title: '가격 변경',
                subtitle: '최근 작업 이력',
              ),
              const SizedBox(height: 16),
              if (appState.offlineMode)
                const _InlineNotice(
                  backgroundColor: Color(0xFFECFEFF),
                  borderColor: Color(0xFF0EA5E9),
                  textColor: Color(0xFF155E75),
                  icon: Icons.cloud_off_outlined,
                  message: '오프라인 캐시 모드에서는 최신 작업 상태가 정확하지 않을 수 있습니다.',
                ),
              if (appState.offlineMode) const SizedBox(height: 12),
              ResponsiveWrapGrid(
                minItemWidth: 220,
                maxColumns: 2,
                children: [
                  StatCard(
                    label: '최근 이력',
                    value: '${history.length}건',
                    sub: '최대 20건 표시',
                    accent: true,
                  ),
                  StatCard(
                    label: '적용 완료',
                    value: '$successfulCount건',
                    sub: history.isEmpty ? '이력이 없습니다.' : '최근 작업 기준',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Panel(
                title: '가격 변경 요청',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.initialProductCode.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _InlineNotice(
                          backgroundColor: const Color(0xFFEFF6FF),
                          borderColor: const Color(0xFF3B82F6),
                          textColor: const Color(0xFF1D4ED8),
                          icon: Icons.link_outlined,
                          message: widget.initialItemName.trim().isNotEmpty
                              ? '${widget.initialItemName} 상품으로 연동되었습니다.'
                              : '다른 화면에서 선택한 상품코드로 연동되었습니다.',
                        ),
                      ),
                    TextField(
                      controller: _productCodeController,
                      readOnly: widget.lockProductCode,
                      onChanged: (_) => _invalidatePreview(),
                      decoration: const InputDecoration(
                        labelText: '상품코드 *',
                        hintText: '000144',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _targetColumn,
                      decoration: const InputDecoration(
                        labelText: '가격 컬럼',
                        border: OutlineInputBorder(),
                      ),
                      items: _priceColumns
                          .map(
                            (column) => DropdownMenuItem<String>(
                              value: column,
                              child: Text(column),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _isSubmitting
                          ? null
                          : (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _targetColumn = value;
                                _invalidatePreview();
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _targetPriceController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(_invalidatePreview),
                      decoration: InputDecoration(
                        labelText: '변경 가격 *',
                        suffixText: '원',
                        border: const OutlineInputBorder(),
                        hintText: widget.initialCurrentPrice == null
                            ? '8000'
                            : '현재 ${UiFormat.won(widget.initialCurrentPrice!)}',
                      ),
                    ),
                    if (widget.initialCurrentPrice != null ||
                        _targetPriceController.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _PriceDeltaRow(
                        currentPrice: widget.initialCurrentPrice,
                        targetPrice: int.tryParse(
                            _targetPriceController.text.replaceAll(',', '')),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _reasonController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: '변경 사유',
                        hintText: '예: 봄 메뉴 가격 조정',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
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
                    if (_isSubmitting) ...[
                      const SizedBox(height: 14),
                      const LinearProgressIndicator(minHeight: 3),
                      const SizedBox(height: 8),
                      Text(
                        lastTask?.status == 'pending'
                            ? '작업 대기 중입니다.'
                            : '가격 변경 작업을 실행 중입니다.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final preview = OutlinedButton.icon(
                          onPressed: _isSubmitting
                              ? null
                              : () => _submit(execute: false),
                          icon: const Icon(Icons.preview_outlined),
                          label: const Text('미리보기'),
                        );
                        final apply = FilledButton.icon(
                          onPressed:
                              _isSubmitting || _lastPreviewSignature == null
                                  ? null
                                  : () async {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (dialogContext) => AlertDialog(
                                          title: const Text('가격 변경 실행'),
                                          content: Text(
                                            '${widget.initialItemName.isEmpty ? productCodeLabel(_productCodeController.text) : widget.initialItemName}의 가격을 실제 POS에 반영할까요?',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(
                                                dialogContext,
                                                false,
                                              ),
                                              child: const Text('취소'),
                                            ),
                                            FilledButton(
                                              onPressed: () => Navigator.pop(
                                                dialogContext,
                                                true,
                                              ),
                                              child: const Text('실제 반영'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed == true && mounted) {
                                        await _submit(execute: true);
                                      }
                                    },
                          icon: const Icon(Icons.rocket_launch_outlined),
                          label: const Text('실제 반영'),
                        );
                        if (constraints.maxWidth < 420) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              preview,
                              const SizedBox(height: 8),
                              apply,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: preview),
                            const SizedBox(width: 8),
                            Expanded(child: apply),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              if (lastTask != null && lastTask.isFinished) ...[
                Panel(
                  title: '최근 실행 결과',
                  subtitle: '방금 실행한 작업의 상태입니다.',
                  child: _TaskResultCard(task: lastTask),
                ),
              ],
              Panel(
                title: '최근 작업 이력',
                subtitle: '웹의 browser-apply-history 이력을 동일하게 표시합니다.',
                child: _isLoadingHistory
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _historyError.isNotEmpty
                        ? EmptyState(
                            title: '최근 작업을 불러오지 못했습니다.',
                            message: _historyError,
                            action: FilledButton(
                              onPressed: _loadHistory,
                              child: const Text('다시 시도'),
                            ),
                          )
                        : history.isEmpty
                            ? const EmptyState(
                                title: '최근 작업 이력이 없습니다.',
                                message: '가격 변경을 실행하면 최근 작업이 여기에 표시됩니다.',
                              )
                            : Column(
                                children: history
                                    .map((task) => _HistoryTile(task: task))
                                    .toList(growable: false),
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String productCodeLabel(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? '선택한 상품' : '상품 $normalized';
}

class _TaskResultCard extends StatelessWidget {
  final BrowserPriceApplyTask task;

  const _TaskResultCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final result = task.result;
    final ok = task.status == 'succeeded' &&
        (result?.status == 'applied' || result?.status == 'preview');
    final preview = result?.status == 'preview';
    final message = (result?.message.isNotEmpty == true
            ? result!.message
            : task.errorMessage)
        .trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ok
            ? const Color.fromRGBO(22, 163, 74, 0.08)
            : const Color.fromRGBO(220, 38, 38, 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ok ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusBadge(status: result?.status ?? task.status),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message.isEmpty
                      ? (preview
                          ? '미리보기가 완료되었습니다. 입력값을 확인한 뒤 실제 반영하세요.'
                          : (ok ? '가격 변경이 완료되었습니다.' : '가격 변경에 실패했습니다.'))
                      : message,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _MetricChip(
                  label: '상품코드',
                  value: result?.productCode ?? task.productCode),
              _MetricChip(
                label: '현재 가격',
                value: result?.currentPrice == null
                    ? '-'
                    : UiFormat.won(result!.currentPrice!),
              ),
              _MetricChip(
                label: '변경 가격',
                value: UiFormat.won(result?.targetPrice ?? task.targetPrice),
              ),
              _MetricChip(label: '컬럼', value: task.targetColumn),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final BrowserPriceApplyTask task;

  const _HistoryTile({required this.task});

  @override
  Widget build(BuildContext context) {
    final result = task.result;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  result?.itemName.isNotEmpty == true
                      ? result!.itemName
                      : (task.productCode.isEmpty
                          ? '가격 변경 작업'
                          : task.productCode),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              _StatusBadge(status: result?.status ?? task.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '상품코드 ${result?.productCode.isNotEmpty == true ? result!.productCode : task.productCode} · ${UiFormat.won(task.targetPrice)} · ${task.targetColumn}',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF475569),
            ),
          ),
          if ((result?.message.isNotEmpty == true) ||
              task.errorMessage.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              result?.message.isNotEmpty == true
                  ? result!.message
                  : task.errorMessage,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              Text(
                '실행자 ${task.actor.isEmpty ? '-' : task.actor}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              Text(
                '사유 ${task.reason.isEmpty ? '-' : task.reason}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              Text(
                '완료 ${task.finishedAt ?? task.startedAt ?? '-'}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScreenHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;

  const _ScreenHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: const TextStyle(
              color: Color(0xFF0D9488),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF64748B),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;
  final IconData icon;
  final String message;

  const _InlineNotice({
    required this.backgroundColor,
    required this.borderColor,
    required this.textColor,
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: textColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        '$label  $value',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF334155),
        ),
      ),
    );
  }
}

class _PriceDeltaRow extends StatelessWidget {
  final int? currentPrice;
  final int? targetPrice;

  const _PriceDeltaRow({
    required this.currentPrice,
    required this.targetPrice,
  });

  @override
  Widget build(BuildContext context) {
    final delta = (currentPrice != null && targetPrice != null)
        ? targetPrice! - currentPrice!
        : null;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        if (currentPrice != null)
          Text(
            '현재 ${UiFormat.won(currentPrice!)}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
        if (targetPrice != null)
          Text(
            '→ ${UiFormat.won(targetPrice!)}',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w700,
            ),
          ),
        if (delta != null && delta != 0)
          Text(
            '(${delta > 0 ? '+' : ''}${UiFormat.number(delta)}원)',
            style: TextStyle(
              fontSize: 12,
              color:
                  delta > 0 ? const Color(0xFFDC2626) : const Color(0xFF2563EB),
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final meta = _statusMeta(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: meta.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: meta.color),
      ),
      child: Text(
        meta.label,
        style: TextStyle(
          color: meta.color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

_StatusMeta _statusMeta(String rawStatus) {
  switch (rawStatus) {
    case 'pending':
      return const _StatusMeta('대기 중', Color(0xFF94A3B8), Color(0xFFF8FAFC));
    case 'running':
      return const _StatusMeta('실행 중', Color(0xFFF59E0B), Color(0xFFFFFBEB));
    case 'succeeded':
    case 'applied':
      return const _StatusMeta('완료', Color(0xFF16A34A), Color(0xFFF0FDF4));
    case 'preview':
      return const _StatusMeta('미리보기', Color(0xFF2563EB), Color(0xFFEFF6FF));
    case 'failed':
    default:
      return const _StatusMeta('실패', Color(0xFFDC2626), Color(0xFFFEF2F2));
  }
}

class _StatusMeta {
  final String label;
  final Color color;
  final Color background;

  const _StatusMeta(this.label, this.color, this.background);
}
