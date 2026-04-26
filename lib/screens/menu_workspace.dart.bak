import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/menu_workspace_models.dart';
import '../state/app_state.dart';
import '../widgets/cache_notice.dart';
import '../widgets/empty_state.dart';
import '../widgets/panel.dart';
import '../widgets/stat_card.dart';

class MenuWorkspaceScreen extends StatefulWidget {
  const MenuWorkspaceScreen({super.key});

  @override
  State<MenuWorkspaceScreen> createState() => _MenuWorkspaceScreenState();
}

class _MenuWorkspaceScreenState extends State<MenuWorkspaceScreen> {
  WorkspaceSnapshot? _snapshot;
  bool _isLoading = true;
  String _error = '';
  bool _fromCache = false;
  DateTime? _cachedAt;
  String _filterStatus = 'all';
  String _filterKind = 'all';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final appState = context.read<AppState>();
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final response = await appState.fetchMapParsed(
        '/api/menu-workspace',
        parser: WorkspaceSnapshot.fromJson,
        cacheTtl: const Duration(minutes: 5),
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
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return EmptyState(
        title: '메뉴 워크스페이스를 불러오지 못했습니다.',
        message: _error,
        action: FilledButton(onPressed: _load, child: const Text('다시 시도')),
      );
    }

    final snapshot = _snapshot;
    if (snapshot == null) {
      return EmptyState(
        title: '데이터 없음',
        action: FilledButton(onPressed: _load, child: const Text('새로고침')),
      );
    }

    final entries = _filteredEntries;
    final s = snapshot.summary;
    final appState = context.watch<AppState>();
    final hasReady = (snapshot.statusCounts['ready'] ?? 0) > 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: appState.hasOperatorAccess
          ? FloatingActionButton.extended(
              onPressed: () => _showPriceChangeSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('가격변경 등록'),
              backgroundColor: const Color(0xFF0D9488),
              foregroundColor: Colors.white,
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
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
                          accent: true,
                        ),
                        StatCard(
                          label: '적용 준비',
                          value: '${s.readyCount}개',
                        ),
                        StatCard(
                          label: '신규 등록',
                          value: '${s.newItemCount}개',
                        ),
                        StatCard(
                          label: '가격 변동 합계',
                          value: _wonSigned(s.priceDeltaTotal),
                        ),
                      ],
                    ),
                    if (hasReady && appState.hasOperatorAccess) ...[  
                      const SizedBox(height: 12),
                      _ApplyReadyBanner(onApplied: _load),
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
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                sliver: SliverList.separated(
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    return _MenuEntryCard(
                      entry: entries[index],
                      onTap: () => _showEntryDetail(context, entries[index]),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showEntryDetail(BuildContext context, MenuEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MenuEntryDetailScreen(entry: entry, onUpdated: _load),
      ),
    );
  }

  void _showPriceChangeSheet(BuildContext context) {
    final appState = context.read<AppState>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PriceChangeCreateSheet(
        appState: appState,
        onCreated: () {
          Navigator.of(context).pop();
          _load();
        },
      ),
    );
  }
}

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
          _FilterChip(label: '전체', value: 'all', groupValue: filterStatus, onSelected: onStatusChanged),
          const SizedBox(width: 6),
          _FilterChip(label: '작성중', value: 'draft', groupValue: filterStatus, onSelected: onStatusChanged),
          const SizedBox(width: 6),
          _FilterChip(label: '검토됨', value: 'reviewed', groupValue: filterStatus, onSelected: onStatusChanged),
          const SizedBox(width: 6),
          _FilterChip(label: '준비완료', value: 'ready', groupValue: filterStatus, onSelected: onStatusChanged),
          const SizedBox(width: 6),
          _FilterChip(label: '완료', value: 'done', groupValue: filterStatus, onSelected: onStatusChanged),
          const SizedBox(width: 16),
          _FilterChip(label: '전체 종류', value: 'all', groupValue: filterKind, onSelected: onKindChanged),
          const SizedBox(width: 6),
          _FilterChip(label: '가격변경', value: 'price_update', groupValue: filterKind, onSelected: onKindChanged),
          const SizedBox(width: 6),
          _FilterChip(label: '신규등록', value: 'new_item', groupValue: filterKind, onSelected: onKindChanged),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String groupValue;
  final ValueChanged<String> onSelected;

  const _FilterChip({
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

class _MenuEntryCard extends StatelessWidget {
  final MenuEntry entry;
  final VoidCallback onTap;

  const _MenuEntryCard({required this.entry, required this.onTap});

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
            Expanded(child: Text(e.itemName, style: const TextStyle(fontWeight: FontWeight.w700))),
            _KindBadge(kind: e.kind),
          ],
        ),
        subtitle: Text(
          e.itemCode.isEmpty ? e.categoryHint : '${e.itemCode}${e.categoryHint.isNotEmpty ? ' · ${e.categoryHint}' : ''}',
        ),
        trailing: e.kind == 'price_update' && e.targetPrice != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '→ ${_won(e.targetPrice!)}원',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (e.currentPrice != null)
                    Text(
                      _wonSigned(e.priceDelta),
                      style: TextStyle(
                        fontSize: 11,
                        color: e.priceDelta >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                      ),
                    ),
                ],
              )
            : null,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      'draft'    => (const Color(0xFF64748B), '작성'),
      'reviewed' => (const Color(0xFF2563EB), '검토'),
      'ready'    => (const Color(0xFF0D9488), '준비'),
      'done'     => (const Color(0xFF16A34A), '완료'),
      _          => (const Color(0xFF94A3B8), status),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
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
      'new_item'     => '신규',
      _              => kind,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
    );
  }
}

