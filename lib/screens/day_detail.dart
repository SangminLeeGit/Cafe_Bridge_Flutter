import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/async_request_guard.dart';
import '../models/dashboard_model.dart';
import '../state/app_state.dart';
import '../widgets/cache_notice.dart';
import '../widgets/empty_state.dart';
import '../widgets/panel.dart';
import '../widgets/responsive_wrap_grid.dart';
import '../widgets/stat_card.dart';

class DayDetailScreen extends StatefulWidget {
  final String date;

  const DayDetailScreen({
    super.key,
    required this.date,
  });

  @override
  State<DayDetailScreen> createState() => _DayDetailScreenState();
}

class _DayDetailScreenState extends State<DayDetailScreen>
    with AsyncRequestGuard<DayDetailScreen> {
  DayDetailData? _data;
  bool _isLoading = true;
  String _error = '';
  late String _targetDate;
  bool _fromCache = false;
  DateTime? _cachedAt;

  @override
  void initState() {
    super.initState();
    _targetDate = widget.date;
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    final request = beginAsyncRequest();
    final appState = context.read<AppState>();
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final response = await appState.fetchMapParsed(
        '/api/days/$_targetDate',
        parser: DayDetailData.fromJson,
      );
      if (!isCurrentAsyncRequest(request)) {
        return;
      }
      setState(() {
        _data = response.data;
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

  Future<void> _moveTo(String? targetDate) async {
    if (targetDate == null || targetDate.isEmpty) {
      return;
    }
    setState(() {
      _targetDate = targetDate;
    });
    await _fetchData();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;

    return Scaffold(
      appBar: AppBar(
        title: Text(_targetDate),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error.isNotEmpty
                ? EmptyState(
                    title: '일별 상세를 불러오지 못했습니다.',
                    message: _error,
                    action: FilledButton(
                      onPressed: _fetchData,
                      child: const Text('다시 시도'),
                    ),
                  )
                : data == null || data.error.isNotEmpty
                    ? EmptyState(
                        title: '일별 데이터가 없습니다.',
                        message: data?.error,
                        action: FilledButton(
                          onPressed: _fetchData,
                          child: const Text('새로고침'),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchData,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          children: [
                            if (_fromCache && _cachedAt != null) ...[
                              CacheNotice(cachedAt: _cachedAt),
                              const SizedBox(height: 16),
                            ],
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: data.prevDate == null
                                        ? null
                                        : () => _moveTo(data.prevDate),
                                    icon: const Icon(Icons.chevron_left),
                                    label: const Text('이전 영업일'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: data.nextDate == null
                                        ? null
                                        : () => _moveTo(data.nextDate),
                                    icon: const Icon(Icons.chevron_right),
                                    label: const Text('다음 영업일'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildSummaryGrid(data),
                            const SizedBox(height: 16),
                            Panel(
                              title: '결제수단 구성',
                              subtitle: '당일 매출 기준 비중',
                              child: _buildPaymentMix(data.paymentMix),
                            ),
                            Panel(
                              title: '시간대 매출',
                              subtitle: '시간대별 영수 건수와 매출',
                              child: _buildHourlySales(data.hourlySales),
                            ),
                            Panel(
                              title: 'POS 분포',
                              subtitle: '포스별 처리 건수와 고객 수',
                              child: _buildPosBreakdown(data.posBreakdown),
                            ),
                            Panel(
                              title: '상위 판매 품목',
                              subtitle: '매출 상위 10개 품목',
                              child: _buildTopItems(data.topItems),
                            ),
                            Panel(
                              title: '영수증 목록',
                              subtitle: 'POS / 결제시간 / 금액',
                              child: _buildBills(data.bills),
                            ),
                          ],
                        ),
                      ),
      ),
    );
  }

  Widget _buildSummaryGrid(DayDetailData data) {
    final summary = data.summary;
    final cards = [
      StatCard(
        label: '총매출',
        value: UiFormat.won(summary.grossAmount),
        sub: '순매출 ${UiFormat.won(summary.pureSalesAmount)}',
        accent: true,
      ),
      StatCard(
        label: '영수건수',
        value: '${UiFormat.number(summary.receiptCount)}건',
        sub: '고객 ${UiFormat.number(summary.customerCount)}명',
      ),
      StatCard(
        label: '할인금액',
        value: UiFormat.won(summary.discountAmount),
        sub: '부가세 ${UiFormat.won(summary.vatAmount)}',
      ),
      StatCard(
        label: '카드 / 현금',
        value:
            '${UiFormat.won(summary.cardAmount)} / ${UiFormat.won(summary.cashAmount)}',
      ),
    ];

    return ResponsiveWrapGrid(
      minItemWidth: 280,
      maxColumns: 2,
      children: cards,
    );
  }

  Widget _buildPaymentMix(List<PaymentMixItem> items) {
    if (items.isEmpty) {
      return const Text(
        '결제수단 데이터가 없습니다.',
        style: TextStyle(color: Color(0xFF64748B)),
      );
    }

    return Column(
      children: items.map((item) {
        final pct = item.pct;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.method,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  Text(
                    '${UiFormat.won(item.amount)} · ${pct.toStringAsFixed(1)}%',
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: (pct / 100).clamp(0, 1),
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFF0D9488)),
                ),
              ),
            ],
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _buildTopItems(List<TopItemSummary> items) {
    if (items.isEmpty) {
      return const Text(
        '품목 데이터가 없습니다.',
        style: TextStyle(color: Color(0xFF64748B)),
      );
    }

    final visibleItems = items.take(10).toList(growable: false);
    return Column(
      children: visibleItems.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            radius: 14,
            backgroundColor: const Color.fromRGBO(13, 148, 136, 0.12),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0D9488),
              ),
            ),
          ),
          title: Text(
            item.itemName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '수량 ${UiFormat.number(item.totalQty)}개',
          ),
          trailing: Text(
            UiFormat.won(item.totalAmount),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _buildBills(List<BillRecord> bills) {
    if (bills.isEmpty) {
      return const Text(
        '영수증 데이터가 없습니다.',
        style: TextStyle(color: Color(0xFF64748B)),
      );
    }

    final visibleBills = bills.take(12).toList(growable: false);
    return Column(
      children: visibleBills.map((bill) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'POS ${bill.posNo} · ${bill.billNo}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${bill.formattedPayTime} · 품목 ${UiFormat.number(bill.itemCount)}개 · 고객 ${UiFormat.number(bill.customerCount)}명',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                UiFormat.won(bill.grossAmount),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _buildHourlySales(List<HourlySalesPoint> rows) {
    if (rows.isEmpty) {
      return const Text(
        '시간대 데이터가 없습니다.',
        style: TextStyle(color: Color(0xFF64748B)),
      );
    }

    return Column(
      children: rows.map((row) {
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('${row.hour}:00'),
          subtitle: Text(
            '영수 ${UiFormat.number(row.billCount)}건 · 고객 ${UiFormat.number(row.totalCustomers)}명',
          ),
          trailing: Text(
            UiFormat.won(row.totalAmount),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _buildPosBreakdown(List<PosBreakdown> rows) {
    if (rows.isEmpty) {
      return const Text(
        'POS 분포 데이터가 없습니다.',
        style: TextStyle(color: Color(0xFF64748B)),
      );
    }

    return Column(
      children: rows.map((row) {
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('POS ${row.posNo}'),
          subtitle: Text(
            '영수 ${UiFormat.number(row.billCount)}건 · 고객 ${UiFormat.number(row.totalCustomers)}명',
          ),
          trailing: Text(
            UiFormat.won(row.totalAmount),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      }).toList(growable: false),
    );
  }
}
