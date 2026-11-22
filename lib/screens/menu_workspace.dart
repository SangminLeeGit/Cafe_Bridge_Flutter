import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/async_request_guard.dart';
import '../models/api_contracts.dart';
import '../models/editor_context.dart';
import '../models/menu_workspace_models.dart';
import '../models/product_identity.dart';
import '../services/api.dart';
import '../services/task_poller.dart';
import '../state/app_state.dart';
import '../widgets/access_gate.dart';
import '../widgets/cache_notice.dart';
import '../widgets/empty_state.dart';
import '../widgets/panel.dart';
import '../widgets/stat_card.dart';

// ─── Models for product browser ──────────────────────────────────────────────

class _ProductRow {
  final Map<String, dynamic> raw;
  final String itemCode;
  final String itemName;
  final int? salePrice;
  final String category;

  const _ProductRow({
    required this.raw,
    required this.itemCode,
    required this.itemName,
    this.salePrice,
    this.category = '',
  });

  factory _ProductRow.fromRegistration(Map<String, dynamic> json) {
    final identity = ProductIdentity.fromRegistrationJson(
      json,
      priceFields: const ['판매가', 'target_price', 'sale_price'],
    );
    return _ProductRow(
      raw: Map<String, dynamic>.from(json),
      itemCode: identity.code,
      itemName: identity.name,
      salePrice: identity.salePrice,
      category: identity.category,
    );
  }

  bool get isLikelyOption => itemName.trim().startsWith('-->');
}

const _lookupDetailFields = <({String label, String key, bool money})>[
  (label: '원가', key: '원가', money: true),
  (label: '공급가', key: '공급가', money: true),
  (label: '단위명칭', key: '단위명칭', money: false),
  (label: '과세유무', key: '과세유무', money: false),
  (label: '부가세', key: '부가세', money: false),
  (label: '사용구분', key: '사용구분', money: false),
  (label: '재고관리', key: '재고관리여부', money: false),
  (label: '통제구분', key: '통제구분', money: false),
  (label: '가격구분', key: '가격구분', money: false),
  (label: '상품구분', key: '상품구분자', money: false),
  (label: '영문명', key: '상품영문명칭', money: false),
  (label: '바코드', key: '바코드', money: false),
];

String _lookupValue(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? '-' : trimmed;
}

String _lookupMoney(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return '-';
  final parsed = int.tryParse(trimmed.replaceAll(',', ''));
  return parsed == null ? trimmed : _won(parsed);
}

String _freshnessLabel(String? syncedAt) {
  final value = syncedAt?.trim() ?? '';
  if (value.isEmpty) return '동기화 시각 정보 없음';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return '동기화 $value';
  final diff = DateTime.now().difference(parsed);
  if (diff.isNegative) return '동기화 $value';
  final mins = diff.inMinutes;
  if (mins < 1) return '방금 동기화';
  if (mins < 60) return '$mins분 전 동기화';
  final hours = diff.inHours;
  return '$hours시간 전 동기화';
}

String _statusLabel(String status) {
  switch (status) {
    case 'ready':
      return '준비완료';
    case 'reviewed':
      return '검토완료';
    case 'done':
      return '반영완료';
    case 'archived':
      return '보관';
    default:
      return '초안';
  }
}

bool _hasUncertainWorkspaceWriteOutcome(Object error) =>
    error is ApiException &&
    (error.isTransportError ||
        error.statusCode == 408 ||
        (error.statusCode != null && error.statusCode! >= 500));

bool _isWorkspaceWriteConflict(Object error) =>
    error is ApiException &&
    (error.statusCode == 409 ||
        error.code == 'revision_conflict' ||
        error.message.contains(
          '워크스페이스 항목이 다른 요청에 의해 변경되었습니다',
        ));

Color _statusColor(String status) {
  switch (status) {
    case 'ready':
      return const Color(0xFF0D9488);
    case 'reviewed':
      return const Color(0xFF2563EB);
    case 'done':
      return const Color(0xFF16A34A);
    case 'archived':
      return const Color(0xFF64748B);
    default:
      return const Color(0xFF94A3B8);
  }
}

// ─── Main screen ─────────────────────────────────────────────────────────────

class MenuWorkspaceScreen extends StatefulWidget {
  const MenuWorkspaceScreen({super.key});

  @override
  State<MenuWorkspaceScreen> createState() => _MenuWorkspaceScreenState();
}

