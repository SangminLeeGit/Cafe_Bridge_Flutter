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

class _CategoryOptionCatalog {
  final List<String> majorOptions;
  final Map<String, List<String>> middleOptionsByMajor;
  final Map<String, List<String>> minorOptionsByMajorMiddle;

  const _CategoryOptionCatalog({
    required this.majorOptions,
    required this.middleOptionsByMajor,
    required this.minorOptionsByMajorMiddle,
  });

  factory _CategoryOptionCatalog.fromProducts(List<_ProductRow> products) {
    final majorSet = <String>{};
    final middleMap = <String, Set<String>>{};
    final minorMap = <String, Set<String>>{};

    for (final product in products) {
      final major = (product.raw['대분류명'] ?? '').toString().trim();
      final middle = (product.raw['중분류명'] ?? '').toString().trim();
      final minor = (product.raw['소분류명'] ?? '').toString().trim();
      if (major.isEmpty || middle.isEmpty) continue;

      majorSet.add(major);
      middleMap.putIfAbsent(major, () => <String>{}).add(middle);
      if (minor.isNotEmpty) {
        minorMap.putIfAbsent('$major::$middle', () => <String>{}).add(minor);
      }
    }

    List<String> sortedValues(Iterable<String> values) {
      final list = values.toList(growable: false);
      list.sort((left, right) => left.compareTo(right));
      return list;
    }

    return _CategoryOptionCatalog(
      majorOptions: sortedValues(majorSet),
      middleOptionsByMajor: {
        for (final entry in middleMap.entries)
          entry.key: sortedValues(entry.value),
      },
      minorOptionsByMajorMiddle: {
        for (final entry in minorMap.entries)
          entry.key: sortedValues(entry.value),
      },
    );
  }
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

  // Kept for the read-only preview workflow; mobile navigation does not expose it.
  // ignore: unused_element
  void _openNewItemScreen() {
    final appState = context.read<AppState>();
    if (!appState.hasOperatorAccess) return;
    final categoryCatalog = _CategoryOptionCatalog.fromProducts(_products
        .where((product) => !product.isLikelyOption)
        .toList(growable: false));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccessGate(
          minimumRole: UserRole.admin,
          fullScreen: true,
          child: _NewMenuAddScreen(
            appState: appState,
            categoryCatalog: categoryCatalog,
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
              'operator 이상 권한이 있어야 가격 변경을 실행할 수 있습니다. 신규 상품 등록은 웹 관리자 화면을 이용하세요.',
              style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
            ),
          ),
      ],
    );
  }
}

class _NewMenuAddScreen extends StatefulWidget {
  final AppState appState;
  final _CategoryOptionCatalog categoryCatalog;
  final VoidCallback? onSubmitted;

  const _NewMenuAddScreen({
    required this.appState,
    required this.categoryCatalog,
    this.onSubmitted,
  });

  @override
  State<_NewMenuAddScreen> createState() => _NewMenuAddScreenState();
}

class _NewMenuAddScreenState extends State<_NewMenuAddScreen> {
  final _itemNameController = TextEditingController();
  final _itemCodeController = TextEditingController();
  final _targetPriceController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _supplyPriceController = TextEditingController();
  final _unitNameController = TextEditingController(text: 'EA');
  final _barcodeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _reasonController = TextEditingController();

  String _taxMode = 'Y';
  String _useMode = 'Y';
  String _stockMode = 'Y';
  String _majorCategory = '';
  String _middleCategory = '';
  String _minorCategory = '';
  bool _isSubmitting = false;
  String _error = '';
  String _statusMessage = '';
  String _lastPreviewMessage = '';
  String _lastPreviewSavedCode = '';
  Map<String, dynamic> _lastResolvedCategories = const {};
  TaskPoller<WorkspaceTaskHistoryEntry>? _poller;