// ─── Entry Detail Screen ──────────────────────────────────────────────────────

class MenuEntryDetailScreen extends StatelessWidget {
  final MenuEntry entry;
  final VoidCallback? onUpdated;

  const MenuEntryDetailScreen({super.key, required this.entry, this.onUpdated});

  @override
  Widget build(BuildContext context) {
    final e = entry;
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
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _showStatusSheet(context, e),
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
                  _InfoRow(label: '품목코드', value: e.itemCode.isEmpty ? '-' : e.itemCode),
                  _InfoRow(label: '분류', value: e.categoryHint.isEmpty ? '-' : e.categoryHint),
                  _InfoRow(label: '상태', value: _statusLabel(e.status)),
                  _InfoRow(label: '종류', value: _kindLabel(e.kind)),
                  _InfoRow(label: '출처', value: e.source.isEmpty ? '-' : e.source),
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
                      value: e.currentPrice == null ? '-' : '${_won(e.currentPrice!)}원',
                    ),
                    _InfoRow(
                      label: '목표 가격',
                      value: e.targetPrice == null ? '-' : '${_won(e.targetPrice!)}원',
                    ),
                    _InfoRow(
                      label: '변동',
                      value: e.targetPrice == null ? '-' : '${_wonSigned(e.priceDelta)}원',
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

  void _showStatusSheet(BuildContext context, MenuEntry e) {
    final appState = context.read<AppState>();
    showModalBottomSheet(
      context: context,
      builder: (_) => _StatusUpdateSheet(
        entry: e,
        appState: appState,
        onUpdated: () {
          Navigator.of(context).pop();
          onUpdated?.call();
        },
      ),
    );
  }
}

class _StatusUpdateSheet extends StatefulWidget {
  final MenuEntry entry;
  final AppState appState;
  final VoidCallback onUpdated;

  const _StatusUpdateSheet({
    required this.entry,
    required this.appState,
    required this.onUpdated,
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
        (_newTargetPrice == null || _newTargetPrice == widget.entry.targetPrice)) {
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
      widget.onUpdated();
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
    const statuses = ['draft', 'reviewed', 'ready', 'done'];
    const labels = ['작성중', '검토됨', '준비완료', '완료'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '상태 변경: ${widget.entry.itemName}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 16),
          RadioGroup<String>(
            groupValue: _selectedStatus,
            onChanged: (v) => setState(() => _selectedStatus = v!),
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
                isDense: true,
              ),
              onChanged: (v) {
                final parsed = int.tryParse(v.replaceAll(',', ''));
                setState(() => _newTargetPrice = parsed);
              },
            ),
          ],
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_error, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: Text(_isSubmitting ? '저장 중...' : '저장'),
          ),
        ],
      ),
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

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
            child: Text(label, style: const TextStyle(color: Color(0xFF64748B))),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

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
          children: cards.map((c) => SizedBox(width: width, child: c)).toList(growable: false),
        );
      },
    );
  }
}