class _MenuWorkspaceScreenState extends State<MenuWorkspaceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _workspaceRefreshTick = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _workspaceRefreshTick.dispose();
    super.dispose();
  }

  void _onPriceChangeRegistered() {
    _workspaceRefreshTick.value++;
    _tabController.animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
    return AccessGate(
      minimumRole: UserRole.admin,
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: '메뉴 선택'),
              Tab(text: '작업 목록'),
            ],
            labelColor: const Color(0xFF0D9488),
            unselectedLabelColor: const Color(0xFF64748B),
            indicatorColor: const Color(0xFF0D9488),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _ProductBrowserTab(
                  onPriceChangeRegistered: _onPriceChangeRegistered,
                  onNewItemRegistered: _onPriceChangeRegistered,
                ),
                _WorkspaceTab(
                  refreshNotifier: _workspaceRefreshTick,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tab 1: Workspace entries ─────────────────────────────────────────────────

class _WorkspaceTab extends StatefulWidget {
  final ValueNotifier<int>? refreshNotifier;
  const _WorkspaceTab({this.refreshNotifier});

  @override
  State<_WorkspaceTab> createState() => _WorkspaceTabState();
}

class _WorkspaceTabState extends State<_WorkspaceTab>
    with AutomaticKeepAliveClientMixin {
  WorkspaceSnapshot? _snapshot;
  bool _isLoading = true;
  String _error = '';
  bool _fromCache = false;
  DateTime? _cachedAt;
  NewItemValidationResponse? _validation;
  bool _validationLoading = true;
  String _validationError = '';
  List<PriceApplyRun> _priceApplyRuns = const [];
  bool _priceApplyRunsLoading = true;
  String _priceApplyRunsError = '';
  List<WorkspaceTaskHistoryEntry> _newItemHistory = const [];
  bool _newItemHistoryLoading = true;
  String _newItemHistoryError = '';
  List<WorkspaceTaskHistoryEntry> _deleteItemHistory = const [];
  bool _deleteItemHistoryLoading = true;
  String _deleteItemHistoryError = '';
  List<WorkspaceTaskHistoryEntry> _browserPriceHistory = const [];
  bool _browserPriceHistoryLoading = true;
  String _browserPriceHistoryError = '';
  String _filterStatus = 'all';
  String _filterKind = 'all';
  String _searchQuery = '';
  bool _loadAllInFlight = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.refreshNotifier?.addListener(_onRefreshRequest);
    unawaited(_loadAll());
  }

  @override
  void dispose() {
    widget.refreshNotifier?.removeListener(_onRefreshRequest);
    super.dispose();
  }

  void _onRefreshRequest() {
    if (mounted && !_isLoading) unawaited(_loadAll(force: true));
  }

  Future<void> _loadSnapshot({bool force = false}) async {
    final appState = context.read<AppState>();
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final response = await appState.fetchMapParsed(
        '/api/menu-workspace',
        parser: WorkspaceSnapshot.fromJson,
        cacheTtl: force ? Duration.zero : const Duration(minutes: 5),
      );
      if (!mounted) return;
      setState(() {
        _snapshot = response.data;
        _fromCache = response.fromCache;
        _cachedAt = response.cachedAt;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadValidation({bool force = false}) async {
    final appState = context.read<AppState>();
    setState(() {
      _validationLoading = true;
      _validationError = '';
    });
    try {
      final response = await appState.fetchMapParsed(
        '/api/menu-workspace/new-item-validate',
        parser: NewItemValidationResponse.fromJson,
        cacheTtl: force ? Duration.zero : const Duration(minutes: 5),
      );
      if (!mounted) return;
      setState(() {
        _validation = response.data;
        _validationLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _validation = null;
        _validationError = error.toString();
        _validationLoading = false;
      });
    }
  }

  Future<void> _loadPriceApplyRuns({bool force = false}) async {
    final appState = context.read<AppState>();
    setState(() {
      _priceApplyRunsLoading = true;
      _priceApplyRunsError = '';
    });
    try {
      final response = await appState.fetchMapParsed<Map<String, dynamic>>(
        '/api/menu-workspace/price-apply-runs',
        parser: (json) {
          final raw = json;
          return {
            'runs': (raw['runs'] as List? ?? [])
                .whereType<Map>()
                .map((item) =>
                    PriceApplyRun.fromJson(Map<String, dynamic>.from(item)))
                .toList(growable: false),
          };
        },
        cacheTtl: force ? Duration.zero : const Duration(minutes: 5),
      );
      if (!mounted) return;
      setState(() {
        _priceApplyRuns = List<PriceApplyRun>.from(
            response.data['runs'] as List? ?? const []);
        _priceApplyRunsLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _priceApplyRuns = const [];
        _priceApplyRunsError = error.toString();
        _priceApplyRunsLoading = false;
      });
    }
  }

  Future<void> _loadNewItemHistory({bool force = false}) async {
    final appState = context.read<AppState>();
    setState(() {
      _newItemHistoryLoading = true;
      _newItemHistoryError = '';
    });
    try {
      final response = await appState.fetchMapParsed<Map<String, dynamic>>(
        '/api/menu-workspace/new-item-apply-history',
        parser: (json) {
          final raw = json;
          return {
            'tasks': (raw['tasks'] as List? ?? [])
                .whereType<Map>()
                .map((item) => WorkspaceTaskHistoryEntry.fromJson(
                    Map<String, dynamic>.from(item)))
                .toList(growable: false),
          };
        },
        cacheTtl: force ? Duration.zero : const Duration(minutes: 5),
      );
      if (!mounted) return;
      setState(() {
        _newItemHistory = List<WorkspaceTaskHistoryEntry>.from(
            response.data['tasks'] as List? ?? const []);
        _newItemHistoryLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _newItemHistory = const [];
        _newItemHistoryError = error.toString();
        _newItemHistoryLoading = false;
      });
    }
  }

  Future<void> _loadBrowserPriceHistory({bool force = false}) async {
    final appState = context.read<AppState>();
    setState(() {
      _browserPriceHistoryLoading = true;
      _browserPriceHistoryError = '';
    });
    try {
      final response = await appState.fetchMapParsed<Map<String, dynamic>>(
        '/api/price/browser-apply-history',
        parser: (json) {
          final raw = json;
          return {
            'tasks': (raw['tasks'] as List? ?? [])
                .whereType<Map>()
                .map((item) => WorkspaceTaskHistoryEntry.fromJson(
                    Map<String, dynamic>.from(item)))
                .toList(growable: false),
          };
        },
        cacheTtl: force ? Duration.zero : const Duration(minutes: 5),
      );
      if (!mounted) return;
      setState(() {
        _browserPriceHistory = List<WorkspaceTaskHistoryEntry>.from(
            response.data['tasks'] as List? ?? const []);
        _browserPriceHistoryLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _browserPriceHistory = const [];
        _browserPriceHistoryError = error.toString();
        _browserPriceHistoryLoading = false;
      });
    }
  }

  Future<void> _loadDeleteItemHistory({bool force = false}) async {
    final appState = context.read<AppState>();
    setState(() {
      _deleteItemHistoryLoading = true;
      _deleteItemHistoryError = '';
    });
    try {
      final response = await appState.fetchMapParsed<Map<String, dynamic>>(
        '/api/menu-workspace/item-delete-history',
        parser: (json) {
          final raw = json;
          return {
            'tasks': (raw['tasks'] as List? ?? [])
                .whereType<Map>()
                .map((item) => WorkspaceTaskHistoryEntry.fromJson(
                    Map<String, dynamic>.from(item)))
                .toList(growable: false),
          };
        },
        cacheTtl: force ? Duration.zero : const Duration(minutes: 5),
      );
      if (!mounted) return;
      setState(() {
        _deleteItemHistory = List<WorkspaceTaskHistoryEntry>.from(
            response.data['tasks'] as List? ?? const []);
        _deleteItemHistoryLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _deleteItemHistory = const [];
        _deleteItemHistoryError = error.toString();
        _deleteItemHistoryLoading = false;
      });
    }
  }

  Future<void> _loadAll({bool force = false}) async {
    if (_loadAllInFlight) return;
    _loadAllInFlight = true;
    try {
      await Future.wait([
        _loadSnapshot(force: force),
        _loadValidation(force: force),
        _loadPriceApplyRuns(force: force),
        _loadNewItemHistory(force: force),
        _loadDeleteItemHistory(force: force),
        _loadBrowserPriceHistory(force: force),
      ]);
    } finally {
      _loadAllInFlight = false;
    }
  }

  List<MenuEntry> get _filteredEntries {
    var entries = _snapshot?.entries ?? const <MenuEntry>[];
    if (_filterStatus != 'all') {
      entries = entries.where((e) => e.status == _filterStatus).toList();
    }
    if (_filterKind != 'all') {
      entries = entries.where((e) => e.kind == _filterKind).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      entries = entries
          .where((e) =>
              e.itemName.toLowerCase().contains(q) ||
              e.itemCode.toLowerCase().contains(q))
          .toList();
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading && _snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return EmptyState(
        title: '메뉴 작업대를 불러오지 못했습니다.',
        message: _error,
        action: FilledButton(
            onPressed: () => _loadSnapshot(force: true),
            child: const Text('다시 시도')),
      );
    }

    final snapshot = _snapshot;
    if (snapshot == null) {
      return EmptyState(
        title: '데이터 없음',
        action: FilledButton(
            onPressed: () => _loadAll(force: true), child: const Text('새로고침')),
      );
    }

    final entries = _filteredEntries;
    final s = snapshot.summary;
    final appState = context.watch<AppState>();
    final hasReady = (snapshot.statusCounts['ready'] ?? 0) > 0;
    final newItemIssues = {
      for (final issue
          in _validation?.issues ?? const <NewItemValidationIssue>[])
        issue.entryId: issue.messages,
    };

    return RefreshIndicator(
      onRefresh: () => _loadAll(force: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_fromCache && _cachedAt != null) ...[
                    CacheNotice(cachedAt: _cachedAt),
                    const SizedBox(height: 12),
                  ],
                  _MetricGrid(
                    cards: [
                      StatCard(
                          label: '전체 항목',
                          value: '${s.totalEntries}개',
                          accent: true),
                      StatCard(label: '적용 준비', value: '${s.readyCount}개'),
                      StatCard(label: '신규 등록', value: '${s.newItemCount}개'),
                      StatCard(
                          label: '가격 변동', value: _wonSigned(s.priceDeltaTotal)),
                    ],
                  ),
                  if (hasReady && appState.hasOperatorAccess) ...[
                    const SizedBox(height: 12),
                    const _ApplyReadyBanner(),
                  ],
                  const SizedBox(height: 16),
                  _FilterBar(
                    filterStatus: _filterStatus,
                    filterKind: _filterKind,
                    onStatusChanged: (v) => setState(() => _filterStatus = v),
                    onKindChanged: (v) => setState(() => _filterKind = v),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: '품목명 또는 코드 검색',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                  const SizedBox(height: 12),
                  _WorkspaceInfoStrip(
                    title: '신규 메뉴 검증',
                    loading: _validationLoading,
                    error: _validationError,
                    summary: _validation == null
                        ? '검증 정보 없음'
                        : '전체 ${_validation!.entryCount}건 · 통과 ${_validation!.validCount}건 · 이슈 ${_validation!.issueCount}건',
                    trailing: TextButton.icon(
                      onPressed: _validationLoading
                          ? null
                          : () => _loadValidation(force: true),
                      icon: const Icon(Icons.verified_outlined, size: 16),
                      label: Text(_validationLoading ? '검증 중...' : '새로고침'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: const Color(0xFF0D9488),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Panel(
                    title: '작업 이력',
                    subtitle: '가격 적용과 신규 메뉴 반영의 최근 결과를 확인합니다.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TaskHistoryHeader(
                          label: '가격 적용',
                          loading: _priceApplyRunsLoading,
                          error: _priceApplyRunsError,
                          count: _priceApplyRuns.length,
                          onRefresh: () => _loadPriceApplyRuns(force: true),
                        ),
                        const SizedBox(height: 8),
                        if (_priceApplyRuns.isNotEmpty)
                          ..._priceApplyRuns
                              .take(3)
                              .map((run) => _PriceApplyRunTile(run: run))
                        else if (!_priceApplyRunsLoading &&
                            _priceApplyRunsError.isEmpty)
                          const Text(
                            '최근 가격 적용 이력이 없습니다.',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        const SizedBox(height: 12),
                        _TaskHistoryHeader(
                          label: '신규 메뉴',
                          loading: _newItemHistoryLoading,
                          error: _newItemHistoryError,
                          count: _newItemHistory.length,
                          onRefresh: () => _loadNewItemHistory(force: true),
                        ),
                        const SizedBox(height: 8),
                        if (_newItemHistory.isNotEmpty)
                          ..._newItemHistory
                              .take(3)
                              .map((task) => _TaskHistoryTile(task: task))
                        else if (!_newItemHistoryLoading &&
                            _newItemHistoryError.isEmpty)
                          const Text(
                            '최근 신규 메뉴 작업 이력이 없습니다.',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        const SizedBox(height: 12),
                        _TaskHistoryHeader(
                          label: '신규 메뉴 삭제',
                          loading: _deleteItemHistoryLoading,
                          error: _deleteItemHistoryError,
                          count: _deleteItemHistory.length,
                          onRefresh: () => _loadDeleteItemHistory(force: true),
                        ),
                        const SizedBox(height: 8),
                        if (_deleteItemHistory.isNotEmpty)
                          ..._deleteItemHistory
                              .take(3)
                              .map((task) => _TaskHistoryTile(task: task))
                        else if (!_deleteItemHistoryLoading &&
                            _deleteItemHistoryError.isEmpty)
                          const Text(
                            '최근 신규 메뉴 삭제 이력이 없습니다.',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        const SizedBox(height: 12),
                        _TaskHistoryHeader(
                          label: '브라우저 가격 변경',
                          loading: _browserPriceHistoryLoading,
                          error: _browserPriceHistoryError,
                          count: _browserPriceHistory.length,
                          onRefresh: () =>
                              _loadBrowserPriceHistory(force: true),
                        ),
                        const SizedBox(height: 8),
                        if (_browserPriceHistory.isNotEmpty)
                          ..._browserPriceHistory
                              .take(3)
                              .map((task) => _TaskHistoryTile(task: task))
                        else if (!_browserPriceHistoryLoading &&
                            _browserPriceHistoryError.isEmpty)
                          const Text(
                            '최근 브라우저 가격 변경 이력이 없습니다.',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF64748B)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          if (entries.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Text(
                  '조건에 맞는 항목이 없습니다.',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverList.separated(
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  return _MenuEntryCard(
                    entry: entries[index],
                    issues: newItemIssues[entries[index].id] ?? const [],
                    onTap: () => _showEntryDetail(context, entries[index]),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  void _showEntryDetail(BuildContext context, MenuEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccessGate(
          minimumRole: UserRole.admin,
          fullScreen: true,
          child: MenuEntryDetailScreen(
            entry: entry,
            onUpdated: () => _loadAll(force: true),
          ),
        ),
      ),
    );
  }
}

// ─── Tab 2: Product Browser ───────────────────────────────────────────────────

class _ProductBrowserTab extends StatefulWidget {
  final VoidCallback? onPriceChangeRegistered;
  final VoidCallback? onNewItemRegistered;
  const _ProductBrowserTab({
    this.onPriceChangeRegistered,
    this.onNewItemRegistered,
  });

  @override
  State<_ProductBrowserTab> createState() => _ProductBrowserTabState();
}

class _ProductBrowserTabState extends State<_ProductBrowserTab>
    with AutomaticKeepAliveClientMixin, AsyncRequestGuard<_ProductBrowserTab> {
  List<_ProductRow> _products = [];
  bool _isLoading = true;
  String _loadError = '';
  bool _hasSearched = false;
  String _source = '';
  String _syncedAt = '';

  final _searchController = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts({
    required String query,
    required bool refresh,
  }) async {
    if (!mounted) return;
    final request = beginAsyncRequest();
    final appState = context.read<AppState>();
    final trimmedQuery = query.trim();
    setState(() {
      _isLoading = true;
      _loadError = '';
      _hasSearched = trimmedQuery.isNotEmpty;
    });
    try {
      final result = await appState.fetchMapParsed<Map<String, dynamic>>(
        '/api/menu-workspace/product-registration',
        params: {
          'query': trimmedQuery,
          'refresh': refresh ? 'true' : 'false',
          'cache_only': refresh ? 'false' : 'true',
        },
        parser: (j) => j,
        cacheTtl: refresh ? Duration.zero : const Duration(minutes: 10),
      );
      if (!isCurrentAsyncRequest(request)) return;
      final rows = (result.data['rows'] as List? ?? [])
          .map((e) => _ProductRow.fromRegistration(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _products = rows;
        _source = (result.data['source'] ?? '').toString();
        _syncedAt = (result.data['synced_at'] ?? '').toString();
        _isLoading = false;
      });
    } catch (e) {
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _loadError = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAll({bool refresh = false}) async {
    await _loadProducts(query: '', refresh: refresh);
  }

  Future<void> _search(String query, {bool refresh = false}) async {
    final q = query.trim();
    if (q.isEmpty) {
      _searchController.clear();
      await _loadAll(refresh: refresh);
      return;
    }
    await _loadProducts(query: q, refresh: refresh);
  }

  Future<void> _refreshCurrent() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      await _loadAll(refresh: true);
      return;
    }
    await _search(query, refresh: true);
  }

  void _openPriceChangeSheet(_ProductRow product) {
    final appState = context.read<AppState>();
    if (!appState.hasOperatorAccess) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccessGate(
          minimumRole: UserRole.admin,
          fullScreen: true,
          child: _QuickPriceChangeSheet(
            product: product,
            appState: appState,
            onDirectApplied: () async {
              await _refreshCurrent();
              widget.onPriceChangeRegistered?.call();
            },
          ),
        ),
      ),
    );
  }

  void _openProductDetailScreen(_ProductRow product) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccessGate(
          minimumRole: UserRole.admin,
          fullScreen: true,
          child: _ProductRegistrationDetailScreen(
            product: product,
            appState: context.read<AppState>(),
            onQuickPriceChange: _openPriceChangeSheet,
          ),
        ),
      ),
    );
  }

  void _openNewItemScreen() {
    final appState = context.read<AppState>();
    if (!appState.hasOperatorAccess) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccessGate(
          minimumRole: UserRole.admin,
          fullScreen: true,
          child: _NewMenuAddScreen(
            appState: appState,
            onSubmitted: () {
              widget.onNewItemRegistered?.call();
              unawaited(_refreshCurrent());
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final appState = context.watch<AppState>();
    final isOperator = appState.hasOperatorAccess;
    final list = _products;
    final isLoading = _isLoading;
    final error = _loadError;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'POS 상품명 또는 코드 검색',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      tooltip: '검색어 지우기',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _loadAll();
                      },
                    )
                  : null,
              isDense: true,
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: _search,
            onChanged: (v) {
              setState(() {});
              if (v.isEmpty) _loadAll();
            },
          ),
        ),
        if (_source.isNotEmpty || _syncedAt.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _WorkspaceInfoStrip(
              title: '상품등록 조회',
              loading: false,
              error: '',
              summary:
                  '${_source.toUpperCase()} · ${_freshnessLabel(_syncedAt)}',
              trailing: IconButton(
                tooltip: '상품등록 새로고침',
                onPressed: _refreshCurrent,
                icon: const Icon(Icons.refresh, size: 18),
                visualDensity: VisualDensity.compact,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compactLayout = constraints.maxWidth < 520;
              final summaryText = Text(
                _hasSearched
                    ? 'POS 상품 검색 결과 (${_products.length}건)'
                    : '전체 메뉴 (${_products.length}건)',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Color(0xFF64748B),
                ),
              );
              final actionButtons = Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: [
                  if (isOperator)
                    FilledButton.icon(
                      onPressed: _openNewItemScreen,
                      icon: const Icon(Icons.add, size: 17),
                      label: const Text('새 메뉴 등록'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0D9488),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _refreshCurrent,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('새로고침', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF64748B),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              );

              if (compactLayout) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    summaryText,
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: actionButtons,
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: summaryText),
                  const SizedBox(width: 12),
                  actionButtons,
                ],
              );
            },
          ),
        ),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : error.isNotEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(error,
                            style: const TextStyle(color: Color(0xFFDC2626))),
                      ),
                    )
                  : list.isEmpty
                      ? Center(
                          child: Text(
                            _hasSearched ? '검색 결과가 없습니다.' : '상품 목록이 없습니다.',
                            style: const TextStyle(color: Color(0xFF64748B)),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: list.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (_, i) => _ProductCard(
                            product: list[i],
                            onTap: isOperator
                                ? () => _openPriceChangeSheet(list[i])
                                : null,
                            onInfoTap: () => _openProductDetailScreen(list[i]),
                          ),
                        ),
        ),
        if (!isOperator)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFFFFF7ED),
            child: const Text(
              'operator 이상 권한이 있어야 가격 변경과 등록 초안 작성을 실행할 수 있습니다.',
              style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
            ),
          ),
      ],
    );
  }
}

