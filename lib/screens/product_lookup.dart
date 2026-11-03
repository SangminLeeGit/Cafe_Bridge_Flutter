import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/async_request_guard.dart';
import '../models/api_contracts.dart';
import '../models/product_identity.dart';
import '../navigation/app_navigation.dart';
import '../state/app_state.dart';
import '../widgets/access_gate.dart';
import '../widgets/panel.dart';
import 'editor_product_catalog.dart';
import 'price_apply.dart';

export '../models/product_identity.dart' show normalizeProductCode;

class ProductLookupItem {
  final Map<String, dynamic> raw;
  final String code;
  final String name;
  final int? salePrice;
  final String category;

  const ProductLookupItem({
    required this.raw,
    required this.code,
    required this.name,
    required this.salePrice,
    required this.category,
  });

  factory ProductLookupItem.fromJson(Map<String, dynamic> json) {
    final identity = ProductIdentity.fromRegistrationJson(json);
    return ProductLookupItem(
      raw: Map<String, dynamic>.from(json),
      code: identity.code,
      name: identity.name,
      salePrice: identity.salePrice,
      category: identity.category,
    );
  }
}

class ProductLookupData {
  final List<ProductLookupItem> rows;
  final int totalCount;
  final int filteredCount;
  final int limit;
  final bool complete;
  final String lastVerifiedAt;
  final String lastFullSnapshotAt;
  final String lastChangedAt;
  final int? generation;
  final String source;
  final String syncedAt;

  const ProductLookupData({
    required this.rows,
    required this.totalCount,
    required this.filteredCount,
    required this.limit,
    required this.complete,
    required this.lastVerifiedAt,
    required this.lastFullSnapshotAt,
    required this.lastChangedAt,
    required this.generation,
    required this.source,
    required this.syncedAt,
  });

  factory ProductLookupData.fromJson(Map<String, dynamic> json) {
    return ProductLookupData(
      rows: requireListOfMaps(json, 'rows')
          .map(ProductLookupItem.fromJson)
          .toList(growable: false),
      totalCount: asInt(json['total_count']),
      filteredCount: asInt(json['filtered_count']),
      limit: asInt(json['limit']),
      complete: json['complete'] == true,
      lastVerifiedAt: asString(json['last_verified_at']),
      lastFullSnapshotAt: asString(json['last_full_snapshot_at']),
      lastChangedAt: asString(json['last_changed_at']),
      generation: asNullableInt(json['generation']),
      source: asString(json['source']),
      syncedAt: asString(json['synced_at']),
    );
  }
}

class ProductLookupScreen extends StatefulWidget {
  const ProductLookupScreen({super.key});

  @override
  State<ProductLookupScreen> createState() => _ProductLookupScreenState();
}

