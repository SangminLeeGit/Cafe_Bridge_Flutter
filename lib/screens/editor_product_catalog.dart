import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/async_request_guard.dart';
import '../models/editor_context.dart';
import '../models/editor_product_catalog.dart';
import '../state/app_state.dart';
import '../widgets/empty_state.dart';

/// Read-only, cursor-paginated browser for the server's editor product catalog.
class EditorProductCatalogScreen extends StatefulWidget {
  const EditorProductCatalogScreen({super.key});

  @override
  State<EditorProductCatalogScreen> createState() =>
      _EditorProductCatalogScreenState();
}

class _EditorProductCatalogScreenState extends State<EditorProductCatalogScreen>
    with AsyncRequestGuard<EditorProductCatalogScreen> {
  final TextEditingController _queryController = TextEditingController();
  List<EditorCatalogProduct> _products = const [];
  String _scopeId = '';
  String _query = '';
  String? _nextCursor;
  String _queryKey = '';
  int? _generation;
  int _totalCount = 0;
  int _filteredCount = 0;
  String _source = '';
  String? _syncedAt;
  bool _complete = false;
  bool _loading = true;
  bool _loadingMore = false;
  String _error = '';
  String _loadMoreError = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadFirstPage());
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _loadFirstPage() async {
    if (!mounted) return;
    final request = beginAsyncRequest();
    final query = _queryController.text.trim();
    final appState = context.read<AppState>();
    setState(() {
      _query = query;
      _products = const [];
      _scopeId = '';
      _nextCursor = null;
      _queryKey = '';
      _generation = null;
      _totalCount = 0;
      _filteredCount = 0;
      _source = '';
      _syncedAt = null;
      _complete = false;
      _loading = true;
      _loadingMore = false;
      _error = '';
      _loadMoreError = '';
    });

    try {
      final contextResult = await appState.fetchMapParsed<EditorContext>(
        '/api/editor/context',
        parser: EditorContext.fromJson,
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      if (!isCurrentAsyncRequest(request)) return;
      final capability = contextResult.data.capability('browse_products');
      if (capability == null || !capability.enabled) {
        final message = capability?.message.trim() ?? '';
        throw StateError(
            message.isNotEmpty ? message : '서버에서 상품 카탈로그 조회 권한을 확인할 수 없습니다.');
      }

      final response = await appState.fetchMapParsed<EditorProductCatalogPage>(
        '/api/editor/products',
        params: editorProductFirstPageParams(query),
        parser: EditorProductCatalogPage.fromJson,
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      if (!isCurrentAsyncRequest(request)) return;
      if (response.data.scopeId != contextResult.data.scopeId) {
        throw const FormatException('상품 카탈로그의 편집 범위가 현재 세션과 다릅니다.');
      }
      _applyFirstPage(response.data);
    } catch (error) {
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _error = error.toString().replaceFirst('Bad state: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    final generation = _generation;
    if (!mounted ||
        _loading ||
        _loadingMore ||
        cursor == null ||
        generation == null) {
      return;
    }
    final request = beginAsyncRequest();
    final appState = context.read<AppState>();
    setState(() {
      _loadingMore = true;
      _loadMoreError = '';
    });
    try {
      final response = await appState.fetchMapParsed<EditorProductCatalogPage>(
        '/api/editor/products',
        params: editorProductNextPageParams(
          query: _query,
          cursor: cursor,
          generation: generation,
          queryKey: _queryKey,
        ),
        parser: EditorProductCatalogPage.fromJson,
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      if (!isCurrentAsyncRequest(request)) return;
      final page = response.data;
      if (page.scopeId != _scopeId ||
          page.generation != generation ||
          page.queryKey != _queryKey) {
        throw const FormatException(
          '상품 목록의 검색 버전이 바뀌었습니다. 처음부터 다시 조회해 주세요.',
        );
      }
      setState(() {
        _products = _appendUniqueProducts(_products, page.rows);
        _nextCursor = page.nextCursor;
        _totalCount = page.totalCount;
        _filteredCount = page.filteredCount;
        _source = page.source;
        _syncedAt = page.syncedAt;
        _complete = page.complete;
        _loadingMore = false;
      });
    } catch (error) {
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _loadMoreError = error.toString().replaceFirst('Exception: ', '');
        _loadingMore = false;
      });
    }
  }

  static List<EditorCatalogProduct> _appendUniqueProducts(
    List<EditorCatalogProduct> existing,
    List<EditorCatalogProduct> next,
  ) {
    final seen = existing.map((item) => item.code).toSet();
    return [
      ...existing,
      ...next.where((item) => item.code.isEmpty || seen.add(item.code)),
    ];
  }

  void _applyFirstPage(EditorProductCatalogPage page) {
    setState(() {
      _products = page.rows;
      _scopeId = page.scopeId;
      _nextCursor = page.nextCursor;
      _queryKey = page.queryKey;
      _generation = page.generation;
      _totalCount = page.totalCount;
      _filteredCount = page.filteredCount;
      _source = page.source;
      _syncedAt = page.syncedAt;
      _complete = page.complete;
      _loading = false;
      _error = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('상품 카탈로그 탐색'),
        actions: [
          IconButton(
            tooltip: '처음부터 다시 조회',
            onPressed: _loading ? null : _loadFirstPage,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _queryController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => unawaited(_loadFirstPage()),
                    decoration: InputDecoration(
                      labelText: '상품명, 코드, 분류 검색',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        tooltip: '검색',
                        onPressed: _loading ? null : _loadFirstPage,
                        icon: const Icon(Icons.arrow_forward),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '서버 동기화 카탈로그의 읽기 전용 조회입니다. POS에 변경을 적용하지 않습니다.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ),
                ],
              ),
            ),
            if (!_loading && _error.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$_filteredCount / $_totalCount개 · ${_source.isEmpty ? '원본 정보 없음' : _source.toUpperCase()}${_syncedAt == null ? '' : ' · 기준 $_syncedAt'}${_complete ? '' : ' · 전체 동기화 미확인'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
            Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_loading && _products.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return EmptyState(
        title: '상품 카탈로그를 불러오지 못했습니다.',
        message: _error,
        action: FilledButton(
          onPressed: _loadFirstPage,
          child: const Text('다시 조회'),
        ),
      );
    }
    if (_products.isEmpty) {
      return EmptyState(
        title: '검색 결과가 없습니다.',
        action: FilledButton(
          onPressed: _loadFirstPage,
          child: const Text('다시 조회'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _products.length + (_nextCursor == null ? 0 : 1),
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          if (index == _products.length) {
            if (_loadMoreError.isNotEmpty) {
              return Column(
                children: [
                  Text(
                    _loadMoreError,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFB91C1C)),
                  ),
                  TextButton.icon(
                    onPressed: _loadingMore ? null : _loadFirstPage,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('처음부터 다시 조회'),
                  ),
                ],
              );
            }
            return Center(
              child: OutlinedButton.icon(
                onPressed: _loadingMore ? null : _loadMore,
                icon: _loadingMore
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more),
                label: Text(_loadingMore ? '불러오는 중...' : '다음 50개 불러오기'),
              ),
            );
          }
          final product = _products[index];
          return Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              title: Text(
                product.name.isEmpty ? '이름 없음' : product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text([
                if (product.code.isNotEmpty) '코드 ${product.code}',
                if (product.category.isNotEmpty) product.category,
              ].join(' · ')),
              trailing: product.price == null
                  ? const Text('-')
                  : Text('${_formatPrice(product.price!)}원'),
            ),
          );
        },
      ),
    );
  }

  static String _formatPrice(int value) => value.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
}