class _NewMenuAddScreen extends StatefulWidget {
  final AppState appState;
  final MenuEntry? existingEntry;
  final VoidCallback? onSubmitted;

  const _NewMenuAddScreen({
    required this.appState,
    this.existingEntry,
    this.onSubmitted,
  });

  @override
  State<_NewMenuAddScreen> createState() => _NewMenuAddScreenState();
}

class _NewMenuAddScreenState extends State<_NewMenuAddScreen> {
  final _itemNameController = TextEditingController();
  final _targetPriceController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _supplyPriceController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _notesController = TextEditingController();

  WorkspaceFormOptions? _formOptions;
  MenuEntry? _existingEntry;
  MenuEntry? _savedEntry;
  Map<String, dynamic>? _preparedPlan;
  Map<String, dynamic>? _pendingCreateBody;
  Map<String, dynamic>? _pendingUpdateBody;
  Set<int> _preCreateEntryIds = const {};
  List<MenuEntry> _reconcileMatches = const [];
  MenuEntry? _latestEntry;
  String _reconcileMessage = '';
  String _majorCategory = '';
  String _middleCategory = '';
  String _minorCategory = '';
  String _unitName = 'EA';
  String _taxMode = '과세';
  String _useMode = '사용';
  String _stockMode = 'N';
  int _step = 1;
  int _noMatchReconcileChecks = 0;
  bool _optionsLoading = true;
  bool _isSaving = false;
  bool _isPreparing = false;
  bool _isReconciling = false;
  bool _createOutcomeUnknown = false;
  bool _updateOutcomeUnknown = false;
  bool _retryCreateAllowed = false;
  bool _retryUpdateAllowed = false;
  bool _serverConflict = false;
  bool _formDirty = false;
  bool _leavePromptOpen = false;
  String _error = '';

  @override
  void dispose() {
    _itemNameController.dispose();
    _targetPriceController.dispose();
    _costPriceController.dispose();
    _supplyPriceController.dispose();
    _barcodeController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _existingEntry = widget.existingEntry;
    final entry = widget.existingEntry;
    if (entry != null) {
      _itemNameController.text = entry.itemName;
      _targetPriceController.text = entry.targetPrice?.toString() ?? '';
      _costPriceController.text = entry.costPrice?.toString() ?? '';
      _supplyPriceController.text = entry.supplyPrice?.toString() ?? '';
      _barcodeController.text = entry.barcode;
      _descriptionController.text = entry.description;
      _notesController.text = entry.notes;
      _majorCategory = entry.majorCategory;
      _middleCategory = entry.middleCategory;
      _minorCategory = entry.minorCategory;
      _unitName = entry.unitName;
      _taxMode = entry.taxMode;
      _useMode = entry.useMode;
      _stockMode = entry.stockMode;
    }
    unawaited(_loadFormOptions());
  }

  bool get _isEditing => _existingEntry != null;
  bool get _existingEntryLocked =>
      _existingEntry?.isSubmissionReserved == true ||
      const {'ready', 'done', 'reserved', 'stale'}
          .contains(_existingEntry?.status);

  int? _parseNonNegativeInt(String raw, {required String fieldName}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final parsed = int.tryParse(trimmed.replaceAll(',', ''));
    if (parsed == null) {
      throw ApiException('$fieldName 값을 숫자로 입력하세요.');
    }
    if (parsed < 0) {
      throw ApiException('$fieldName 값은 0 이상이어야 합니다.');
    }
    return parsed;
  }

  Future<WorkspaceFormOptions> _fetchFormOptions() async {
    final response = await widget.appState.fetchMapParsed<WorkspaceFormOptions>(
      '/api/menu-workspace/form-options',
      parser: WorkspaceFormOptions.fromJson,
      cacheTtl: Duration.zero,
      allowStaleOnError: false,
    );
    return response.data;
  }

  Future<void> _loadFormOptions() async {
    if (mounted) {
      setState(() {
        _optionsLoading = true;
        _error = '';
      });
    }
    try {
      final options = await _fetchFormOptions();
      if (!mounted) return;
      setState(() {
        _formOptions = options;
        if (_existingEntry == null) {
          _majorCategory = options.profileDefault('major_category');
          _middleCategory = options.profileDefault('middle_category');
          _minorCategory = options.profileDefault('minor_category');
          _unitName = options.profileDefault('unit_name', fallback: 'EA');
          _taxMode = options.profileDefault('tax_mode', fallback: '과세');
          _useMode = options.profileDefault('use_mode', fallback: '사용');
          _stockMode = options.profileDefault('stock_mode', fallback: 'N');
        }
        _optionsLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _optionsLoading = false;
        _error = '분류와 등록 기본값을 불러오지 못했습니다. 다시 새로고침해 주세요. $error';
      });
    }
  }

  List<String> get _middleCategoryOptions {
    if (_majorCategory.trim().isEmpty) return const [];
    return _formOptions?.categoryOptions.middleOptions(_majorCategory.trim()) ??
        const [];
  }

  List<String> get _minorCategoryOptions {
    final major = _majorCategory.trim();
    final middle = _middleCategory.trim();
    if (major.isEmpty || middle.isEmpty) return const [];
    return _formOptions?.categoryOptions.minorOptions(major, middle) ??
        const [];
  }

  void _onMajorCategoryChanged(String? value) {
    _majorCategory = (value ?? '').trim();
    _middleCategory = '';
    _minorCategory = '';
  }

  void _onMiddleCategoryChanged(String? value) {
    _middleCategory = (value ?? '').trim();
    _minorCategory = '';
  }

  void _markFormChanged() {
    _formDirty = true;
    _preparedPlan = null;
    _savedEntry = null;
    _error = '';
  }

  Map<String, dynamic> _buildDraftFields() {
    final options = _formOptions;
    if (options == null || _optionsLoading) {
      throw const ApiException('등록 정보를 불러오는 중입니다. 잠시 후 다시 시도하세요.');
    }
    final itemName = _itemNameController.text.trim();
    final majorCategory = _majorCategory.trim();
    final middleCategory = _middleCategory.trim();
    final minorCategory = _minorCategory.trim();
    final barcode = _barcodeController.text.trim();
    final description = _descriptionController.text.trim();
    final notes = _notesController.text.trim();
    final targetPrice = _parseNonNegativeInt(
      _targetPriceController.text,
      fieldName: '판매가',
    );
    final costPrice = _parseNonNegativeInt(
      _costPriceController.text,
      fieldName: '원가',
    );
    final supplyPrice = _parseNonNegativeInt(
      _supplyPriceController.text,
      fieldName: '공급가',
    );

    if (itemName.isEmpty) {
      throw const ApiException('상품명을 입력하세요.');
    }
    if (targetPrice == null) {
      throw const ApiException('판매가를 입력하세요.');
    }
    if (!options.categoryOptions.containsPath(
      majorCategory,
      middleCategory,
      minorCategory,
    )) {
      throw const ApiException(
        '현재 EasyPOS 분류 목록에서 대·중·소 분류를 선택하세요. 분류 목록이 준비되지 않았다면 새로고침해 주세요.',
      );
    }
    final fields = buildNewItemDraftRequestBody(
      itemName: itemName,
      targetPrice: targetPrice,
      majorCategory: majorCategory,
      middleCategory: middleCategory,
      minorCategory: minorCategory,
      unitName: _unitName,
      taxMode: _taxMode,
      useMode: _useMode,
      stockMode: _stockMode,
      barcode: barcode,
      description: description,
      notes: notes,
      costPrice: costPrice,
      supplyPrice: supplyPrice,
    );
    // The PATCH request excludes nulls on the server. Blank cost/supply inputs
    // therefore mean "leave unchanged" while editing, not "clear this value".
    return fields;
  }

  MenuEntry _parseSavedEntry(
    Map<String, dynamic> json, {
    int? expectedId,
  }) {
    final entry = MenuEntry.fromJson(json);
    if (entry.id <= 0 ||
        entry.kind != 'new_item' ||
        (expectedId != null && entry.id != expectedId)) {
      throw const FormatException('서버의 등록 초안 응답을 확인할 수 없습니다.');
    }
    return entry;
  }

  Future<WorkspaceSnapshot> _fetchWorkspaceSnapshot() async {
    final response = await widget.appState.fetchMapParsed<WorkspaceSnapshot>(
      '/api/menu-workspace',
      parser: WorkspaceSnapshot.fromJson,
      cacheTtl: Duration.zero,
      allowStaleOnError: false,
    );
    return response.data;
  }