  @override
  void dispose() {
    _poller?.cancel();
    _itemNameController.dispose();
    _itemCodeController.dispose();
    _targetPriceController.dispose();
    _costPriceController.dispose();
    _supplyPriceController.dispose();
    _unitNameController.dispose();
    _barcodeController.dispose();
    _descriptionController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

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

  List<String> get _middleCategoryOptions {
    if (_majorCategory.trim().isEmpty) return const [];
    return widget.categoryCatalog.middleOptionsByMajor[_majorCategory.trim()] ??
        const [];
  }

  List<String> get _minorCategoryOptions {
    final major = _majorCategory.trim();
    final middle = _middleCategory.trim();
    if (major.isEmpty || middle.isEmpty) return const [];
    return widget
            .categoryCatalog.minorOptionsByMajorMiddle['$major::$middle'] ??
        const [];
  }

  String get _middleCategoryHint {
    if (_majorCategory.trim().isEmpty) return '대분류를 먼저 선택';
    if (_middleCategoryOptions.isEmpty) return '선택 가능한 중분류 없음';
    return '중분류 선택';
  }

  String get _minorCategoryHint {
    if (_majorCategory.trim().isEmpty) return '대분류를 먼저 선택';
    if (_middleCategory.trim().isEmpty) return '중분류를 먼저 선택';
    if (_minorCategoryOptions.isEmpty) return '선택 가능한 소분류 없음';
    return '소분류 선택';
  }

  void _onMajorCategoryChanged(String? value) {
    final nextMajor = (value ?? '').trim();
    final nextMiddleOptions = nextMajor.isEmpty
        ? const <String>[]
        : (widget.categoryCatalog.middleOptionsByMajor[nextMajor] ??
            const <String>[]);
    final keepMiddle = nextMiddleOptions.contains(_middleCategory.trim());
    final nextMiddle = keepMiddle ? _middleCategory.trim() : '';
    final nextMinorOptions = (nextMajor.isEmpty || nextMiddle.isEmpty)
        ? const <String>[]
        : (widget.categoryCatalog
                .minorOptionsByMajorMiddle['$nextMajor::$nextMiddle'] ??
            const <String>[]);
    final keepMinor = nextMinorOptions.contains(_minorCategory.trim());
    setState(() {
      _majorCategory = nextMajor;
      _middleCategory = nextMiddle;
      _minorCategory = keepMinor ? _minorCategory.trim() : '';
    });
  }

  void _onMiddleCategoryChanged(String? value) {
    final nextMiddle = (value ?? '').trim();
    final nextMinorOptions =
        (_majorCategory.trim().isEmpty || nextMiddle.isEmpty)
            ? const <String>[]
            : (widget.categoryCatalog.minorOptionsByMajorMiddle[
                    '${_majorCategory.trim()}::$nextMiddle'] ??
                const <String>[]);
    final keepMinor = nextMinorOptions.contains(_minorCategory.trim());
    setState(() {
      _middleCategory = nextMiddle;
      _minorCategory = keepMinor ? _minorCategory.trim() : '';
    });
  }

  Map<String, dynamic> _buildRequestBody({required bool execute}) {
    final itemName = _itemNameController.text.trim();
    final majorCategory = _majorCategory.trim();
    final middleCategory = _middleCategory.trim();
    final minorCategory = _minorCategory.trim();
    final itemCode = _itemCodeController.text.trim();
    final barcode = _barcodeController.text.trim();
    final unitName = _unitNameController.text.trim();
    final description = _descriptionController.text.trim();
    final reason = _reasonController.text.trim();
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
    if (majorCategory.isEmpty ||
        middleCategory.isEmpty ||
        minorCategory.isEmpty) {
      throw const ApiException('대/중/소 분류를 모두 입력하세요.');
    }
    if (targetPrice == null) {
      throw const ApiException('판매가를 입력하세요.');
    }
    if (barcode.isNotEmpty && int.tryParse(barcode) == null) {
      throw const ApiException('바코드는 숫자만 입력할 수 있습니다.');
    }

    return {
      'item_name': itemName,
      'target_price': targetPrice,
      'major_category': majorCategory,
      'middle_category': middleCategory,
      'minor_category': minorCategory,
      'unit_name': unitName.isEmpty ? 'EA' : unitName,
      'tax_mode': _taxMode,
      'use_mode': _useMode,
      'stock_mode': _stockMode,
      'barcode': barcode,
      'description': description,
      'item_code': itemCode,
      if (costPrice != null) 'cost_price': costPrice,
      if (supplyPrice != null) 'supply_price': supplyPrice,
      'execute': execute,
      'reason': reason.isNotEmpty
          ? reason
          : (execute ? 'mobile-new-item-apply' : 'mobile-new-item-preview'),
    };
  }

  Future<WorkspaceTaskHistoryEntry> _pollTask(String taskId) async {
    final poller = TaskPoller<WorkspaceTaskHistoryEntry>(
      interval: const Duration(seconds: 3),
      timeout: const Duration(minutes: 6),
      adapter: TaskStatusAdapter<WorkspaceTaskHistoryEntry>(
        statusOf: (task) => task.status,
      ),
      fetch: () async {
        final response =
            await widget.appState.fetchMapParsed<WorkspaceTaskHistoryEntry>(
          '/api/menu-workspace/new-item-apply/$taskId',
          parser: WorkspaceTaskHistoryEntry.fromJson,
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
    } on TaskPollingFailedException<WorkspaceTaskHistoryEntry> catch (error) {
      return error.value;
    } on TimeoutException {
      throw const ApiException(
        '신규 메뉴 작업 응답이 지연되고 있습니다. 잠시 후 다시 확인해 주세요.',
      );
    } finally {
      if (identical(_poller, poller)) _poller = null;
    }
  }

  Future<void> _submit({required bool execute}) async {
    final messenger = ScaffoldMessenger.of(context);
    Map<String, dynamic> body;
    try {
      body = _buildRequestBody(execute: execute);
    } catch (error) {
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = '';
      _statusMessage = execute
          ? '웹과 동일한 Selenium 경로로 신규 메뉴를 등록 중입니다. 최대 1~2분 정도 걸릴 수 있습니다.'
          : '신규 메뉴 미리보기를 실행 중입니다.';
    });

    try {
      final started = await widget.appState.postJson(
        '/api/menu-workspace/new-item-apply',
        body: body,
      );
      final taskId = AsyncTaskStartResponse.fromJson(started).taskId.trim();
      if (taskId.isEmpty) {
        throw const ApiException('신규 메뉴 작업 ID를 받지 못했습니다.');
      }

      final task = await _pollTask(taskId);
      if (!mounted) return;

      final topLevelMessage = task.errorMessage.trim();
      final resultMessage = task.resultMessage.trim();
      var message = resultMessage.isNotEmpty
          ? resultMessage
          : (topLevelMessage.isNotEmpty ? topLevelMessage : '작업 결과를 확인해 주세요.');
      final resultStatus = task.resultStatus;
      final isSuccess = task.status == 'succeeded' &&
          (resultStatus == 'preview' || resultStatus == 'applied');
      final savedItemCode = task.savedItemCode.trim();
      if (resultStatus == 'applied' && savedItemCode.isNotEmpty) {
        message = '$message (저장 코드 $savedItemCode)';
      }

      if (!isSuccess) {
        setState(() {
          _error = message;
          _statusMessage = '';
        });
        return;
      }

      if (execute) {
        widget.onSubmitted?.call();
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: const Color(0xFF0D9488),
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }

      setState(() {
        _lastPreviewMessage = message;
        _lastPreviewSavedCode = savedItemCode;
        _lastResolvedCategories = task.resolvedCategories;
        _statusMessage = '';
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _statusMessage = '';
      });
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _isSubmitting;
    return Scaffold(
      appBar: AppBar(
        title: const Text('신규 메뉴'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE2E8F0)),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            const _InlineNotice(
              backgroundColor: Color(0xFFF0FDFA),
              borderColor: Color(0xFF99F6E4),
              textColor: Color(0xFF0F766E),
              icon: Icons.info_outline,
              message:
                  '미리보기는 저장 가능성만 확인하고, 등록은 백엔드 신규 메뉴 추가 API를 통해 실제 저장을 시도합니다. 분류는 기존 값만 드롭다운에서 선택합니다.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _itemNameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '상품명 *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _itemCodeController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '상품코드',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _unitNameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '단위명칭',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue:
                        _majorCategory.isEmpty ? null : _majorCategory,
                    hint: const Text('대분류 선택'),
                    decoration: const InputDecoration(
                      labelText: '대분류 *',
                      border: OutlineInputBorder(),
                    ),
                    items: widget.categoryCatalog.majorOptions
                        .map(
                          (option) => DropdownMenuItem<String>(
                              value: option, child: Text(option)),
                        )
                        .toList(growable: false),
                    onChanged: isBusy ? null : _onMajorCategoryChanged,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue:
                        _middleCategory.isEmpty ? null : _middleCategory,
                    hint: Text(_middleCategoryHint),
                    disabledHint: Text(_middleCategoryHint),
                    decoration: const InputDecoration(
                      labelText: '중분류 *',
                      border: OutlineInputBorder(),
                    ),
                    items: _middleCategoryOptions
                        .map((option) => DropdownMenuItem<String>(
                            value: option, child: Text(option)))
                        .toList(growable: false),
                    onChanged: isBusy ||
                            _majorCategory.trim().isEmpty ||
                            _middleCategoryOptions.isEmpty
                        ? null
                        : _onMiddleCategoryChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _minorCategory.isEmpty ? null : _minorCategory,
              hint: Text(_minorCategoryHint),
              disabledHint: Text(_minorCategoryHint),
              decoration: const InputDecoration(
                labelText: '소분류 *',
                border: OutlineInputBorder(),
              ),
              items: _minorCategoryOptions
                  .map((option) => DropdownMenuItem<String>(
                      value: option, child: Text(option)))
                  .toList(growable: false),
              onChanged: isBusy ||
                      _middleCategory.trim().isEmpty ||
                      _minorCategoryOptions.isEmpty
                  ? null
                  : (value) =>
                      setState(() => _minorCategory = (value ?? '').trim()),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _targetPriceController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '판매가 *',
                      suffixText: '원',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _costPriceController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '원가',
                      suffixText: '원',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _supplyPriceController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '공급가',
                      suffixText: '원',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _taxMode,
                    decoration: const InputDecoration(
                      labelText: '과세유무',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Y', child: Text('과세(Y)')),
                      DropdownMenuItem(value: 'N', child: Text('면세(N)')),
                    ],
                    onChanged: isBusy
                        ? null
                        : (value) =>
                            setState(() => _taxMode = value ?? _taxMode),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _useMode,
                    decoration: const InputDecoration(
                      labelText: '사용구분',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Y', child: Text('사용(Y)')),
                      DropdownMenuItem(value: 'N', child: Text('미사용(N)')),
                    ],
                    onChanged: isBusy
                        ? null
                        : (value) =>
                            setState(() => _useMode = value ?? _useMode),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _stockMode,
                    decoration: const InputDecoration(
                      labelText: '재고관리',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Y', child: Text('관리(Y)')),
                      DropdownMenuItem(value: 'N', child: Text('미관리(N)')),
                    ],
                    onChanged: isBusy
                        ? null
                        : (value) =>
                            setState(() => _stockMode = value ?? _stockMode),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _barcodeController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '바코드',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '상품설명',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonController,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '메모 / 요청 사유',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            if (_lastPreviewMessage.isNotEmpty) ...[
              const SizedBox(height: 12),
              _InlineNotice(
                backgroundColor: const Color(0xFFF0FDF4),
                borderColor: const Color(0xFF86EFAC),
                textColor: const Color(0xFF166534),
                icon: Icons.check_circle_outline,
                message: _lastPreviewMessage,
              ),
              if (_lastResolvedCategories.isNotEmpty) ...[
                const SizedBox(height: 12),
                Panel(
                  title: '해석된 분류 코드',
                  child: Column(
                    children: [
                      _InfoRow(
                        label: '대분류',
                        value: _categoryDisplayValue(
                          _lastResolvedCategories['major_category']?.toString(),
                          _lastResolvedCategories['major_code']?.toString(),
                        ),
                      ),
                      _InfoRow(
                        label: '중분류',
                        value: _categoryDisplayValue(
                          _lastResolvedCategories['middle_category']
                              ?.toString(),
                          (_lastResolvedCategories['middle_code_full'] ??
                                  _lastResolvedCategories['middle_code'])
                              ?.toString(),
                        ),
                      ),
                      _InfoRow(
                        label: '소분류',
                        value: _categoryDisplayValue(
                          _lastResolvedCategories['minor_category']?.toString(),
                          (_lastResolvedCategories['minor_code_full'] ??
                                  _lastResolvedCategories['minor_code'])
                              ?.toString(),
                        ),
                      ),
                      if (_lastPreviewSavedCode.isNotEmpty)
                        _InfoRow(label: '저장 코드', value: _lastPreviewSavedCode),
                    ],
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
            if (_statusMessage.isNotEmpty) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(minHeight: 3),
              const SizedBox(height: 8),
              Text(
                _statusMessage,
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
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
              const Text(
                '모바일에서는 신규 상품을 실제 등록하지 않습니다. 실제 실행은 웹 관리자 화면을 이용하세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF92400E)),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: isBusy ? null : () => _submit(execute: false),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: Text(isBusy ? '처리 중...' : '미리보기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _categoryDisplayValue(String? name, String? code) {
  final normalizedName = (name ?? '').trim();
  final normalizedCode = (code ?? '').trim();
  if (normalizedName.isEmpty && normalizedCode.isEmpty) return '-';
  if (normalizedCode.isEmpty) return normalizedName;
  if (normalizedName.isEmpty) return normalizedCode;
  return '$normalizedName ($normalizedCode)';
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
    final canEdit = appState.hasOperatorAccess;

    return Scaffold(
      appBar: AppBar(
        title: Text(e.itemName),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE2E8F0)),
        ),
        actions: [
          if (canEdit)
            IconButton(
              tooltip: '항목 편집',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _showStatusSheet(e),
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
                      value: e.categoryHint.isEmpty ? '-' : e.categoryHint),
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
      final body = <String, dynamic>{'status': _selectedStatus};
      if (_newTargetPrice != null) body['target_price'] = _newTargetPrice;
      await widget.appState.postJson(
        '/api/menu-workspace/entries/${widget.entry.id}',
        body: body,
        method: 'PATCH',
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        widget.entry.copyWith(
          status: _selectedStatus,
          targetPrice: _newTargetPrice,
        ),
      );
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
    const statuses = ['draft', 'reviewed', 'ready', 'done', 'archived'];
    const labels = ['작성중', '검토됨', '준비완료', '완료', '보관'];

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