class _ProductLookupScreenState extends State<ProductLookupScreen>
    with AsyncRequestGuard<ProductLookupScreen> {
  final _searchController = TextEditingController();
  ProductLookupData? _data;
  bool _loading = true;
  String _error = '';
  int _limit = 100;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (!mounted) return;
    final request = beginAsyncRequest();
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final response =
          await context.read<AppState>().fetchMapParsed<Map<String, dynamic>>(
                '/api/products/registration',
                params: {
                  'query': _searchController.text.trim(),
                  'limit': '$_limit',
                  'compact': 'false',
                  'refresh': refresh ? 'true' : 'false',
                  'cache_only': 'false',
                },
                parser: (json) => json,
                cacheTtl: refresh ? Duration.zero : const Duration(minutes: 10),
              );
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _data = ProductLookupData.fromJson(response.data);
        _loading = false;
      });
    } catch (error) {
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _openDetail(ProductLookupItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccessGate(
          minimumRole: UserRole.viewer,
          fullScreen: true,
          child: _ProductLookupDetailScreen(item: item),
        ),
      ),
    );
  }

  void _openPriceChange(ProductLookupItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccessGate(
          minimumRole: UserRole.operator,
          fullScreen: true,
          child: PriceApplyScreen(
            initialProductCode: item.code,
            initialItemName: item.name,
            initialCurrentPrice: item.salePrice,
            lockProductCode: true,
          ),
        ),
      ),
    );
  }

  void _openCatalog() {
    AppNavigation.pushGuarded(
      context,
      minimumRole: UserRole.viewer,
      child: const EditorProductCatalogScreen(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canChangePrice = context.watch<AppState>().hasOperatorAccess;
    final data = _data;
    final items = data?.rows ?? const <ProductLookupItem>[];
    final isTruncated = data != null && data.filteredCount > items.length;
    return AccessGate(
      minimumRole: UserRole.viewer,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final search = TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _load(),
                  decoration: InputDecoration(
                    labelText: '상품명 또는 상품코드',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: '검색',
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.arrow_forward),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                );
                final limit = DropdownButtonFormField<int>(
                  initialValue: _limit,
                  decoration: const InputDecoration(
                    labelText: '표시 개수',
                    border: OutlineInputBorder(),
                  ),
                  items: const [50, 100, 200]
                      .map((value) => DropdownMenuItem(
                            value: value,
                            child: Text('$value개'),
                          ))
                      .toList(growable: false),
                  onChanged: _loading
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _limit = value);
                          unawaited(_load());
                        },
                );
                if (constraints.maxWidth < 520) {
                  return Column(
                    children: [
                      search,
                      const SizedBox(height: 10),
                      limit,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: 12),
                    SizedBox(width: 140, child: limit),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _openCatalog,
                icon: const Icon(Icons.manage_search),
                label: const Text('페이지형 카탈로그 탐색'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '표시 ${_formatNumber(items.length)} / 검색 ${_formatNumber(data?.filteredCount ?? 0)} / 전체 ${_formatNumber(data?.totalCount ?? 0)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _loading ? null : () => _load(refresh: true),
                      tooltip: '새로고침',
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                if (data != null) ...[
                  Text(
                    '${data.source.isEmpty ? '' : '${data.source.toUpperCase()} · '}${data.syncedAt.isEmpty ? '동기화 시각 미제공' : '동기화 $data.syncedAt'} · 조회 한도 ${_formatNumber(data.limit)}개',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text(
                        data.complete ? '전체 스냅샷 완료' : '전체 스냅샷 불완전',
                        style: TextStyle(
                          color: data.complete
                              ? const Color(0xFF15803D)
                              : const Color(0xFFB45309),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        'generation ${data.generation == null ? '-' : _formatNumber(data.generation!)}',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '최종 검증 ${_metadataValue(data.lastVerifiedAt)}',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '전체 스냅샷 ${_metadataValue(data.lastFullSnapshotAt)}',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '최종 변경 ${_metadataValue(data.lastChangedAt)}',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  if (isTruncated) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '검색 결과 ${_formatNumber(data.filteredCount)}개 중 ${_formatNumber(items.length)}개만 표시 중입니다.',
                            style: const TextStyle(
                              color: Color(0xFF92400E),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _openCatalog,
                            icon: const Icon(Icons.manage_search),
                            label: const Text('페이지형 카탈로그로 전체 탐색'),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              alignment: Alignment.centerLeft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error.isNotEmpty
                    ? _LookupMessage(
                        message: _error,
                        action: () => _load(),
                      )
                    : items.isEmpty
                        ? const _LookupMessage(message: '검색 결과가 없습니다.')
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return Card(
                                margin: EdgeInsets.zero,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _openDetail(item),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name.isEmpty
                                              ? '이름 없음'
                                              : item.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            _CodeChip(code: item.code),
                                            if (item.salePrice != null)
                                              Text(
                                                '${_formatNumber(item.salePrice!)}원',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            if (item.category.isNotEmpty)
                                              Text(
                                                item.category,
                                                style: const TextStyle(
                                                  color: Color(0xFF64748B),
                                                ),
                                              ),
                                          ],
                                        ),
                                        if (canChangePrice &&
                                            item.code.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: TextButton.icon(
                                              onPressed: () =>
                                                  _openPriceChange(item),
                                              icon: const Icon(
                                                Icons.price_change_outlined,
                                              ),
                                              label: const Text('가격 변경'),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _ProductLookupDetailScreen extends StatefulWidget {
  final ProductLookupItem item;

  const _ProductLookupDetailScreen({required this.item});

  @override
  State<_ProductLookupDetailScreen> createState() =>
      _ProductLookupDetailScreenState();
}

class _ProductLookupDetailScreenState extends State<_ProductLookupDetailScreen>
    with AsyncRequestGuard<_ProductLookupDetailScreen> {
  Map<String, dynamic>? _row;
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final request = beginAsyncRequest();
    if (widget.item.code.isEmpty) {
      setState(() {
        _loading = false;
        _error = '상품코드가 없어 상세 정보를 조회할 수 없습니다.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final response =
          await context.read<AppState>().fetchMapParsed<Map<String, dynamic>>(
                '/api/products/registration/${Uri.encodeComponent(widget.item.code)}',
                params: const {'compact': 'false'},
                parser: (json) => json,
                cacheTtl: const Duration(minutes: 10),
              );
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _row = response.data['row'] is Map
            ? Map<String, dynamic>.from(response.data['row'] as Map)
            : widget.item.raw;
        _loading = false;
      });
    } catch (error) {
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = _row ?? widget.item.raw;
    final fields = row.entries
        .where(
            (entry) => entry.value != null && entry.value.toString().isNotEmpty)
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: const Text('상품 상세'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Panel(
                    title:
                        widget.item.name.isEmpty ? '이름 없음' : widget.item.name,
                    subtitle: '상품코드 ${widget.item.code}',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _CodeChip(code: widget.item.code),
                        if (widget.item.salePrice != null)
                          Chip(
                            label: Text(
                              '판매가 ${_formatNumber(widget.item.salePrice!)}원',
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error,
                      style: const TextStyle(color: Color(0xFFDC2626)),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Panel(
                    title: '등록 정보',
                    child: Column(
                      children: fields
                          .map((entry) => _DetailRow(
                                label: entry.key,
                                value: entry.value.toString(),
                              ))
                          .toList(growable: false),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CodeChip extends StatelessWidget {
  final String code;

  const _CodeChip({required this.code});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.tag, size: 16),
      label: Text(code.isEmpty ? '코드 없음' : code),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _LookupMessage extends StatelessWidget {
  final String message;
  final VoidCallback? action;

  const _LookupMessage({required this.message, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: action, child: const Text('다시 시도')),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatNumber(int value) {
  final text = value.toString();
  return text.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
}

String _metadataValue(String value) => value.isEmpty ? '미기록' : value;