  Future<void> _continueToReview() async {
    try {
      final body = _buildDraftFields();
      setState(() {
        _reviewFields = body;
        _step = 2;
        _error = '';
      });
    } catch (error) {
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Map<String, dynamic> _reviewFields = const {};

  Future<bool> _confirmSave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_isEditing ? '등록 초안 수정' : '등록 초안 저장'),
        content: const Text(
          '메뉴 정보를 CafeBridge 작업대에 저장합니다. 이 작업은 POS에 상품·가격·터치키 정보를 반영하지 않습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('돌아가기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('초안 저장'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _saveDraft({bool alreadyConfirmed = false}) async {
    if (_isSaving || _createOutcomeUnknown || _updateOutcomeUnknown) return;
    if (!alreadyConfirmed && !await _confirmSave()) return;
    Map<String, dynamic> fields;
    try {
      fields = _buildDraftFields();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      return;
    }

    final editing = _existingEntry;
    if (editing?.isSubmissionReserved == true) {
      setState(() {
        _error = '등록 요청이 예약된 항목은 수정할 수 없습니다. 작업 이력을 확인하세요.';
      });
      return;
    }
    if (editing == null) {
      setState(() {
        _isSaving = true;
        _error = '';
        _reconcileMessage = '';
      });
      Set<int> baseline;
      try {
        baseline =
            (await _fetchWorkspaceSnapshot()).entries.map((e) => e.id).toSet();
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _isSaving = false;
          _error =
              '저장 전 작업 목록 확인에 실패해 요청을 보내지 않았습니다. 연결을 확인하고 다시 시도하세요. $error';
        });
        return;
      }
      _preCreateEntryIds = baseline;
      var requestCompleted = false;
      try {
        final response = await widget.appState.postJson(
          '/api/menu-workspace/new-item',
          body: fields,
        );
        requestCompleted = true;
        final saved = _parseSavedEntry(response);
        _markSaved(saved, created: true);
      } catch (error) {
        if (!mounted) return;
        final uncertain =
            requestCompleted || _hasUncertainWorkspaceWriteOutcome(error);
        setState(() {
          _isSaving = false;
          _error = uncertain
              ? '저장 응답을 확인하지 못했습니다. 중복 저장하지 말고 작업 목록에서 먼저 저장 여부를 확인하세요.'
              : error.toString().replaceFirst('Exception: ', '');
          _createOutcomeUnknown = uncertain;
          _pendingCreateBody = uncertain ? fields : null;
          _noMatchReconcileChecks = 0;
          _retryCreateAllowed = false;
        });
      }
      return;
    }

    final body = buildRevisionGuardedMenuEntryUpdateBody(
      fields: fields,
      expectedRevision: editing.revision,
    );
    setState(() {
      _isSaving = true;
      _error = '';
      _serverConflict = false;
    });
    var requestCompleted = false;
    try {
      final response = await widget.appState.postJson(
        '/api/menu-workspace/entries/${editing.id}',
        body: body,
        method: 'PATCH',
      );
      requestCompleted = true;
      final saved = _parseSavedEntry(response, expectedId: editing.id);
      _markSaved(saved, created: false);
    } catch (error) {
      if (!mounted) return;
      final uncertain =
          requestCompleted || _hasUncertainWorkspaceWriteOutcome(error);
      setState(() {
        _isSaving = false;
        _error = uncertain
            ? '수정 응답을 확인하지 못했습니다. 다시 저장하기 전에 최신 버전을 확인하세요.'
            : error.toString().replaceFirst('Exception: ', '');
        _updateOutcomeUnknown = uncertain;
        _pendingUpdateBody = _updateOutcomeUnknown ? body : null;
        _serverConflict = _isWorkspaceWriteConflict(error);
      });
    }
  }

  void _markSaved(MenuEntry entry, {required bool created}) {
    if (!mounted) return;
    setState(() {
      _existingEntry = entry;
      _savedEntry = entry;
      _reviewFields = const {};
      _preparedPlan = null;
      _reconcileMatches = const [];
      _latestEntry = null;
      _step = 2;
      _isSaving = false;
      _isReconciling = false;
      _formDirty = false;
      _createOutcomeUnknown = false;
      _updateOutcomeUnknown = false;
      _retryCreateAllowed = false;
      _retryUpdateAllowed = false;
      _pendingCreateBody = null;
      _pendingUpdateBody = null;
      _serverConflict = false;
      _error = '';
      _reconcileMessage = created
          ? '등록 초안을 저장했습니다. 아직 POS에는 반영되지 않았습니다.'
          : '등록 초안을 수정했습니다. 아직 POS에는 반영되지 않았습니다.';
    });
    widget.onSubmitted?.call();
  }

  bool _entryMatchesBody(MenuEntry entry, Map<String, dynamic> body) {
    final values = <String, dynamic>{
      'item_name': entry.itemName,
      'target_price': entry.targetPrice,
      'major_category': entry.majorCategory,
      'middle_category': entry.middleCategory,
      'minor_category': entry.minorCategory,
      'unit_name': entry.unitName,
      'tax_mode': entry.taxMode,
      'use_mode': entry.useMode,
      'stock_mode': entry.stockMode,
      'barcode': entry.barcode,
      'description': entry.description,
      'notes': entry.notes,
      'cost_price': entry.costPrice,
      'supply_price': entry.supplyPrice,
    };
    for (final field in body.keys) {
      if (field == 'expected_revision') continue;
      if (values[field] != body[field]) return false;
    }
    return true;
  }

  Future<void> _reconcileSave() async {
    if (_isReconciling) return;
    setState(() {
      _isReconciling = true;
      _reconcileMatches = const [];
      _reconcileMessage = '작업 목록에서 저장 결과를 확인하고 있습니다.';
    });
    try {
      final snapshot = await _fetchWorkspaceSnapshot();
      if (!mounted) return;
      if (_createOutcomeUnknown) {
        final body = _pendingCreateBody;
        if (body == null) throw const ApiException('확인할 신규 메뉴 요청이 없습니다.');
        final matches = snapshot.entries
            .where((entry) =>
                entry.kind == 'new_item' &&
                !_preCreateEntryIds.contains(entry.id) &&
                _entryMatchesBody(entry, body))
            .toList(growable: false);
        setState(() {
          _isReconciling = false;
          _reconcileMatches = matches;
          if (matches.isNotEmpty) {
            _noMatchReconcileChecks = 0;
            _reconcileMessage =
                '입력 내용과 일치하는 새 초안이 있습니다. 저장됐다고 자동 판단하지 않습니다. 아래 항목을 확인한 뒤 선택하세요.';
          } else {
            _noMatchReconcileChecks++;
            _retryCreateAllowed = _noMatchReconcileChecks >= 2;
            _reconcileMessage = _retryCreateAllowed
                ? '최신 작업 목록 2회에서 새 초안을 찾지 못했습니다. 요청이 처리 중일 가능성도 있으니 확인 후에만 다시 저장하세요.'
                : '새 초안을 아직 찾지 못했습니다. 잠시 후 한 번 더 확인하세요. 확인 전에는 저장을 다시 요청하지 마세요.';
          }
        });
      } else if (_updateOutcomeUnknown || _serverConflict) {
        final editing = _existingEntry;
        if (editing == null) {
          throw const ApiException('확인할 수정 항목이 없습니다.');
        }
        MenuEntry? latest;
        for (final item in snapshot.entries) {
          if (item.id == editing.id) {
            latest = item;
            break;
          }
        }
        if (latest == null) {
          setState(() {
            _isReconciling = false;
            _latestEntry = null;
            _reconcileMessage = '항목을 찾지 못했습니다. 작업 목록을 새로고침해 확인하세요.';
          });
          return;
        }
        final latestEntry = latest;
        final pending = _pendingUpdateBody;
        if (pending != null && _entryMatchesBody(latestEntry, pending)) {
          _markSaved(latestEntry, created: false);
          return;
        }
        setState(() {
          _isReconciling = false;
          _latestEntry = latestEntry;
          _retryUpdateAllowed = latestEntry.revision == editing.revision &&
              !latestEntry.isSubmissionReserved;
          _reconcileMessage = _retryUpdateAllowed
              ? '서버 항목의 revision이 바뀌지 않아 수정은 저장되지 않은 것으로 보입니다. 최신 내용을 유지한 채 다시 시도할 수 있습니다.'
              : '서버 항목이 다른 요청으로 변경되었습니다. 최신 내용을 불러와 확인한 뒤 다시 편집하세요.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isReconciling = false;
        _reconcileMessage =
            '저장 결과를 확인하지 못했습니다. 다시 확인하기 전에는 요청을 반복하지 마세요. $error';
      });
    }
  }

  Future<void> _useReconciledEntry(MenuEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('이 초안을 이어서 사용'),
        content: Text(
          '“${entry.itemName}” (ID ${entry.id}, revision ${entry.revision})이 입력 내용과 일치합니다. 작업 목록에서 확인한 항목을 이어서 사용합니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('이 초안 사용'),
          ),
        ],
      ),
    );
    if (confirmed == true) _markSaved(entry, created: true);
  }

  void _loadLatestEntry(MenuEntry entry) {
    setState(() {
      _existingEntry = entry;
      _savedEntry = null;
      _latestEntry = null;
      _updateOutcomeUnknown = false;
      _serverConflict = false;
      _retryUpdateAllowed = false;
      _pendingUpdateBody = null;
      _formDirty = false;
      _preparedPlan = null;
      _error = '';
      _reconcileMessage = '최신 서버 내용을 불러왔습니다. 수정한 내용을 다시 확인하세요.';
      _step = 1;
      _itemNameController.text = entry.itemName;
      _targetPriceController.text = entry.targetPrice?.toString() ?? '';
      _costPriceController.text = entry.costPrice?.toString() ?? '';
      _supplyPriceController.text = entry.supplyPrice?.toString() ?? '';
      _barcodeController.text = entry.barcode;
      _descriptionController.text = entry.description;
      _notesController.text = entry.notes;
      _majorCategory = entry.majorCategory;
      _middleCategory = entry.middleCategory;
      _minorCategory = entry.minorCategory;
      _unitName = entry.unitName;
      _taxMode = entry.taxMode;
      _useMode = entry.useMode;
      _stockMode = entry.stockMode;
    });
  }

  Future<void> _prepareRegistration() async {
    final entry = _savedEntry;
    if (entry == null || _isPreparing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('등록 준비 확인'),
        content: const Text(
          '현재 EasyPOS 분류 카탈로그와 초안 내용을 서버에서 검증합니다. 이 단계는 POS에 상품·가격·터치키를 쓰지 않습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('준비 검증'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _isPreparing = true;
      _error = '';
      _preparedPlan = null;
    });
    try {
      final options = await _fetchFormOptions();
      final catalog = options.categoryOptions;
      if (!catalog.hasExecutionScope ||
          !catalog.containsPath(
            entry.majorCategory,
            entry.middleCategory,
            entry.minorCategory,
          )) {
        throw const ApiException(
          '최신 EasyPOS 분류 카탈로그와 등록 범위를 확인할 수 없습니다. 초안을 확인한 뒤 다시 시도하세요.',
        );
      }
      final response = await widget.appState.postJson(
        '/api/easypos/product-create/plan',
        body: {
          'tenant_id': catalog.tenantId,
          'shop_no': catalog.shopNo,
          'environment': catalog.environment,
          'credential_ref': catalog.credentialRef,
          'upstream_origin': catalog.upstreamOrigin,
          'entry_id': entry.id,
          'entry_revision': entry.revision,
          'payload': {
            'item_code': entry.itemCode,
            'item_name': entry.itemName,
            'target_price': entry.targetPrice,
            'barcode': entry.barcode,
            'unit_name': entry.unitName,
            'tax_mode': entry.taxMode,
            'use_mode': entry.useMode,
            'stock_mode': entry.stockMode,
            'cost_price': entry.costPrice,
            'supply_price': entry.supplyPrice,
          },
          'major': entry.majorCategory,
          'middle': entry.middleCategory,
          'minor': entry.minorCategory,
          'catalog_version': catalog.snapshotId,
          'form_contract_version': 'wizard-v1',
        },
      );
      final plan = asMap(response['plan']);
      if (plan.isEmpty || asString(plan['plan_id']).trim().isEmpty) {
        throw const ApiException('서버가 등록 준비 계획을 반환하지 않았습니다.');
      }
      if (!mounted) return;
      setState(() {
        _formOptions = options;
        _preparedPlan = plan;
        _isPreparing = false;
        _reconcileMessage =
            '등록 준비 검증을 마쳤습니다. POS에는 아직 반영되지 않았습니다.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isPreparing = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _confirmLeave() async {
    if (_leavePromptOpen) return;
    _leavePromptOpen = true;
    final uncertain = _createOutcomeUnknown || _updateOutcomeUnknown;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(uncertain ? '저장 결과를 확인하세요' : '작성 중인 내용이 있어요'),
        content: Text(
          uncertain
              ? '저장 응답이 불확실합니다. 나간 뒤 작업 목록을 새로고침해 초안이 저장됐는지 확인하세요. 확인 전에는 같은 요청을 반복하지 마세요.'
              : '저장하지 않은 변경 내용이 사라집니다. 나갈까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('계속 편집'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    _leavePromptOpen = false;
    if (confirmed == true && mounted) {
      Navigator.of(context).pop(_savedEntry);
    }
  }

  List<String> _selectOptions(String key, String current, String fallback) {
    final values = _formOptions?.optionValues(key) ?? const <String>[];
    final result = <String>[...values];
    if (current.trim().isNotEmpty && !result.contains(current.trim())) {
      result.add(current.trim());
    }
    if (result.isEmpty && fallback.isNotEmpty) result.add(fallback);
    return result;
  }

  Widget _selectField({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
    bool enabled = true,
  }) {
    final choices = options.toSet().toList(growable: false);
    return DropdownButtonFormField<String>(
      key: ValueKey<String>('$label:${choices.join('\u0000')}:$value'),
      initialValue: choices.contains(value) ? value : null,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: choices
          .map((option) => DropdownMenuItem<String>(
                value: option,
                child: Text(option),
              ))
          .toList(growable: false),
      onChanged: enabled && choices.isNotEmpty
          ? (next) {
              if (next == null) return;
              setState(() {
                onChanged(next);
                _markFormChanged();
              });
            }
          : null,
    );
  }

  Widget _textField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? helperText,
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      minLines: maxLines == 1 ? null : maxLines,
      maxLines: maxLines,
      textInputAction: maxLines == 1 ? TextInputAction.next : TextInputAction.newline,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => setState(_markFormChanged),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _isSaving || _isPreparing || _isReconciling;
    final entry = _savedEntry;
    final catalog = _formOptions?.categoryOptions;
    final majorOptions = catalog?.majorOptions ?? const <String>[];
    final middleOptions = _middleCategoryOptions;
    final minorOptions = _minorCategoryOptions;
    final planId = asString(_preparedPlan?['plan_id']);
    final warnings = (_preparedPlan?['validation_warnings'] as List? ?? const [])
        .map((warning) => warning.toString())
        .toList(growable: false);
    final reviewAdditionalInfo = <String>[
      if (asString(_reviewFields['barcode']).isNotEmpty)
        '바코드 ${_reviewFields['barcode']}',
      if (_reviewFields['cost_price'] != null)
        '원가 ${_won(asInt(_reviewFields['cost_price']))}원',
      if (_reviewFields['supply_price'] != null)
        '공급가 ${_won(asInt(_reviewFields['supply_price']))}원',
    ];
    return PopScope<MenuEntry?>(
      canPop: !_formDirty && !_createOutcomeUnknown && !_updateOutcomeUnknown,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmLeave());
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '등록 초안 편집' : '새 메뉴 등록'),
        actions: [
          IconButton(
            tooltip: '분류 목록 새로고침',
            onPressed: _optionsLoading || isBusy ? null : _loadFormOptions,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE2E8F0)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Row(
            children: [
              _StepBadge(number: 1, label: '정보', active: _step == 1),
              const Expanded(child: Divider()),
              _StepBadge(number: 2, label: '확인', active: _step == 2),
            ],
          ),
          const SizedBox(height: 16),
          const _InlineNotice(
            backgroundColor: Color(0xFFFFF7ED),
            borderColor: Color(0xFFFED7AA),
            textColor: Color(0xFF9A3412),
            icon: Icons.lock_outline,
            message:
                '이 화면은 CafeBridge 등록 초안만 저장하고 서버 카탈로그로 등록 준비를 검증합니다. POS 상품 등록·가격 변경·터치키 반영은 실행하지 않습니다.',
          ),
          if (_optionsLoading) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text('최신 EasyPOS 분류와 등록 기본값을 확인하고 있습니다.'),
          ],
          if (catalog != null && !catalog.available) ...[
            const SizedBox(height: 12),
            _InlineNotice(
              backgroundColor: const Color(0xFFFFF7ED),
              borderColor: const Color(0xFFFED7AA),
              textColor: const Color(0xFF9A3412),
              icon: Icons.warning_amber_outlined,
              message: 'EasyPOS 분류 목록을 사용할 수 없습니다. ${catalog.snapshotId.isEmpty ? '연결을 확인하고 새로고침해 주세요.' : '현재 분류를 확인해 주세요.'}',
            ),
          ],
          if (_step == 1) ...[
            const SizedBox(height: 16),
            Text(
              _isEditing ? '등록 초안 수정' : '새 메뉴 정보',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _textField(
              label: '상품명 *',
              controller: _itemNameController,
              enabled: !isBusy,
            ),
            const SizedBox(height: 12),
            _textField(
              label: '판매가 *',
              controller: _targetPriceController,
              keyboardType: TextInputType.number,
              enabled: !isBusy,
            ),
            const SizedBox(height: 12),
            _selectField(
              label: '대분류 *',
              value: _majorCategory,
              options: majorOptions,
              enabled: !isBusy && (catalog?.available ?? false),
              onChanged: _onMajorCategoryChanged,
            ),
            const SizedBox(height: 12),
            _selectField(
              label: '중분류 *',
              value: _middleCategory,
              options: middleOptions,
              enabled: !isBusy && _majorCategory.isNotEmpty,
              onChanged: _onMiddleCategoryChanged,
            ),
            const SizedBox(height: 12),
            _selectField(
              label: '소분류 *',
              value: _minorCategory,
              options: minorOptions,
              enabled: !isBusy && _middleCategory.isNotEmpty,
              onChanged: (value) => _minorCategory = value,
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('추가 정보'),
              subtitle: const Text('원가 · 공급가 · 바코드 · 과세 · 단위'),
              children: [
                _textField(
                  label: '원가',
                  controller: _costPriceController,
                  keyboardType: TextInputType.number,
                  helperText: _isEditing ? '비우면 기존 값이 유지됩니다.' : null,
                  enabled: !isBusy,
                ),
                const SizedBox(height: 12),
                _textField(
                  label: '공급가',
                  controller: _supplyPriceController,
                  keyboardType: TextInputType.number,
                  helperText: _isEditing ? '비우면 기존 값이 유지됩니다.' : null,
                  enabled: !isBusy,
                ),
                const SizedBox(height: 12),
                _textField(
                  label: '바코드',
                  controller: _barcodeController,
                  keyboardType: TextInputType.text,
                  enabled: !isBusy,
                ),
                const SizedBox(height: 12),
                _textField(
                  label: '상품 설명',
                  controller: _descriptionController,
                  maxLines: 2,
                  enabled: !isBusy,
                ),
                const SizedBox(height: 12),
                _selectField(
                  label: '단위',
                  value: _unitName,
                  options: _selectOptions('unit_name', _unitName, 'EA'),
                  enabled: !isBusy,
                  onChanged: (value) => _unitName = value,
                ),
                const SizedBox(height: 12),
                _selectField(
                  label: '과세',
                  value: _taxMode,
                  options: _selectOptions('tax_mode', _taxMode, '과세'),
                  enabled: !isBusy,
                  onChanged: (value) => _taxMode = value,
                ),
                const SizedBox(height: 12),
                _selectField(
                  label: '사용',
                  value: _useMode,
                  options: _selectOptions('use_mode', _useMode, '사용'),
                  enabled: !isBusy,
                  onChanged: (value) => _useMode = value,
                ),
                const SizedBox(height: 12),
                _selectField(
                  label: '재고 관리',
                  value: _stockMode,
                  options: _selectOptions('stock_mode', _stockMode, 'N'),
                  enabled: !isBusy,
                  onChanged: (value) => _stockMode = value,
                ),
                const SizedBox(height: 12),
                _textField(
                  label: '내부 메모',
                  controller: _notesController,
                  maxLines: 2,
                  enabled: !isBusy,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '상품코드는 등록 후 EasyPOS가 관리합니다. 이 초안에서 상품코드를 지정하지 않습니다.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
            Text(
              entry == null ? '저장 전 최종 확인' : '등록 초안 확인',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (_savedEntry == null) ...[
              _InfoRow(
                label: '상품명',
                value: asString(_reviewFields['item_name']),
              ),
              _InfoRow(
                label: '판매가',
                value: '${_won(asInt(_reviewFields['target_price']))}원',
              ),
              _InfoRow(
                label: '분류',
                value: [
                  _reviewFields['major_category'],
                  _reviewFields['middle_category'],
                  _reviewFields['minor_category'],
                ].where((value) => value != null && value.toString().isNotEmpty).join(' › '),
              ),
              _InfoRow(
                label: '추가 정보',
                value: reviewAdditionalInfo.isEmpty
                    ? '-'
                    : reviewAdditionalInfo.join(' · '),
              ),
              if (_reconcileMessage.isNotEmpty &&
                  (_createOutcomeUnknown ||
                      _updateOutcomeUnknown ||
                      _serverConflict)) ...[
                const SizedBox(height: 12),
                _InlineNotice(
                  backgroundColor: const Color(0xFFFFF7ED),
                  borderColor: const Color(0xFFFED7AA),
                  textColor: const Color(0xFF9A3412),
                  icon: Icons.sync_problem_outlined,
                  message: _reconcileMessage,
                ),
              ],
              if (_reconcileMatches.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final match in _reconcileMatches)
                  Card(
                    child: ListTile(
                      title: Text(match.itemName),
                      subtitle: Text(
                        'ID ${match.id} · revision ${match.revision} · ${_won(match.targetPrice ?? 0)}원',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: isBusy ? null : () => _useReconciledEntry(match),
                    ),
                  ),
              ],
              if (_latestEntry != null &&
                  (_updateOutcomeUnknown || _serverConflict)) ...[
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    title: const Text('최신 서버 버전'),
                    subtitle: Text(
                      'revision ${_latestEntry!.revision} · ${_latestEntry!.itemName}',
                    ),
                    trailing: const Icon(Icons.refresh),
                    onTap:
                        isBusy ? null : () => _loadLatestEntry(_latestEntry!),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const _InlineNotice(
                backgroundColor: Color(0xFFF0FDFA),
                borderColor: Color(0xFF99F6E4),
                textColor: Color(0xFF0F766E),
                icon: Icons.info_outline,
                message: '저장 후에도 상태는 초안입니다. POS에는 아무것도 반영되지 않습니다.',
              ),
            ] else ...[
              Panel(
                title: entry.itemName,
                subtitle:
                    '초안 ID ${entry.id} · revision ${entry.revision} · ${_statusLabel(entry.status)}',
                child: Column(
                  children: [
                    _InfoRow(
                      label: '판매가',
                      value: entry.targetPrice == null
                          ? '-'
                          : '${_won(entry.targetPrice!)}원',
                    ),
                    _InfoRow(
                      label: '분류',
                      value: [
                        entry.majorCategory,
                        entry.middleCategory,
                        entry.minorCategory,
                      ].where((value) => value.isNotEmpty).join(' › '),
                    ),
                    _InfoRow(
                      label: '저장 상태',
                      value: 'CafeBridge 초안 · POS 미반영',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (_reconcileMessage.isNotEmpty)
                _InlineNotice(
                  backgroundColor: _createOutcomeUnknown || _updateOutcomeUnknown
                      ? const Color(0xFFFFF7ED)
                      : const Color(0xFFF0FDFA),
                  borderColor: _createOutcomeUnknown || _updateOutcomeUnknown
                      ? const Color(0xFFFED7AA)
                      : const Color(0xFF99F6E4),
                  textColor: _createOutcomeUnknown || _updateOutcomeUnknown
                      ? const Color(0xFF9A3412)
                      : const Color(0xFF0F766E),
                  icon: _createOutcomeUnknown || _updateOutcomeUnknown
                      ? Icons.sync_problem_outlined
                      : Icons.check_circle_outline,
                  message: _reconcileMessage,
                ),
              if (_preparedPlan != null) ...[
                const SizedBox(height: 12),
                _InlineNotice(
                  backgroundColor: const Color(0xFFF0FDFA),
                  borderColor: const Color(0xFF99F6E4),
                  textColor: const Color(0xFF0F766E),
                  icon: Icons.verified_outlined,
                  message: warnings.isEmpty
                      ? '등록 준비 검증을 마쳤습니다. 아직 POS에 반영되지 않았습니다.'
                      : '등록 준비 계획에 확인할 내용이 있습니다: ${warnings.join(' ')}',
                ),
                if (planId.isNotEmpty)
                  SelectableText('준비 번호: $planId'),
              ],
              if (_reconcileMatches.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final match in _reconcileMatches)
                  Card(
                    child: ListTile(
                      title: Text(match.itemName),
                      subtitle: Text(
                        'ID ${match.id} · revision ${match.revision} · ${_won(match.targetPrice ?? 0)}원',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: isBusy ? null : () => _useReconciledEntry(match),
                    ),
                  ),
              ],
              if (_latestEntry != null &&
                  (_updateOutcomeUnknown || _serverConflict)) ...[
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    title: const Text('최신 서버 버전'),
                    subtitle: Text(
                      'revision ${_latestEntry!.revision} · ${_latestEntry!.itemName}',
                    ),
                    trailing: const Icon(Icons.refresh),
                    onTap: isBusy ? null : () => _loadLatestEntry(_latestEntry!),
                  ),
                ),
              ],
            ],
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _error,
                style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
              ),
            ],
            if (_isSaving || _isPreparing || _isReconciling) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(minHeight: 3),
            ],
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_step == 1)
                FilledButton(
                  onPressed: isBusy ||
                          _optionsLoading ||
                          _existingEntryLocked ||
                          !(catalog?.available ?? false)
                      ? null
                      : _continueToReview,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9488),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text('다음: 내용 확인'),
                )
              else if (_savedEntry == null)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_createOutcomeUnknown ||
                        _updateOutcomeUnknown ||
                        _serverConflict)
                      OutlinedButton.icon(
                        onPressed: isBusy ? null : _reconcileSave,
                        icon: const Icon(Icons.sync),
                        label: Text(
                          _isReconciling ? '확인 중...' : '저장 여부 확인',
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 46),
                        ),
                      ),
                    if (_retryCreateAllowed)
                      OutlinedButton(
                        onPressed: isBusy
                            ? null
                            : () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (dialogContext) => AlertDialog(
                                    title: const Text('초안 저장 다시 시도'),
                                    content: const Text(
                                      '최신 작업 목록을 두 번 확인했지만 일치하는 초안이 없습니다. 중복 가능성을 이해하고 다시 저장할까요?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext, false),
                                        child: const Text('취소'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext, true),
                                        child: const Text('다시 저장'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true && mounted) {
                                  setState(() {
                                    _createOutcomeUnknown = false;
                                    _retryCreateAllowed = false;
                                  });
                                  await _saveDraft(alreadyConfirmed: true);
                                }
                              },
                        child: const Text('확인 후 다시 저장'),
                      ),
                    if (_retryUpdateAllowed)
                      OutlinedButton(
                        onPressed: isBusy
                            ? null
                            : () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (dialogContext) => AlertDialog(
                                    title: const Text('수정 다시 시도'),
                                    content: const Text(
                                      '최신 작업 목록을 확인했으며 같은 revision에 수정 내용이 반영되지 않은 것으로 보입니다. 같은 수정 요청을 다시 보낼까요?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext, false),
                                        child: const Text('취소'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext, true),
                                        child: const Text('다시 수정'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true || !mounted) return;
                                setState(() {
                                  _updateOutcomeUnknown = false;
                                  _retryUpdateAllowed = false;
                                });
                                await _saveDraft(alreadyConfirmed: true);
                              },
                        child: const Text('수정 다시 시도'),
                      ),
                    if (!_createOutcomeUnknown &&
                        !_updateOutcomeUnknown &&
                        !_serverConflict)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isBusy
                                  ? null
                                  : () => setState(() {
                                        _step = 1;
                                        _error = '';
                                      }),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 50),
                              ),
                              child: const Text('수정하기'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: isBusy ? null : () => _saveDraft(),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF0D9488),
                                minimumSize: const Size(double.infinity, 50),
                              ),
                              child: Text(
                                  _isSaving ? '저장 중...' : '초안 저장'),
                            ),
                          ),
                        ],
                      ),
                  ],
                )
              else ...[
                if (!_createOutcomeUnknown &&
                    !_updateOutcomeUnknown &&
                    !_serverConflict)
                  OutlinedButton(
                    onPressed: isBusy
                        ? null
                        : () {
                            _existingEntry = _savedEntry;
                            setState(() {
                              _step = 1;
                              _formDirty = false;
                              _preparedPlan = null;
                              _error = '';
                            });
                          },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 46),
                    ),
                    child: const Text('초안 내용 수정'),
                  ),
                if (_savedEntry != null &&
                    !_createOutcomeUnknown &&
                    !_updateOutcomeUnknown &&
                    !_serverConflict)
                  FilledButton(
                    onPressed: isBusy ? null : _prepareRegistration,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9488),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: Text(
                      _isPreparing
                          ? '서버에서 검증 중...'
                          : _preparedPlan == null
                              ? '등록 준비 검증'
                              : '최신 카탈로그로 다시 검증',
                    ),
                  ),
                if (_savedEntry != null)
                  TextButton(
                    onPressed: isBusy
                        ? null
                        : () => Navigator.of(context).pop(_savedEntry),
                    child: Text(widget.existingEntry == null
                        ? '초안 목록으로 돌아가기'
                        : '상세 화면으로 돌아가기'),
                  ),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _StepBadge extends StatelessWidget {
  final int number;
  final String label;
  final bool active;

  const _StepBadge({
    required this.number,
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF0D9488) : const Color(0xFF64748B);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: active
              ? const Color.fromRGBO(13, 148, 136, 0.12)
              : const Color(0xFFF1F5F9),
          child: Text(
            '$number',
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

// ─── Product Card ─────────────────────────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  final _ProductRow product;
  final VoidCallback? onTap;
  final VoidCallback? onInfoTap;

  const _ProductCard({
    required this.product,
    this.onTap,
    this.onInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.inventory_2_outlined,
            size: 20, color: Color(0xFF94A3B8)),
        title: Text(
          product.itemName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          [
            if (product.itemCode.isNotEmpty) product.itemCode,
            if (product.category.isNotEmpty) product.category,
          ].join(' · '),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (product.salePrice != null)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_won(product.salePrice!)}원',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  if (onTap != null)
                    const Text(
                      '탭하여 가격 변경',
                      style: TextStyle(fontSize: 10, color: Color(0xFF0D9488)),
                    ),
                ],
              )
            else if (onTap != null)
              const Text(
                '탭하여 가격 변경',
                style: TextStyle(fontSize: 11, color: Color(0xFF0D9488)),
              ),
            if (onInfoTap != null) ...[
              const SizedBox(width: 4),
              IconButton(
                onPressed: onInfoTap,
                icon: const Icon(Icons.info_outline, size: 18),
                visualDensity: VisualDensity.compact,
                color: const Color(0xFF64748B),
                tooltip: '상세 보기',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductRegistrationDetailScreen extends StatefulWidget {
  final _ProductRow product;
  final AppState appState;
  final void Function(_ProductRow product) onQuickPriceChange;

  const _ProductRegistrationDetailScreen({
    required this.product,
    required this.appState,
    required this.onQuickPriceChange,
  });

  @override
  State<_ProductRegistrationDetailScreen> createState() =>
      _ProductRegistrationDetailScreenState();
}

class _ProductRegistrationDetailScreenState
    extends State<_ProductRegistrationDetailScreen> {
  ProductRegistrationLookup? _lookup;
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool force = false}) async {
    final itemCode = widget.product.itemCode.trim();
    if (itemCode.isEmpty) {
      setState(() {
        _lookup = null;
        _isLoading = false;
        _error = '상품코드가 없어 상품등록 상세를 불러올 수 없습니다.';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final response = await widget.appState.fetchMapParsed(
        '/api/menu-workspace/product-registration/${Uri.encodeComponent(itemCode)}',
        params: {'compact': 'false', 'refresh': force ? 'true' : 'false'},
        parser: ProductRegistrationLookup.fromJson,
        cacheTtl: force ? Duration.zero : const Duration(minutes: 10),
      );
      if (!mounted) return;
      setState(() {
        _lookup = response.data;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Map<String, dynamic> get _row {
    final lookupRow = _lookup?.row;
    return lookupRow?.isNotEmpty == true ? lookupRow! : widget.product.raw;
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = widget.appState.hasOperatorAccess;
    final itemCode = widget.product.itemCode.trim();
    final source =
        (_lookup?.source ?? '').isNotEmpty ? _lookup!.source : 'cache';
    final syncedAt = _lookup?.syncedAt ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('상품등록 상세'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : () => _load(force: true),
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Panel(
              title: widget.product.itemName,
              subtitle: itemCode.isEmpty ? '상품코드 없음' : itemCode,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _WorkspaceInfoStrip(
                    title: '조회 상태',
                    loading: _isLoading,
                    error: _error,
                    summary: _lookup == null
                        ? '조회 데이터 없음'
                        : '${_lookup!.found ? '조회 완료' : '미발견'} · ${source.toUpperCase()} · ${_freshnessLabel(syncedAt)}',
                    trailing: canEdit && itemCode.isNotEmpty
                        ? FilledButton.icon(
                            onPressed: () =>
                                widget.onQuickPriceChange(widget.product),
                            icon: const Icon(Icons.price_change_outlined,
                                size: 16),
                            label: const Text('가격 변경'),
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _TinyMetricChip(
                          label: '상품명',
                          value: _lookupValue(widget.product.itemName),
                          accent: true),
                      _TinyMetricChip(
                          label: '코드', value: _lookupValue(itemCode)),
                      _TinyMetricChip(
                          label: '판매가',
                          value: widget.product.salePrice == null
                              ? '-'
                              : '${_won(widget.product.salePrice!)}원'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Panel(
              title: '상세 정보',
              subtitle: '상품등록 화면의 값을 그대로 보여줍니다.',
              child: Column(
                children: [
                  for (final field in _lookupDetailFields)
                    _InfoRow(
                      label: field.label,
                      value: field.money
                          ? _lookupMoney(_row[field.key]?.toString())
                          : _lookupValue(_row[field.key]?.toString()),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Panel(
              title: '원본 메타데이터',
              child: Column(
                children: [
                  _InfoRow(
                      label: 'source', value: _lookupValue(_lookup?.source)),
                  _InfoRow(
                      label: 'synced_at',
                      value: _lookupValue(_lookup?.syncedAt)),
                  _InfoRow(
                      label: 'found',
                      value: _lookup?.found == true ? 'true' : 'false'),
                  _InfoRow(
                      label: '상품코드', value: _lookupValue(_lookup?.productCode)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Quick Price Change Sheet ─────────────────────────────────────────────────

class _QuickPriceChangeSheet extends StatefulWidget {
  final _ProductRow product;
  final AppState appState;
  final Future<void> Function()? onDirectApplied;

  const _QuickPriceChangeSheet({
    required this.product,
    required this.appState,
    this.onDirectApplied,
  });

  @override
  State<_QuickPriceChangeSheet> createState() => _QuickPriceChangeSheetState();
}

class _QuickPriceChangeSheetState extends State<_QuickPriceChangeSheet> {
  final _targetController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isDirectApplying = false;
  String _error = '';
  EditorContext? _editorContext;
  bool _isLoadingPriceCapability = true;
  String _priceCapabilityError = '';
  TaskPoller<BrowserPriceApplyTask>? _poller;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPriceCapability());
  }

  @override
  void dispose() {
    _poller?.cancel();
    _targetController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<BrowserPriceApplyTask> _pollBrowserApplyTask(String taskId) async {
    final poller = TaskPoller<BrowserPriceApplyTask>(
      interval: const Duration(seconds: 3),
      timeout: const Duration(minutes: 6),
      adapter: TaskStatusAdapter<BrowserPriceApplyTask>(
        statusOf: (task) => task.status,
      ),
      fetch: () async {
        final response =
            await widget.appState.fetchMapParsed<BrowserPriceApplyTask>(
          '/api/price/browser-apply/$taskId',
          parser: BrowserPriceApplyTask.fromJson,
          cacheTtl: Duration.zero,
          allowStaleOnError: false,
        );
        return response.data;
      },
    );
    _poller?.cancel();
    _poller = poller;
    try {
      return await poller.poll();
    } on TaskPollingFailedException<BrowserPriceApplyTask> catch (error) {
      return error.value;
    } on TimeoutException {
      throw const ApiException(
        '가격 변경 작업 응답이 지연되고 있습니다. 잠시 후 다시 확인해 주세요.',
      );
    } finally {
      if (identical(_poller, poller)) _poller = null;
    }
  }

  bool get _canApplyPrice => _editorContext?.canApplyPrice('판매가') ?? false;

  String get _priceApplyBlockReason {
    if (_isLoadingPriceCapability) return '서버에서 가격 반영 권한을 확인하고 있습니다.';
    if (_priceCapabilityError.isNotEmpty) {
      return '가격 실제 반영 상태를 확인하지 못해 실행이 차단되었습니다. $_priceCapabilityError';
    }
    return _editorContext?.priceApplyBlockReason('판매가') ??
        '서버에서 가격 반영 기능 상태를 확인할 수 없어 실행이 차단되었습니다.';
  }

  Future<EditorContext> _refreshPriceCapability() async {
    try {
      final response = await widget.appState.fetchMapParsed<EditorContext>(
        '/api/editor/context',
        parser: EditorContext.fromJson,
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      if (mounted) {
        setState(() {
          _editorContext = response.data;
          _priceCapabilityError = '';
          _isLoadingPriceCapability = false;
        });
      }
      return response.data;
    } catch (error) {
      if (mounted) {
        setState(() {
          _editorContext = null;
          _priceCapabilityError = error.toString();
          _isLoadingPriceCapability = false;
        });
      }
      rethrow;
    }
  }

  Future<void> _loadPriceCapability() async {
    try {
      await _refreshPriceCapability();
    } catch (_) {
      // The disabled action and inline explanation are the fail-closed state.
    }
  }

  Future<void> _requirePriceApplyCapability() async {
    final editorContext = await _refreshPriceCapability();
    if (!editorContext.canApplyPrice('판매가')) {
      throw ApiException(
        editorContext.priceApplyBlockReason('판매가'),
        statusCode: 503,
        code: editorContext.capability('apply_price')?.reasonCode ??
            'capability_disabled',
      );
    }
  }

  Future<void> _applyDirectly() async {
    if (!_canApplyPrice) {
      setState(() => _error = _priceApplyBlockReason);
      return;
    }
    final itemCode = widget.product.itemCode.trim();
    if (itemCode.isEmpty) {
      setState(() => _error = '상품코드가 없어 POS 즉시 적용을 실행할 수 없습니다.');
      return;
    }

    final targetText = _targetController.text.replaceAll(',', '');
    final targetPrice = int.tryParse(targetText);
    if (targetPrice == null || targetPrice < 0) {
      setState(() => _error = '변경할 가격을 올바르게 입력하세요.');
      return;
    }

    setState(() {
      _isDirectApplying = true;
      _error = '';
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      final reason = _notesController.text.trim();
      final previewStarted = await widget.appState.postJson(
        '/api/price/browser-apply',
        body: {
          'product_code': itemCode,
          'target_price': targetPrice,
          'target_column': '판매가',
          'execute': false,
          'reason': reason.isNotEmpty ? reason : 'mobile-browser-preview',
        },
      );
      final previewTaskId =
          AsyncTaskStartResponse.fromJson(previewStarted).taskId.trim();
      if (previewTaskId.isEmpty) {
        throw const ApiException('가격 변경 작업 ID를 받지 못했습니다.');
      }
      final previewTask = await _pollBrowserApplyTask(previewTaskId);
      if (previewTask.status != 'succeeded' ||
          previewTask.result?.status != 'preview') {
        throw ApiException(
          previewTask.result?.message.isNotEmpty == true
              ? previewTask.result!.message
              : '가격 변경 미리보기에 실패했습니다.',
        );
      }
      // A successful preview is not permission to mutate. Re-check the
      // server-owned capability before showing the POS confirmation.
      await _requirePriceApplyCapability();
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('가격 변경 실행'),
          content: Text(
            '${widget.product.itemName}의 판매가를 ${_won(targetPrice)}원으로 실제 반영할까요?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('실제 반영'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      // Confirmations may remain open while the backend feature gate changes.
      // Refresh again immediately before sending execute=true.
      await _requirePriceApplyCapability();
      final started = await widget.appState.postJson(
        '/api/price/browser-apply',
        body: {
          'product_code': itemCode,
          'target_price': targetPrice,
          'target_column': '판매가',
          'execute': true,
          'reason': reason.isNotEmpty ? reason : 'mobile-browser-apply',
        },
      );
      final taskId = AsyncTaskStartResponse.fromJson(started).taskId.trim();
      if (taskId.isEmpty) {
        throw const ApiException('가격 변경 작업 ID를 받지 못했습니다.');
      }
      final task = await _pollBrowserApplyTask(taskId);
      if (!mounted) return;

      final taskStatus = task.status;
      final taskResult = task.result;
      final resultStatus = taskResult?.status ?? '';
      final itemName = (taskResult?.itemName.isNotEmpty == true
              ? taskResult!.itemName
              : widget.product.itemName)
          .trim();
      final message = (taskResult?.message.isNotEmpty == true
              ? taskResult!.message
              : task.errorMessage)
          .trim();

      if (taskStatus == 'succeeded' && resultStatus == 'applied') {
        await widget.onDirectApplied?.call();
        if (!mounted) return;
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              message.isNotEmpty
                  ? '$itemName · $message'
                  : '$itemName 가격이 POS에 적용됐습니다.',
            ),
            backgroundColor: const Color(0xFF0D9488),
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }

      setState(() {
        _error = message.isNotEmpty ? message : 'POS 가격 변경에 실패했습니다.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isDirectApplying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final isBusy = _isDirectApplying;
    return Scaffold(
      appBar: AppBar(
        title: const Text('가격 변경'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE2E8F0)),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Row(
              children: [
                const Icon(Icons.price_change_outlined,
                    color: Color(0xFF0D9488), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.itemName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                      if (p.itemCode.isNotEmpty)
                        Text(
                          p.itemCode,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                    ],
                  ),
                ),
                if (p.salePrice != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('현재가',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF64748B))),
                      Text(
                        '${_won(p.salePrice!)}원',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: Color(0xFF0F172A)),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (p.itemCode.isEmpty)
              const _InlineNotice(
                backgroundColor: Color(0xFFFEF3C7),
                borderColor: Color(0xFFF59E0B),
                textColor: Color(0xFF92400E),
                icon: Icons.warning_amber_outlined,
                message: '이 상품은 POS 상품코드가 없어 POS 즉시 적용을 실행할 수 없습니다.',
              ),
            if (p.isLikelyOption) ...[
              if (p.itemCode.isEmpty) const SizedBox(height: 10),
              const _InlineNotice(
                backgroundColor: Color(0xFFFFF7ED),
                borderColor: Color(0xFFF59E0B),
                textColor: Color(0xFF9A3412),
                icon: Icons.info_outline,
                message:
                    '옵션/부가 항목처럼 보여 POS 직접 적용이 실패할 수 있습니다. 웹과 같은 Selenium 경로로 요청해도 POS 검색 결과에 없으면 적용되지 않습니다.',
              ),
            ],
            if (!_canApplyPrice) ...[
              const SizedBox(height: 10),
              _InlineNotice(
                backgroundColor: const Color(0xFFFFF7ED),
                borderColor: const Color(0xFFF59E0B),
                textColor: const Color(0xFF9A3412),
                icon: Icons.lock_outline,
                message: _priceApplyBlockReason,
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _targetController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '변경할 가격 *',
                suffixText: '원',
                border: const OutlineInputBorder(),
                hintText:
                    p.salePrice != null ? '현재 ${_won(p.salePrice!)}원' : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '메모 (선택)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _error,
                style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
              ),
            ],
            if (_isDirectApplying) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(minHeight: 3),
              const SizedBox(height: 8),
              const Text(
                '웹과 동일한 헤드리스 Selenium 경로로 POS 가격 변경을 실행 중입니다. 최대 1~2분 정도 걸릴 수 있습니다.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: isBusy ||
                        _isLoadingPriceCapability ||
                        !_canApplyPrice ||
                        p.itemCode.isEmpty
                    ? null
                    : _applyDirectly,
                icon: const Icon(Icons.rocket_launch_outlined),
                label: Text(_isDirectApplying
                    ? 'POS 적용 중...'
                    : _canApplyPrice
                        ? 'POS에 즉시 적용'
                        : '현재 실제 반영 불가'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1D4ED8),
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Entry Detail Screen ──────────────────────────────────────────────────────

class MenuEntryDetailScreen extends StatefulWidget {
  final MenuEntry entry;
  final VoidCallback? onUpdated;

  const MenuEntryDetailScreen({super.key, required this.entry, this.onUpdated});

  @override
  State<MenuEntryDetailScreen> createState() => _MenuEntryDetailScreenState();
}

class _MenuEntryDetailScreenState extends State<MenuEntryDetailScreen> {
  late MenuEntry _entry;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
  }

  @override
  Widget build(BuildContext context) {
    final e = _entry;
    final appState = context.read<AppState>();
    final canEdit = appState.hasOperatorAccess && !e.isSubmissionReserved;
    final canEditMenuDraft = canEdit &&
        e.kind == 'new_item' &&
        !const {'ready', 'done', 'reserved', 'stale'}.contains(e.status);
    final canEditStatus = canEdit &&
        e.kind != 'new_item' &&
        !const {'done', 'reserved', 'stale'}.contains(e.status);

    return Scaffold(
      appBar: AppBar(
        title: Text(e.itemName),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE2E8F0)),
        ),
        actions: [
          if (canEditMenuDraft)
            IconButton(
              tooltip: '등록 초안 편집',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _editMenuDraft(e),
            ),
          if (canEditStatus)
            IconButton(
              tooltip: '항목 편집',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _showStatusSheet(e),
            ),
          if (canEdit)
            IconButton(
              tooltip: '초안 삭제',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteEntry(e),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Panel(
              title: '기본 정보',
              child: Column(
                children: [
                  _InfoRow(label: '품목명', value: e.itemName),
                  _InfoRow(
                      label: '품목코드',
                      value: e.itemCode.isEmpty ? '-' : e.itemCode),
                  _InfoRow(
                      label: '분류',
                      value: e.kind == 'new_item'
                          ? [
                              e.majorCategory,
                              e.middleCategory,
                              e.minorCategory,
                            ].where((value) => value.isNotEmpty).join(' › ')
                          : (e.categoryHint.isEmpty ? '-' : e.categoryHint)),
                  _InfoRow(label: 'revision', value: '${e.revision}'),
                  _InfoRow(label: '상태', value: _statusLabel(e.status)),
                  _InfoRow(label: '종류', value: _kindLabel(e.kind)),
                  _InfoRow(
                      label: '단위',
                      value: e.unitName.isEmpty ? '-' : e.unitName),
                  _InfoRow(
                      label: '과세', value: e.taxMode.isEmpty ? '-' : e.taxMode),
                  _InfoRow(
                      label: '사용', value: e.useMode.isEmpty ? '-' : e.useMode),
                  _InfoRow(
                      label: '재고',
                      value: e.stockMode.isEmpty ? '-' : e.stockMode),
                  _InfoRow(
                      label: '바코드', value: e.barcode.isEmpty ? '-' : e.barcode),
                  _InfoRow(
                      label: '상품설명',
                      value: e.description.isEmpty ? '-' : e.description),
                  _InfoRow(
                      label: '출처', value: e.source.isEmpty ? '-' : e.source),
                  _InfoRow(
                      label: '생성',
                      value: e.createdAt.isEmpty ? '-' : e.createdAt),
                  _InfoRow(
                      label: '수정',
                      value: e.updatedAt.isEmpty ? '-' : e.updatedAt),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (e.kind == 'price_update') ...[
              Panel(
                title: '가격 정보',
                child: Column(
                  children: [
                    _InfoRow(
                      label: '현재 가격',
                      value: e.currentPrice == null
                          ? '-'
                          : '${_won(e.currentPrice!)}원',
                    ),
                    _InfoRow(
                      label: '목표 가격',
                      value: e.targetPrice == null
                          ? '-'
                          : '${_won(e.targetPrice!)}원',
                    ),
                    _InfoRow(
                      label: '변동',
                      value: e.targetPrice == null
                          ? '-'
                          : '${_wonSigned(e.priceDelta)}원',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (e.kind == 'new_item') ...[
              Panel(
                title: '등록 정보',
                child: Column(
                  children: [
                    _InfoRow(
                      label: '판매가',
                      value: e.targetPrice == null
                          ? '-'
                          : '${_won(e.targetPrice!)}원',
                    ),
                    _InfoRow(
                      label: '원가 / 공급가',
                      value:
                          '${e.costPrice == null ? '-' : _won(e.costPrice!)} / ${e.supplyPrice == null ? '-' : _won(e.supplyPrice!)}원',
                    ),
                    _InfoRow(
                      label: '저장 상태',
                      value: e.isSubmissionReserved
                          ? '등록 요청 처리 중 · 편집/삭제 제한'
                          : 'CafeBridge 초안 · POS 미반영',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (e.notes.isNotEmpty)
              Panel(
                title: '메모',
                child: Text(e.notes),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteEntry(MenuEntry entry) async {
    final appState = context.read<AppState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('메뉴 작업 항목 삭제'),
        content: Text(
          '"${entry.itemName}" 항목을 삭제할까요? 이미 등록이 예약된 항목은 삭제할 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await appState.postJson(
        '/api/menu-workspace/entries/${entry.id}',
        method: 'DELETE',
      );
      if (!mounted) return;
      widget.onUpdated?.call();
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _showStatusSheet(MenuEntry entry) async {
    final appState = context.read<AppState>();
    final updated = await Navigator.of(context).push<MenuEntry>(
      MaterialPageRoute(
        builder: (_) => AccessGate(
          minimumRole: UserRole.admin,
          fullScreen: true,
          child: _StatusUpdateSheet(
            entry: entry,
            appState: appState,
          ),
        ),
      ),
    );
    if (!mounted || updated == null) {
      return;
    }
    setState(() => _entry = updated);
    widget.onUpdated?.call();
  }

  Future<void> _editMenuDraft(MenuEntry entry) async {
    final appState = context.read<AppState>();
    final updated = await Navigator.of(context).push<MenuEntry>(
      MaterialPageRoute(
        builder: (_) => AccessGate(
          minimumRole: UserRole.admin,
          fullScreen: true,
          child: _NewMenuAddScreen(
            appState: appState,
            existingEntry: entry,
            onSubmitted: widget.onUpdated,
          ),
        ),
      ),
    );
    if (!mounted || updated == null) return;
    setState(() => _entry = updated);
  }
}

// ─── Status Update Sheet ──────────────────────────────────────────────────────

class _StatusUpdateSheet extends StatefulWidget {
  final MenuEntry entry;
  final AppState appState;

  const _StatusUpdateSheet({
    required this.entry,
    required this.appState,
  });

  @override
  State<_StatusUpdateSheet> createState() => _StatusUpdateSheetState();
}

class _StatusUpdateSheetState extends State<_StatusUpdateSheet> {
  String _selectedStatus = '';
  int? _newTargetPrice;
  late final TextEditingController _targetPriceController;
  bool _isSubmitting = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.entry.status;
    _targetPriceController = TextEditingController(
      text: widget.entry.targetPrice?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _targetPriceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedStatus == widget.entry.status &&
        (_newTargetPrice == null ||
            _newTargetPrice == widget.entry.targetPrice)) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = '';
    });
    try {
      final body = buildRevisionGuardedMenuEntryUpdateBody(
        fields: {'status': _selectedStatus},
        expectedRevision: widget.entry.revision,
      );
      if (_newTargetPrice != null) body['target_price'] = _newTargetPrice;
      final response = await widget.appState.postJson(
        '/api/menu-workspace/entries/${widget.entry.id}',
        body: body,
        method: 'PATCH',
      );
      if (!mounted) return;
      Navigator.of(context).pop(MenuEntry.fromJson(response));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const statuses = ['draft', 'reviewed', 'ready', 'archived'];
    const labels = ['작성중', '검토됨', '준비완료', '보관'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('항목 편집'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE2E8F0)),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(
              widget.entry.itemName,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
            const SizedBox(height: 16),
            RadioGroup<String>(
              groupValue: _selectedStatus,
              onChanged: (v) =>
                  setState(() => _selectedStatus = v ?? _selectedStatus),
              child: Column(
                children: List.generate(statuses.length, (i) {
                  return RadioListTile<String>(
                    title: Text(labels[i]),
                    value: statuses[i],
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  );
                }),
              ),
            ),
            if (widget.entry.kind == 'price_update') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _targetPriceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '목표 가격 (원)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  final parsed = int.tryParse(v.replaceAll(',', ''));
                  setState(() => _newTargetPrice = parsed);
                },
              ),
            ],
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _error,
                style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
            child: Text(_isSubmitting ? '저장 중...' : '저장'),
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceInfoStrip extends StatelessWidget {
  final String title;
  final bool loading;
  final String error;
  final String summary;
  final Widget? trailing;

  const _WorkspaceInfoStrip({
    required this.title,
    required this.loading,
    required this.error,
    required this.summary,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        error.isNotEmpty ? const Color(0xFF9A3412) : const Color(0xFF0F172A);
    final background =
        error.isNotEmpty ? const Color(0xFFFFF7ED) : const Color(0xFFF8FAFC);
    final border =
        error.isNotEmpty ? const Color(0xFFFCD34D) : const Color(0xFFE2E8F0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                error.isNotEmpty ? error : summary,
                style: TextStyle(fontSize: 12, color: color),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          );
          final indicator = Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: loading
                  ? const Color(0xFF0EA5E9)
                  : error.isNotEmpty
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFF0D9488),
              shape: BoxShape.circle,
            ),
          );
          if (trailing != null && constraints.maxWidth < 360) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    indicator,
                    const SizedBox(width: 10),
                    Expanded(child: details),
                  ],
                ),
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: trailing!),
              ],
            );
          }
          return Row(
            children: [
              indicator,
              const SizedBox(width: 10),
              Expanded(child: details),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TinyMetricChip extends StatelessWidget {
  final String label;
  final String value;
  final bool accent;

  const _TinyMetricChip({
    required this.label,
    required this.value,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent
            ? const Color.fromRGBO(13, 148, 136, 0.08)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: accent ? const Color(0xFF0D9488) : const Color(0xFFE2E8F0)),
      ),
      child: Text('$label $value',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _TaskHistoryHeader extends StatelessWidget {
  final String label;
  final bool loading;
  final String error;
  final int count;
  final VoidCallback onRefresh;

  const _TaskHistoryHeader({
    required this.label,
    required this.loading,
    required this.error,
    required this.count,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(width: 6),
        Text('($count)',
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
        const Spacer(),
        if (error.isNotEmpty)
          const Icon(Icons.error_outline, size: 16, color: Color(0xFFDC2626)),
        if (loading) ...[
          const SizedBox(width: 8),
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
        const SizedBox(width: 4),
        IconButton(
          tooltip: '$label 새로고침',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh, size: 16),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _PriceApplyRunTile extends StatelessWidget {
  final PriceApplyRun run;

  const _PriceApplyRunTile({required this.run});

  @override
  Widget build(BuildContext context) {
    final ok = run.status == 'succeeded';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  run.taskId,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                run.status,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: ok ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '총 ${run.totalItems} · 적용 ${run.appliedCount} · 실패 ${run.failedCount}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
          if (run.errorMessage.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(run.errorMessage,
                style: const TextStyle(fontSize: 11, color: Color(0xFFB45309))),
          ],
        ],
      ),
    );
  }
}

class _TaskHistoryTile extends StatelessWidget {
  final WorkspaceTaskHistoryEntry task;

  const _TaskHistoryTile({required this.task});

  @override
  Widget build(BuildContext context) {
    final ok = task.resultStatus == 'applied' || task.status == 'succeeded';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.displayTitle,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                task.status,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: ok ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                ),
              ),
            ],
          ),
          if (task.displaySubtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(task.displaySubtitle,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          ],
          if (task.resultMessage.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(task.resultMessage,
                style: const TextStyle(fontSize: 11, color: Color(0xFF0F172A))),
          ],
        ],
      ),
    );
  }
}

// ─── Filter Bar ───────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final String filterStatus;
  final String filterKind;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onKindChanged;

  const _FilterBar({
    required this.filterStatus,
    required this.filterKind,
    required this.onStatusChanged,
    required this.onKindChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterChipWidget(
              label: '전체',
              value: 'all',
              groupValue: filterStatus,
              onSelected: onStatusChanged),
          const SizedBox(width: 6),
          _FilterChipWidget(
              label: '작성중',
              value: 'draft',
              groupValue: filterStatus,
              onSelected: onStatusChanged),
          const SizedBox(width: 6),
          _FilterChipWidget(
              label: '검토됨',
              value: 'reviewed',
              groupValue: filterStatus,
              onSelected: onStatusChanged),
          const SizedBox(width: 6),
          _FilterChipWidget(
              label: '준비완료',
              value: 'ready',
              groupValue: filterStatus,
              onSelected: onStatusChanged),
          const SizedBox(width: 6),
          _FilterChipWidget(
              label: '완료',
              value: 'done',
              groupValue: filterStatus,
              onSelected: onStatusChanged),
          const SizedBox(width: 6),
          _FilterChipWidget(
              label: '보관',
              value: 'archived',
              groupValue: filterStatus,
              onSelected: onStatusChanged),
          const SizedBox(width: 16),
          _FilterChipWidget(
              label: '전체 종류',
              value: 'all',
              groupValue: filterKind,
              onSelected: onKindChanged),
          const SizedBox(width: 6),
          _FilterChipWidget(
              label: '가격변경',
              value: 'price_update',
              groupValue: filterKind,
              onSelected: onKindChanged),
          const SizedBox(width: 6),
          _FilterChipWidget(
              label: '신규등록',
              value: 'new_item',
              groupValue: filterKind,
              onSelected: onKindChanged),
        ],
      ),
    );
  }
}

class _FilterChipWidget extends StatelessWidget {
  final String label;
  final String value;
  final String groupValue;
  final ValueChanged<String> onSelected;

  const _FilterChipWidget({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(value),
      selectedColor: const Color.fromRGBO(13, 148, 136, 0.15),
      checkmarkColor: const Color(0xFF0D9488),
    );
  }
}

// ─── Workspace Entry Cards ────────────────────────────────────────────────────

class _MenuEntryCard extends StatelessWidget {
  final MenuEntry entry;
  final VoidCallback onTap;
  final List<String> issues;

  const _MenuEntryCard({
    required this.entry,
    required this.onTap,
    this.issues = const [],
  });

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: _StatusBadge(status: e.status),
        title: Row(
          children: [
            Expanded(
                child: Text(e.itemName,
                    style: const TextStyle(fontWeight: FontWeight.w700))),
            _KindBadge(kind: e.kind),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              e.itemCode.isEmpty
                  ? e.categoryHint
                  : '${e.itemCode}${e.categoryHint.isNotEmpty ? ' · ${e.categoryHint}' : ''}',
            ),
            if (issues.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: issues.take(2).map((issue) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      issue,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF9A3412)),
                    ),
                  );
                }).toList(growable: false),
              ),
            ],
          ],
        ),
        isThreeLine: issues.isNotEmpty,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (e.kind == 'price_update' && e.targetPrice != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('→ ${_won(e.targetPrice!)}원',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (e.currentPrice != null)
                    Text(
                      _wonSigned(e.priceDelta),
                      style: TextStyle(
                        fontSize: 11,
                        color: e.priceDelta >= 0
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFDC2626),
                      ),
                    ),
                ],
              ),
            if (issues.isNotEmpty) ...[
              const SizedBox(height: 4),
              const Icon(Icons.warning_amber_rounded,
                  size: 18, color: Color(0xFFF59E0B)),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    final label = switch (status) {
      'draft' => '작성',
      'reviewed' => '검토',
      'ready' => '준비',
      'done' => '완료',
      'archived' => '보관',
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _KindBadge extends StatelessWidget {
  final String kind;
  const _KindBadge({required this.kind});

  @override
  Widget build(BuildContext context) {
    final label = switch (kind) {
      'price_update' => '가격',
      'new_item' => '신규',
      _ => kind,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
    );
  }
}

// ─── Apply-Ready Banner ───────────────────────────────────────────────────────

class _ApplyReadyBanner extends StatefulWidget {
  const _ApplyReadyBanner();

  @override
  State<_ApplyReadyBanner> createState() => _ApplyReadyBannerState();
}

class _ApplyReadyBannerState extends State<_ApplyReadyBanner> {
  bool _isApplying = false;

  Future<void> _apply({required bool execute}) async {
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isApplying = true);
    try {
      final result = await appState.postJson(
        '/api/menu-workspace/apply-ready',
        body: {'execute': execute, 'reason': execute ? 'mobile-apply' : ''},
      );
      if (!mounted) return;
      // 응답: {"apply_result": {"success_count": ..., "items": [...]}, "skipped": [...]}
      final applyResult = result['apply_result'] as Map? ?? {};
      final skippedList = result['skipped'] as List? ?? [];
      final applied = applyResult['success_count'] ?? 0;
      final failed = applyResult['failed_count'] ?? 0;
      final skippedCount = skippedList.length;

      // 실패 항목 이유 추출
      final failedItems = (applyResult['items'] as List? ?? [])
          .whereType<Map>()
          .where((e) => e['status'] == 'failed')
          .toList();

      if (failed > 0 && failedItems.isNotEmpty) {
        // 실패 상세를 별도 스낵바로 표시
        final failDetails = failedItems.map((e) {
          final name = e['item_name'] as String? ?? '';
          final msg = e['message'] as String? ?? '알 수 없는 오류';
          return '· $name: $msg';
        }).join('\n');
        messenger.showSnackBar(SnackBar(
          content: Text('$failed건 적용 실패\n$failDetails'),
          backgroundColor: const Color(0xFFDC2626),
          duration: const Duration(seconds: 8),
        ));
      } else {
        final parts = <String>[
          if (execute) '$applied건 적용 완료' else '[미리보기] $applied건 적용 예정',
          if (failed > 0) '$failed건 실패',
          if (skippedCount > 0) '$skippedCount건 건너뜀(상품코드 없음)',
        ];
        messenger.showSnackBar(SnackBar(
          content: Text(parts.join(' · ')),
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      // ApiException 메시지에서 detail 추출 (e.g. '상품코드와 목표가...')
      final msg = e.toString().replaceFirst('ApiException: ', '');
      messenger.showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFFDC2626),
        duration: const Duration(seconds: 5),
      ));
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(13, 148, 136, 0.08),
        border: Border.all(color: const Color(0xFF0D9488)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.rocket_launch_outlined,
                  color: Color(0xFF0D9488), size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '준비완료 항목이 있습니다. 실제 반영은 웹 관리자 화면을 이용하세요.',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _isApplying ? null : () => _apply(execute: false),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact),
            child: const Text('미리보기'),
          ),
        ],
      ),
    );
  }
}

// ─── Metric Grid ──────────────────────────────────────────────────────────────

class _MetricGrid extends StatelessWidget {
  final List<Widget> cards;
  const _MetricGrid({required this.cards});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 720
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .map((c) => SizedBox(width: width, child: c))
              .toList(growable: false),
        );
      },
    );
  }
}

// ─── Info Row ─────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child:
                Text(label, style: const TextStyle(color: Color(0xFF64748B))),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _kindLabel(String k) => switch (k) {
      'price_update' => '가격 변경',
      'new_item' => '신규 등록',
      _ => k,
    };

String _won(num value) {
  final abs = value.abs().round();
  final str = abs.toString();
  final buffer = StringBuffer();
  for (int i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
    buffer.write(str[i]);
  }
  return value < 0 ? '-${buffer.toString()}' : buffer.toString();
}

String _wonSigned(int value) {
  final sign = value >= 0 ? '+' : '';
  return '$sign${_won(value)}';
}
