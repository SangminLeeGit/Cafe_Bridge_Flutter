import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/async_request_guard.dart';
import '../models/touchkey_models.dart';
import '../state/app_state.dart';
import '../widgets/empty_state.dart';
import '../widgets/panel.dart';
import '../widgets/responsive_wrap_grid.dart';
import '../widgets/stat_card.dart';

class TouchkeyScreen extends StatefulWidget {
  const TouchkeyScreen({super.key});

  @override
  State<TouchkeyScreen> createState() => _TouchkeyScreenState();
}

class _TouchkeyScreenState extends State<TouchkeyScreen>
    with AsyncRequestGuard<TouchkeyScreen> {
  TouchkeyPayload? _data;
  bool _isLoading = false;
  String _error = '';
  _TouchkeyViewMode _viewMode = _TouchkeyViewMode.map;
  final Map<String, TouchkeyPayload> _touchkeyCache =
      <String, TouchkeyPayload>{};

  String _touchkeyCacheKey(
    String programKey, [
    Map<String, String>? selectedClass,
  ]) {
    final normalizedProgram = programKey.trim().toLowerCase();
    final classCode = (selectedClass?['분류코드'] ?? '').trim();
    final sortValue = (selectedClass?['순번'] ?? '').trim();
    return '$normalizedProgram::$classCode::$sortValue';
  }

  void _storeTouchkeyCache(
    TouchkeyPayload payload, {
    required String requestedProgramKey,
    Map<String, String>? requestedClass,
  }) {
    final normalizedProgram = requestedProgramKey.trim().toLowerCase();
    _touchkeyCache[_touchkeyCacheKey(normalizedProgram, requestedClass)] =
        payload;

    final selectedClass = <String, String>{
      '분류코드': payload.selectedClass['분류코드']?.toString().trim() ?? '',
      '순번': payload.selectedClass['순번']?.toString().trim() ?? '',
    };
    if (selectedClass['분류코드']!.isNotEmpty || selectedClass['순번']!.isNotEmpty) {
      _touchkeyCache[_touchkeyCacheKey(normalizedProgram, selectedClass)] =
          payload;
    }
  }

  Future<void> _load([
    Map<String, String>? selectedClass,
  ]) async {
    if (!mounted) return;
    final request = beginAsyncRequest();
    const nextProgram = 'touchkey';
    final cachedPayload =
        _touchkeyCache[_touchkeyCacheKey(nextProgram, selectedClass)];
    if (cachedPayload != null) {
      setState(() {
        _data = cachedPayload;
        _isLoading = false;
        _error = '';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final response =
          await context.read<AppState>().fetchMapParsed<TouchkeyPayload>(
                '/api/menu-engineering/touchkey-tables',
                params: {
                  'program': nextProgram,
                  'row_limit': 120,
                  if ((selectedClass?['분류코드'] ?? '').trim().isNotEmpty)
                    'class_code': selectedClass!['분류코드']!.trim(),
                  if ((selectedClass?['순번'] ?? '').trim().isNotEmpty)
                    'sort_value': selectedClass!['순번']!.trim(),
                },
                parser: TouchkeyPayload.fromJson,
                cacheTtl: Duration.zero,
                allowStaleOnError: false,
              );
      if (!isCurrentAsyncRequest(request)) {
        return;
      }
      _storeTouchkeyCache(
        response.data,
        requestedProgramKey: nextProgram,
        requestedClass: selectedClass,
      );
      setState(() {
        _data = response.data;
      });
    } catch (error) {
      if (!isCurrentAsyncRequest(request)) {
        return;
      }
      setState(() {
        _data = null;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (isCurrentAsyncRequest(request)) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('터치키 구조 탐색',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : () => _load(),
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE2E8F0)),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _TouchkeyHeader(),
            const SizedBox(height: 16),
            if (_error.isNotEmpty)
              EmptyState(
                title: '터치키 데이터를 불러오지 못했습니다.',
                message: _error,
                action: FilledButton(
                  onPressed: _isLoading ? null : () => _load(),
                  child: const Text('다시 시도'),
                ),
              ),
            if (_isLoading && data == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (data != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ModeChip(
                    label: 'POS 맵',
                    selected: _viewMode == _TouchkeyViewMode.map,
                    onTap: () {
                      setState(() {
                        _viewMode = _TouchkeyViewMode.map;
                      });
                    },
                  ),
                  _ModeChip(
                    label: '데이터 탐색기',
                    selected: _viewMode == _TouchkeyViewMode.explorer,
                    onTap: () {
                      setState(() {
                        _viewMode = _TouchkeyViewMode.explorer;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_viewMode == _TouchkeyViewMode.map)
                _TouchkeyMapView(
                  data: data,
                  isLoading: _isLoading,
                  onSelectClass: (selectedClass) => _load(selectedClass),
                )
              else
                _TouchkeyExplorerView(data: data),
            ],
          ],
        ),
      ),
    );
  }
}

class _TouchkeyHeader extends StatelessWidget {
  const _TouchkeyHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Touchkey Explorer',
            style: TextStyle(
              color: Color(0xFF0D9488),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '터치키 구조 탐색',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          SizedBox(height: 6),
          Text(
            '키맵과 원본 표를 확인합니다.',
            style: TextStyle(color: Color(0xFF64748B), height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _TouchkeyMapView extends StatefulWidget {
  final TouchkeyPayload data;
  final bool isLoading;
  final ValueChanged<Map<String, String>> onSelectClass;

  const _TouchkeyMapView({
    required this.data,
    required this.isLoading,
    required this.onSelectClass,
  });

  @override
  State<_TouchkeyMapView> createState() => _TouchkeyMapViewState();
}

class _TouchkeyMapViewState extends State<_TouchkeyMapView> {
  int _page = 1;

  @override
  void didUpdateWidget(covariant _TouchkeyMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldClassCode =
        oldWidget.data.selectedClass['분류코드']?.toString().trim();
    final newClassCode = widget.data.selectedClass['분류코드']?.toString().trim();
    final oldSortValue = oldWidget.data.selectedClass['순번']?.toString().trim();
    final newSortValue = widget.data.selectedClass['순번']?.toString().trim();
    if (oldWidget.data.programKey != widget.data.programKey ||
        oldClassCode != newClassCode ||
        oldSortValue != newSortValue) {
      _page = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sourceCodes = widget.data.sources
        .map((source) => source.programCode)
        .where((value) => value.trim().isNotEmpty)
        .join(' + ');
    final renderedSlotTables =
        widget.data.tables.where(_isRenderedSlotTable).toList(growable: false);
    final renderedClassTable = _findRenderedClassSlotTable(renderedSlotTables);
    final renderedProductTable =
        _findRenderedProductSlotTable(renderedSlotTables, renderedClassTable);
    final classTable = _findMatchingTable(widget.data.tables, _isClassTable);
    final productTable =
        _findMatchingTable(widget.data.tables, _isProductTable);
    final slotTable = renderedProductTable;

    final classItems = (classTable?.objectRows.isNotEmpty ?? false)
        ? classTable!.objectRows
        : _parseRenderedClassItems(renderedClassTable);
    final productItems =
        productTable?.objectRows ?? const <Map<String, String>>[];
    final loadedCode =
        widget.data.selectedClass['분류코드']?.toString().trim().isNotEmpty == true
            ? widget.data.selectedClass['분류코드'].toString().trim()
            : (classItems.isEmpty ? '' : (classItems.first['분류코드'] ?? ''));
    final loadedClass = _findClassRow(classItems, loadedCode);
    final scopedProductItems =
        _filterProductItemsByLoadedClass(productItems, loadedCode);
    final slotGrid = _buildSlotGrid(slotTable);
    final allPages = _allPages(scopedProductItems);
    final activePage = allPages.contains(_page) ? _page : allPages.first;
    final datasetGrid = _buildDatasetGrid(scopedProductItems, activePage);
    final gridH = slotGrid == null
        ? _gridSize(
            loadedClass?['터치키H'],
            scopedProductItems
                .map((item) => item['터치키H'])
                .toList(growable: false),
          )
        : (slotTable?.columns ?? const <String>[])
            .where((column) =>
                RegExp(r'^slot_\d+$', caseSensitive: false).hasMatch(column))
            .length;
    final gridV = slotGrid == null
        ? _gridSize(
            loadedClass?['터치키V'],
            scopedProductItems
                .map((item) => item['터치키V'])
                .toList(growable: false),
          )
        : (slotTable?.rows.length ?? 0);
    final activeGrid = slotGrid ?? datasetGrid;

    return Column(
      children: [
        ResponsiveWrapGrid(
          minItemWidth: 220,
          maxColumns: 2,
          children: [
            StatCard(
              label: '프로그램',
              value: widget.data.label.isEmpty
                  ? widget.data.programCode
                  : widget.data.label,
              sub: sourceCodes.isEmpty ? widget.data.programCode : sourceCodes,
              accent: true,
            ),
            StatCard(
              label: '로드 상태',
              value: _loadStatusLabel(widget.data.loadStatus),
              sub: widget.data.description.isEmpty
                  ? '-'
                  : widget.data.description,
            ),
          ],
        ),
        if (widget.data.sources.isNotEmpty ||
            widget.data.sourceErrors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 16),
            child: Column(
              children: [
                if (widget.data.sources.isNotEmpty)
                  ResponsiveWrapGrid(
                    minItemWidth: 220,
                    maxColumns: 2,
                    children: widget.data.sources
                        .map(
                          (source) => StatCard(
                            label: source.programCode,
                            value: source.label.isEmpty ? '-' : source.label,
                            sub:
                                '${_loadStatusLabel(source.loadStatus)} · 그리드 ${source.tableCount}개',
                          ),
                        )
                        .toList(growable: false),
                  ),
                if (widget.data.sourceErrors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color.fromRGBO(220, 38, 38, 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color.fromRGBO(220, 38, 38, 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '일부 소스 로드 실패',
                          style: TextStyle(
                            color: Color(0xFFB91C1C),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final item in widget.data.sourceErrors)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '${item.programCode.isEmpty ? item.label : item.programCode}: ${item.error}',
                              style: const TextStyle(
                                color: Color(0xFFB91C1C),
                                height: 1.4,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          )
        else
          const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF18222A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF243038)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: classItems.map(
                    (item) {
                      final isLoaded = item['분류코드'] == loadedCode;
                      return Container(
                        margin: const EdgeInsets.only(right: 6),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: widget.isLoading || isLoaded
                                ? null
                                : () => widget.onSelectClass(item),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isLoaded
                                    ? const Color(0xFF0D5E55)
                                    : const Color(0xFF243038),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isLoaded
                                      ? const Color(0xFF14B8A6)
                                      : const Color(0xFF2D3E45),
                                ),
                              ),
                              child: Text(
                                item['분류명']?.trim().isNotEmpty == true
                                    ? item['분류명']!
                                    : (item['분류코드'] ?? '-'),
                                style: TextStyle(
                                  color: isLoaded
                                      ? const Color(0xFF99F6E4)
                                      : const Color(0xFF83A1A8),
                                  fontSize: 11,
                                  fontWeight: isLoaded
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ).toList(growable: false),
                ),
              ),
              const SizedBox(height: 10),
              if (gridH <= 0 || gridV <= 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      '그리드 데이터가 없습니다.',
                      style: TextStyle(color: Color(0xFF507870)),
                    ),
                  ),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: gridH * 92,
                    child: GridView.builder(
                      itemCount: gridH * gridV,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: gridH,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                        childAspectRatio: gridH > 6 ? 1.35 : 1.1,
                      ),
                      itemBuilder: (context, index) {
                        final h = (index % gridH) + 1;
                        final v = (index ~/ gridH) + 1;
                        final product = activeGrid['$h-$v'];
                        return _PosSlotCard(product: product);
                      },
                    ),
                  ),
                ),
              if (allPages.length > 1) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children: allPages
                      .map(
                        (page) => OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _page = page;
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            backgroundColor: activePage == page
                                ? const Color(0xFF0D5E55)
                                : const Color(0xFF1A2D32),
                            foregroundColor: activePage == page
                                ? const Color(0xFF99F6E4)
                                : const Color(0xFF7AB8B0),
                            side: BorderSide(
                              color: activePage == page
                                  ? const Color(0xFF14B8A6)
                                  : const Color(0xFF243038),
                            ),
                          ),
                          child: Text('$page'),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '상품 배치됨 / 빈 슬롯 / 현재 로드된 분류',
                      style: TextStyle(fontSize: 11, color: Color(0xFF507870)),
                    ),
                  ),
                  Text(
                    '$gridH × $gridV 그리드 · ${activeGrid.length}개 상품 배치',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF507870),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  static TouchkeyTable? _findMatchingTable(
    List<TouchkeyTable> tables,
    bool Function(TouchkeyTable table) predicate,
  ) {
    for (final table in tables) {
      if (predicate(table)) {
        return table;
      }
    }
    return null;
  }

  static bool _hasColumn(TouchkeyTable table, String column) {
    return table.columns.contains(column);
  }

  static bool _hasAnyColumn(TouchkeyTable table, List<String> columns) {
    return columns.any((column) => _hasColumn(table, column));
  }

  static bool _matchesDatasetHint(TouchkeyTable table, String hint) {
    final candidates = <String>[
      table.binddatasetResolved.trim().toLowerCase(),
      table.binddataset.trim().toLowerCase(),
    ].where((value) => value.isNotEmpty);
    for (final value in candidates) {
      if (value == hint || value.endsWith('.$hint') || value.contains(hint)) {
        return true;
      }
    }
    return false;
  }

  static bool _isRenderedSlotTable(TouchkeyTable table) {
    return table.columns.isNotEmpty &&
        table.columns.every(
          (column) =>
              RegExp(r'^slot_\d+$', caseSensitive: false).hasMatch(column),
        );
  }

  static List<String> _renderedSlotValues(
    TouchkeyTable? table, {
    int? limit,
  }) {
    if (table == null || table.rows.isEmpty) {
      return const <String>[];
    }
    final values = <String>[];
    for (final row in table.rows) {
      for (final cell in row) {
        final value = cell.trim();
        if (value.isEmpty || value == '-') {
          continue;
        }
        values.add(value);
        if (limit != null && values.length >= limit) {
          return values;
        }
      }
    }
    return values;
  }

  static List<String> _splitRenderedSlotValue(String value) {
    return value
        .split(RegExp(r'\r?\n+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  static bool _isRenderedSlotCode(String value) {
    return RegExp(r'^\d+$').hasMatch(value.trim());
  }

  static bool _isRenderedSlotPrice(String value) {
    return normalizeTouchkeyPriceText(value).isNotEmpty;
  }

  static Map<String, String>? _parseRenderedClassSlotValue(String value) {
    final lines = _splitRenderedSlotValue(value);
    if (lines.length < 2 || !_isRenderedSlotCode(lines.first)) {
      return null;
    }
    return <String, String>{
      '분류코드': lines.first,
      '순번': lines.first,
      '분류명': lines.skip(1).join(' '),
    };
  }

  static Map<String, String>? _parseRenderedProductSlotValue(String value) {
    final lines = _splitRenderedSlotValue(value);
    if (lines.isEmpty) {
      return null;
    }
    final code = _isRenderedSlotCode(lines.first) ? lines.first : '';
    final last = lines.last;
    final price = normalizeTouchkeyPriceText(last);
    final hasPrice = price.isNotEmpty;
    final startIndex = code.isNotEmpty ? 1 : 0;
    final endIndex = hasPrice ? lines.length - 1 : lines.length;
    final name = lines.sublist(startIndex, endIndex).join(' ').trim();
    return <String, String>{
      '상품코드': code,
      '상품명': name.isNotEmpty ? name : lines.join(' '),
      '판매가': price,
    };
  }

  static String? _renderedSlotRole(TouchkeyTable table) {
    if (!_isRenderedSlotTable(table)) {
      return null;
    }
    final datasetHints = <String>[
      table.binddatasetResolved.trim().toLowerCase(),
      table.binddataset.trim().toLowerCase(),
    ].where((value) => value.isNotEmpty);
    for (final hint in datasetHints) {
      if (hint == 'dstouchkeyclass' ||
          hint.endsWith('.dstouchkeyclass') ||
          hint.contains('dstouchkeyclass') ||
          hint == 'ds1') {
        return 'class';
      }
      if (hint == 'dstouchkey' ||
          hint.endsWith('.dstouchkey') ||
          hint.contains('dstouchkey') ||
          hint == 'ds2') {
        return 'product';
      }
    }
    final values = _renderedSlotValues(table, limit: 16);
    if (values.any((value) {
      final lines = _splitRenderedSlotValue(value);
      final last = lines.isEmpty ? '' : lines.last;
      return lines.length >= 3 || _isRenderedSlotPrice(last);
    })) {
      return 'product';
    }
    if (values.any((value) => _parseRenderedClassSlotValue(value) != null)) {
      return 'class';
    }
    return null;
  }

  static TouchkeyTable? _findRenderedClassSlotTable(
      List<TouchkeyTable> tables) {
    return _findMatchingTable(
        tables, (table) => _renderedSlotRole(table) == 'class');
  }

  static TouchkeyTable? _findRenderedProductSlotTable(
    List<TouchkeyTable> tables,
    TouchkeyTable? renderedClassTable,
  ) {
    final explicitProduct = _findMatchingTable(
        tables, (table) => _renderedSlotRole(table) == 'product');
    if (explicitProduct != null) {
      return explicitProduct;
    }
    if (tables.length == 1) {
      return tables.first;
    }
    for (final table in tables) {
      if (table != renderedClassTable) {
        return table;
      }
    }
    return null;
  }

  static List<Map<String, String>> _parseRenderedClassItems(
    TouchkeyTable? table,
  ) {
    final items = <Map<String, String>>[];
    final seen = <String>{};
    for (final value in _renderedSlotValues(table)) {
      final parsed = _parseRenderedClassSlotValue(value);
      if (parsed == null) {
        continue;
      }
      final key = '${parsed['분류코드']}-${parsed['순번']}';
      if (seen.contains(key)) {
        continue;
      }
      seen.add(key);
      items.add(parsed);
    }
    return items;
  }

  static bool _isClassTable(TouchkeyTable table) {
    if (_matchesDatasetHint(table, 'dstouchkeyclass')) {
      return true;
    }
    if (_isRenderedSlotTable(table)) {
      return false;
    }
    return table.displayKind == '분류 데이터셋' ||
        (_hasColumn(table, '분류코드') &&
            _hasAnyColumn(table, <String>['분류명', '터치키H', '터치키V']));
  }

  static bool _isProductTable(TouchkeyTable table) {
    if (_matchesDatasetHint(table, 'dstouchkeyclass') ||
        _isRenderedSlotTable(table)) {
      return false;
    }
    if (_matchesDatasetHint(table, 'dstouchkey')) {
      return true;
    }
    return table.displayKind == '상품 데이터셋' ||
        ((_hasColumn(table, '터치키H') || _hasColumn(table, '터치키V')) &&
            _hasAnyColumn(table, <String>['상품명', '상품코드', '판매가']));
  }

  static Map<String, String>? _findClassRow(
    List<Map<String, String>> rows,
    String loadedCode,
  ) {
    for (final row in rows) {
      if (row['분류코드'] == loadedCode) {
        return row;
      }
    }
    return rows.isEmpty ? null : rows.first;
  }

  static List<Map<String, String>> _filterProductItemsByLoadedClass(
    List<Map<String, String>> productItems,
    String loadedCode,
  ) {
    if (loadedCode.trim().isEmpty) {
      return productItems;
    }
    final hasClassCode = productItems.any(
      (item) => (item['분류코드'] ?? '').trim().isNotEmpty,
    );
    if (!hasClassCode) {
      return productItems;
    }
    final filtered = productItems
        .where((item) => (item['분류코드'] ?? '').trim() == loadedCode)
        .toList(growable: false);
    return filtered.isEmpty ? productItems : filtered;
  }

  static Map<String, Map<String, String>> _buildDatasetGrid(
    List<Map<String, String>> productItems,
    int page,
  ) {
    final grid = <String, Map<String, String>>{};
    for (final item in productItems) {
      if (_parseInt(item['터치키페이지'], defaultValue: 1) != page) {
        continue;
      }
      final h = _parseInt(item['터치키H']);
      final v = _parseInt(item['터치키V']);
      if (h > 0 && v > 0) {
        grid['$h-$v'] = item;
      }
    }
    return grid;
  }

  static Map<String, Map<String, String>>? _buildSlotGrid(
      TouchkeyTable? table) {
    if (table == null || table.rows.isEmpty) {
      return null;
    }
    final slotColumns = table.columns
        .where((column) =>
            RegExp(r'^slot_\d+$', caseSensitive: false).hasMatch(column))
        .toList(growable: false);
    if (slotColumns.isEmpty) {
      return null;
    }
    final grid = <String, Map<String, String>>{};
    for (var rowIndex = 0; rowIndex < table.rows.length; rowIndex++) {
      final row = table.rows[rowIndex];
      for (var columnIndex = 0;
          columnIndex < slotColumns.length;
          columnIndex++) {
        final tableColumnIndex =
            table.columns.indexOf(slotColumns[columnIndex]);
        if (tableColumnIndex < 0 || tableColumnIndex >= row.length) {
          continue;
        }
        final value = row[tableColumnIndex];
        if (value.trim().isEmpty || value == '-') {
          continue;
        }
        final parsed = _parseRenderedProductSlotValue(value);
        if (parsed == null || (parsed['상품명'] ?? '').trim().isEmpty) {
          continue;
        }
        grid['${columnIndex + 1}-${rowIndex + 1}'] = parsed;
      }
    }
    return grid.isEmpty ? null : grid;
  }

  static List<int> _allPages(List<Map<String, String>> productItems) {
    final pages = productItems
        .map((item) => _parseInt(item['터치키페이지'], defaultValue: 1))
        .where((value) => value > 0)
        .toSet()
        .toList(growable: false)
      ..sort();
    return pages.isEmpty ? const <int>[1] : pages;
  }

  static int _gridSize(String? explicit, List<String?> candidates) {
    final direct = _parseInt(explicit);
    if (direct > 0) {
      return direct;
    }
    final values = candidates
        .map((value) => _parseInt(value))
        .where((value) => value > 0)
        .toList(growable: false);
    if (values.isEmpty) {
      return 4;
    }
    values.sort();
    return values.last;
  }

  static int _parseInt(String? value, {int defaultValue = 0}) {
    final parsed = int.tryParse((value ?? '').replaceAll(',', '').trim());
    return parsed ?? defaultValue;
  }
}

class _TouchkeyExplorerView extends StatefulWidget {
  final TouchkeyPayload data;

  const _TouchkeyExplorerView({required this.data});

  @override
  State<_TouchkeyExplorerView> createState() => _TouchkeyExplorerViewState();
}

class _TouchkeyExplorerViewState extends State<_TouchkeyExplorerView> {
  late String _activeGridKey;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _activeGridKey =
        widget.data.tables.isEmpty ? '' : widget.data.tables.first.gridKey;
  }

  @override
  void didUpdateWidget(covariant _TouchkeyExplorerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.programKey != widget.data.programKey) {
      _activeGridKey =
          widget.data.tables.isEmpty ? '' : widget.data.tables.first.gridKey;
      _searchController.clear();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeTable = _findActiveTable(widget.data.tables, _activeGridKey);
    final sourceCodes = widget.data.sources
        .map((source) => source.programCode)
        .where((value) => value.trim().isNotEmpty)
        .join(' + ');
    final filteredRows = activeTable == null
        ? const <List<String>>[]
        : _filterRows(activeTable, _searchController.text);
    final selectedClass =
        widget.data.selectedClass['분류명']?.toString().trim().isNotEmpty == true
            ? widget.data.selectedClass['분류명'].toString().trim()
            : (widget.data.selectedClass['분류코드']
                        ?.toString()
                        .trim()
                        .isNotEmpty ==
                    true
                ? widget.data.selectedClass['분류코드'].toString().trim()
                : '-');

    return Column(
      children: [
        ResponsiveWrapGrid(
          minItemWidth: 220,
          maxColumns: 2,
          children: [
            StatCard(
              label: '프로그램',
              value: widget.data.label.isEmpty
                  ? widget.data.programCode
                  : widget.data.label,
              sub: sourceCodes.isEmpty ? widget.data.programCode : sourceCodes,
              accent: true,
            ),
            StatCard(
              label: '로드 상태',
              value: _loadStatusLabel(widget.data.loadStatus),
              sub: widget.data.description.isEmpty
                  ? '-'
                  : widget.data.description,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.data.sources.isNotEmpty ||
            widget.data.sourceErrors.isNotEmpty) ...[
          Panel(
            title: '통합 소스',
            subtitle: '현재 화면을 구성한 원본 프로그램입니다.',
            child: Column(
              children: [
                if (widget.data.sources.isNotEmpty)
                  ResponsiveWrapGrid(
                    minItemWidth: 220,
                    maxColumns: 2,
                    children: widget.data.sources
                        .map(
                          (source) => StatCard(
                            label: source.programCode,
                            value: source.label.isEmpty ? '-' : source.label,
                            sub:
                                '${_loadStatusLabel(source.loadStatus)} · 그리드 ${source.tableCount}개',
                          ),
                        )
                        .toList(growable: false),
                  ),
                if (widget.data.sourceErrors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final item in widget.data.sourceErrors)
                    _InfoRow(
                      label: item.programCode.isEmpty
                          ? item.label
                          : item.programCode,
                      value: item.error.isEmpty ? '-' : item.error,
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        ResponsiveWrapGrid(
          minItemWidth: 220,
          maxColumns: 2,
          children: [
            StatCard(
              label: '선택 분류',
              value: selectedClass,
              sub:
                  '분류 ${widget.data.datasetCounts['분류데이터셋'] ?? widget.data.datasetCounts['dsTouchKeyClass'] ?? 0}행',
            ),
            StatCard(
              label: '탐지 그리드',
              value: '${widget.data.tables.length}개',
              sub: '런타임 노드 ${widget.data.runtimeNodes.length}개',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Panel(
          title: '프로그램 구조',
          subtitle: '열기 방식과 현재 선택 상태를 보여 줍니다.',
          child: Column(
            children: [
              _InfoRow(
                label: '프로그램 경로',
                value: widget.data.programPath.isEmpty
                    ? '-'
                    : widget.data.programPath,
              ),
              _InfoRow(
                label: '열기 방식',
                value: widget.data.openResult['method']?.toString() ?? '-',
              ),
              _InfoRow(
                label: '메뉴명',
                value: widget.data.openResult['menu_name']?.toString() ?? '-',
              ),
              _InfoRow(
                label: '메뉴 ID',
                value: widget.data.openResult['menu_id']?.toString() ?? '-',
              ),
              _InfoRow(
                label: '조회 시각',
                value:
                    widget.data.fetchedAt.isEmpty ? '-' : widget.data.fetchedAt,
              ),
            ],
          ),
        ),
        Panel(
          title: '로드 흐름',
          subtitle: '분류 로드, 상품 로드, 생략 사유까지 단계별로 확인합니다.',
          child: widget.data.loadSteps.isEmpty
              ? const EmptyState(
                  title: '로드 흐름 정보가 없습니다.',
                  message: '백엔드 응답에 load_steps가 포함되면 여기에 표시됩니다.',
                )
              : Column(
                  children: widget.data.loadSteps
                      .map((step) => _LoadStepTile(step: step))
                      .toList(growable: false),
                ),
        ),
        Panel(
          title: '그리드 탐색기',
          subtitle: '원시 데이터셋을 그대로 확인합니다.',
          child: widget.data.tables.isEmpty
              ? const EmptyState(
                  title: '표시할 그리드가 없습니다.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue:
                          _activeGridKey.isEmpty ? null : _activeGridKey,
                      decoration: const InputDecoration(
                        labelText: '그리드 선택',
                        border: OutlineInputBorder(),
                      ),
                      items: widget.data.tables
                          .map(
                            (table) => DropdownMenuItem<String>(
                              value: table.gridKey,
                              child: Text(
                                "${table.gridName} · ${table.displayKind}${table.sourceProgramCode.isEmpty ? '' : ' · ${table.sourceProgramCode}'}",
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _activeGridKey = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: '검색',
                        hintText: '상품명, 코드, 분류명 등',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.clear_outlined),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (activeTable != null) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          _ExplorerChip(
                            label: '행 수',
                            value: '${activeTable.rowCount}',
                          ),
                          _ExplorerChip(
                            label: '컬럼 수',
                            value: '${activeTable.columns.length}',
                          ),
                          _ExplorerChip(
                            label: 'Filled Cells',
                            value: '${activeTable.filledCells}',
                          ),
                          _ExplorerChip(
                            label: 'Format/Body',
                            value:
                                '${activeTable.formatLength} / ${activeTable.bodyCellCount}',
                          ),
                          if (activeTable.sourceProgramCode.isNotEmpty)
                            _ExplorerChip(
                              label: 'Source',
                              value: activeTable.sourceProgramCode,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (activeTable == null)
                      const EmptyState(title: '표시할 그리드가 없습니다.')
                    else if (filteredRows.isEmpty)
                      const EmptyState(
                        title: '검색 결과가 없습니다.',
                      )
                    else
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 18,
                          columns: activeTable.columns
                              .map((column) => DataColumn(label: Text(column)))
                              .toList(growable: false),
                          rows: filteredRows
                              .take(60)
                              .map(
                                (row) => DataRow(
                                  cells: row
                                      .map((cell) => DataCell(Text(cell)))
                                      .toList(growable: false),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  static List<List<String>> _filterRows(TouchkeyTable table, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return table.rows;
    }
    return table.rows
        .where(
          (row) => row.any(
            (cell) => cell.toLowerCase().contains(normalized),
          ),
        )
        .toList(growable: false);
  }

  static TouchkeyTable? _findActiveTable(
    List<TouchkeyTable> tables,
    String gridKey,
  ) {
    for (final table in tables) {
      if (table.gridKey == gridKey) {
        return table;
      }
    }
    return tables.isEmpty ? null : tables.first;
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: const Color.fromRGBO(13, 148, 136, 0.15),
      labelStyle: TextStyle(
        color: selected ? const Color(0xFF0F766E) : const Color(0xFF475569),
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? const Color(0xFF0D9488) : const Color(0xFFE2E8F0),
        ),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _PosSlotCard extends StatelessWidget {
  final Map<String, String>? product;

  const _PosSlotCard({required this.product});

  @override
  Widget build(BuildContext context) {
    if (product == null) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A272C),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF243038)),
        ),
      );
    }

    final name = product!['상품명']?.trim() ?? '';
    final price = product!['판매가']?.trim() ?? '';
    final code = product!['상품코드']?.trim() ?? '';

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF2A3C40),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF3A5058)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            name.isEmpty ? '-' : name,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFD6EAE6),
              fontSize: 11,
              height: 1.3,
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Text(
              price != '-' && price.isNotEmpty
                  ? _formatPrice(price)
                  : (code.isEmpty ? '' : code),
              style: TextStyle(
                color: price != '-' && price.isNotEmpty
                    ? const Color(0xFF99F6E4)
                    : const Color(0xFF507870),
                fontSize: price != '-' && price.isNotEmpty ? 12 : 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatPrice(String value) {
    return normalizeTouchkeyPriceText(value);
  }
}

class _LoadStepTile extends StatelessWidget {
  final TouchkeyLoadStep step;

  const _LoadStepTile({required this.step});

  @override
  Widget build(BuildContext context) {
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
          Text(
            step.title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            step.detail,
            style: const TextStyle(color: Color(0xFF64748B), height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Color(0xFF0F172A)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExplorerChip extends StatelessWidget {
  final String label;
  final String value;

  const _ExplorerChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
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

enum _TouchkeyViewMode { map, explorer }

String _loadStatusLabel(String status) {
  switch (status.toLowerCase()) {
    case 'loaded':
      return '로드 완료';
    case 'partial':
      return '부분 로드';
    case 'empty':
      return '빈 결과';
    case 'skipped':
      return '로드 생략';
    case 'error':
      return '로드 실패';
    default:
      return status.trim().isEmpty ? '-' : status;
  }
}