String _statusLabel(String s) => switch (s) {
      'draft'    => '작성중',
      'reviewed' => '검토됨',
      'ready'    => '준비완료',
      'done'     => '완료',
      _          => s,
    };

String _kindLabel(String k) => switch (k) {
      'price_update' => '가격 변경',
      'new_item'     => '신규 등록',
      _              => k,
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

// ─── Apply-Ready Banner ───────────────────────────────────────────────────────

class _ApplyReadyBanner extends StatefulWidget {
  final VoidCallback onApplied;
  const _ApplyReadyBanner({required this.onApplied});

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
      final applied = result['applied_count'] ?? result['count'] ?? '?';
      final skipped = result['skipped_count'] ?? result['skipped'] ?? 0;
      messenger.showSnackBar(SnackBar(
        content: Text(execute
            ? '$applied건 가격 적용 완료${skipped > 0 ? ', $skipped건 건너뜀' : ''}'
            : '[미리보기] $applied건 적용 예정${skipped > 0 ? ', $skipped건 건너뜀' : ''}'),
      ));
      if (execute) widget.onApplied();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('오류: $e')));
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
      child: Row(
        children: [
          const Icon(Icons.rocket_launch_outlined, color: Color(0xFF0D9488), size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '준비완료 항목이 있습니다.',
              style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
            ),
          ),
          OutlinedButton(
            onPressed: _isApplying ? null : () => _apply(execute: false),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('미리보기'),
          ),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: _isApplying ? null : () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('가격 적용'),
                  content: const Text('준비완료 상태의 가격변경 항목을 POS에 실제 반영합니다.\n계속하시겠습니까?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('취소')),
                    FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('적용')),
                  ],
                ),
              );
              if (confirmed == true) _apply(execute: true);
            },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              backgroundColor: const Color(0xFF0D9488),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(_isApplying ? '적용 중...' : 'POS 적용'),
          ),
        ],
      ),
    );
  }
}

// ─── Price Change Create Sheet ────────────────────────────────────────────────

class _PriceChangeCreateSheet extends StatefulWidget {
  final AppState appState;
  final VoidCallback onCreated;
  const _PriceChangeCreateSheet({required this.appState, required this.onCreated});

  @override
  State<_PriceChangeCreateSheet> createState() => _PriceChangeCreateSheetState();
}

class _PriceChangeCreateSheetState extends State<_PriceChangeCreateSheet> {
  final _itemNameController = TextEditingController();
  final _itemCodeController = TextEditingController();
  final _currentPriceController = TextEditingController();
  final _targetPriceController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isSubmitting = false;
  String _error = '';

  @override
  void dispose() {
    _itemNameController.dispose();
    _itemCodeController.dispose();
    _currentPriceController.dispose();
    _targetPriceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _itemNameController.text.trim();
    final targetText = _targetPriceController.text.replaceAll(',', '');
    final targetPrice = int.tryParse(targetText);

    if (name.isEmpty) {
      setState(() => _error = '품목명을 입력하세요.');
      return;
    }
    if (targetPrice == null || targetPrice < 0) {
      setState(() => _error = '목표 가격을 올바르게 입력하세요.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = '';
    });

    try {
      final body = <String, dynamic>{
        'item_name': name,
        'target_price': targetPrice,
      };
      final code = _itemCodeController.text.trim();
      if (code.isNotEmpty) body['item_code'] = code;
      final currentText = _currentPriceController.text.replaceAll(',', '');
      final currentPrice = int.tryParse(currentText);
      if (currentPrice != null) body['current_price'] = currentPrice;
      final notes = _notesController.text.trim();
      if (notes.isNotEmpty) body['notes'] = notes;

      await widget.appState.postJson('/api/menu-workspace/price-change', body: body);
      if (!mounted) return;
      widget.onCreated();
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
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16, 20, 16,
        MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '가격변경 항목 등록',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _itemNameController,
              decoration: const InputDecoration(
                labelText: '품목명 *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _itemCodeController,
              decoration: const InputDecoration(
                labelText: '품목코드 (선택)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _currentPriceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '현재 가격 (선택)',
                      suffixText: '원',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _targetPriceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '목표 가격 *',
                      suffixText: '원',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: '메모 (선택)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_error, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
              child: Text(_isSubmitting ? '등록 중...' : '등록'),
            ),
          ],
        ),
      ),
    );
  }
}

