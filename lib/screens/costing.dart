import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/costing_models.dart';
import '../state/app_state.dart';
import '../widgets/cache_notice.dart';
import '../widgets/empty_state.dart';
import '../widgets/panel.dart';
import '../widgets/responsive_wrap_grid.dart';
import '../widgets/stat_card.dart';

class CostingScreen extends StatelessWidget {
  const CostingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '원가 관리',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '재료 단가와 레시피 원가율을 관리합니다.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                ),
                const SizedBox(height: 12),
                const TabBar(
                  tabs: [
                    Tab(text: '대시보드'),
                    Tab(text: '재료'),
                    Tab(text: '레시피'),
                  ],
                ),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _CostingDashboardTab(),
                _IngredientsTab(),
                _RecipesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Dashboard Tab ────────────────────────────────────────────────────────────

class _CostingDashboardTab extends StatefulWidget {
  const _CostingDashboardTab();

  @override
  State<_CostingDashboardTab> createState() => _CostingDashboardTabState();
}

class _CostingDashboardTabState extends State<_CostingDashboardTab> {
  CostingDashboardData? _data;
  bool _isLoading = true;
  String _error = '';
  bool _fromCache = false;
  DateTime? _cachedAt;

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
        '/api/costing/dashboard',
        params: {'limit': 5},
        parser: CostingDashboardData.fromJson,
        cacheTtl: const Duration(minutes: 10),
      );
      if (!mounted) return;
      setState(() {
        _data = response.data;
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return EmptyState(
        title: '원가 대시보드를 불러오지 못했습니다.',
        message: _error,
        action: FilledButton(onPressed: _load, child: const Text('다시 시도')),
      );
    }
    final data = _data;
    if (data == null) {
      return EmptyState(
        title: '데이터가 없습니다.',
        action: FilledButton(onPressed: _load, child: const Text('새로고침')),
      );
    }

    final s = data.summary;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_fromCache && _cachedAt != null) ...[
            CacheNotice(cachedAt: _cachedAt),
            const SizedBox(height: 12),
          ],
          _MetricGrid(
            cards: [
              StatCard(
                label: '등록 재료',
                value: '${s.ingredientCount}개',
                sub: '단가 등록 ${s.pricedIngredientCount}개',
                accent: true,
              ),
              StatCard(
                label: '레시피',
                value: '${s.recipeCount}개',
                sub: '원가 초과 ${s.alertRecipeCount}개',
              ),
              StatCard(
                label: '7일 단가 변경',
                value: '${s.recentPriceChangeCount}건',
              ),
              StatCard(
                label: '최종 단가 등록',
                value: s.lastPriceChangeAt.isEmpty
                    ? '-'
                    : s.lastPriceChangeAt.substring(0, 10),
              ),
            ],
          ),
          if (data.alerts.isNotEmpty) ...[
            const SizedBox(height: 16),
            Panel(
              title: '원가 초과 레시피',
              subtitle: '목표 원가율 초과 항목',
              child: Column(
                children: data.alerts.map((r) {
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(r.menuName),
                    subtitle: Text(
                      '원가율 ${(r.costRatio * 100).toStringAsFixed(1)}% (목표 ${(r.targetCostRatio * 100).toStringAsFixed(0)}%)',
                    ),
                    trailing: Text(
                      '${_won(r.totalCost)}원',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                    onTap: () => _pushRecipeDetail(context, r),
                  );
                }).toList(growable: false),
              ),
            ),
          ],
          if (data.recentRecipes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Panel(
              title: '최근 업데이트 레시피',
              child: Column(
                children: data.recentRecipes.map((r) {
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(r.menuName),
                    subtitle: Text(
                      '재료 ${r.itemCount}종 · 원가율 ${(r.costRatio * 100).toStringAsFixed(1)}%',
                    ),
                    trailing: Text(
                      '${_won(r.totalCost)}원',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () => _pushRecipeDetail(context, r),
                  );
                }).toList(growable: false),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Ingredients Tab ──────────────────────────────────────────────────────────

class _IngredientsTab extends StatefulWidget {
  const _IngredientsTab();

  @override
  State<_IngredientsTab> createState() => _IngredientsTabState();
}

class _IngredientsTabState extends State<_IngredientsTab> {
  List<Ingredient>? _list;
  bool _isLoading = true;
  String _error = '';

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
        '/api/costing/ingredients',
        parser: (json) => _parseIngredients(json),
        cacheTtl: const Duration(minutes: 10),
      );
      if (!mounted) return;
      setState(() {
        _list = response.data;
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

  static List<Ingredient> _parseIngredients(Map<String, dynamic> json) {
    final raw = json['ingredients'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Ingredient.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return EmptyState(
        title: '재료 목록을 불러오지 못했습니다.',
        message: _error,
        action: FilledButton(onPressed: _load, child: const Text('다시 시도')),
      );
    }
    final list = _list ?? const <Ingredient>[];
    if (list.isEmpty) {
      return EmptyState(
        title: '등록된 재료가 없습니다.',
        action: FilledButton(onPressed: _load, child: const Text('새로고침')),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemCount: list.length,
        itemBuilder: (context, index) {
          final item = list[index];
          return _IngredientCard(
            ingredient: item,
            onTap: () => _pushIngredientDetail(context, item),
          );
        },
      ),
    );
  }
}

class _IngredientCard extends StatelessWidget {
  final Ingredient ingredient;
  final VoidCallback onTap;

  const _IngredientCard({required this.ingredient, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final i = ingredient;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        title: Row(
          children: [
            Expanded(
                child: Text(i.name,
                    style: const TextStyle(fontWeight: FontWeight.w700))),
            if (!i.isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '비활성',
                  style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${i.category.isEmpty ? '미분류' : i.category} · ${i.baseUnit} · 단가 이력 ${i.priceCount}건',
        ),
        trailing: i.currentUnitCost == null
            ? const Text('단가 없음',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12))
            : Text(
                '${i.currentUnitCost!.toStringAsFixed(i.currentUnitCost! < 10 ? 2 : 0)}원/\${i.baseUnit}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
      ),
    );
  }
}

// ─── Recipes Tab ──────────────────────────────────────────────────────────────

class _RecipesTab extends StatefulWidget {
  const _RecipesTab();

  @override
  State<_RecipesTab> createState() => _RecipesTabState();
}

class _RecipesTabState extends State<_RecipesTab> {
  List<RecipeSummaryRow>? _list;
  bool _isLoading = true;
  String _error = '';

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
        '/api/costing/recipes',
        parser: (json) => _parseRecipes(json),
        cacheTtl: const Duration(minutes: 10),
      );
      if (!mounted) return;
      setState(() {
        _list = response.data;
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

  static List<RecipeSummaryRow> _parseRecipes(Map<String, dynamic> json) {
    final raw = json['recipes'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => RecipeSummaryRow.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return EmptyState(
        title: '레시피 목록을 불러오지 못했습니다.',
        message: _error,
        action: FilledButton(onPressed: _load, child: const Text('다시 시도')),
      );
    }
    final list = _list ?? const <RecipeSummaryRow>[];
    if (list.isEmpty) {
      return EmptyState(
        title: '등록된 레시피가 없습니다.',
        action: FilledButton(onPressed: _load, child: const Text('새로고침')),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemCount: list.length,
        itemBuilder: (context, index) {
          final item = list[index];
          return _RecipeCard(
            recipe: item,
            onTap: () => _pushRecipeDetail(context, item),
          );
        },
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  final RecipeSummaryRow recipe;
  final VoidCallback onTap;

  const _RecipeCard({required this.recipe, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = recipe;
    final costRatioPct = (r.costRatio * 100).toStringAsFixed(1);
    final targetPct = (r.targetCostRatio * 100).toStringAsFixed(0);

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        title: Row(
          children: [
            Expanded(
              child: Text(r.menuName,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (r.isOverCost)
              const Icon(Icons.warning_amber_rounded,
                  size: 16, color: Color(0xFFDC2626)),
          ],
        ),
        subtitle: Text(
          '재료 ${r.itemCount}종 · 원가율 $costRatioPct% (목표 $targetPct%)',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${_won(r.totalCost)}원',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: r.isOverCost ? const Color(0xFFDC2626) : null,
              ),
            ),
            if (r.sellingPrice > 0)
              Text(
                '판매가 ${_won(r.sellingPrice)}원',
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Recipe Detail Screen ─────────────────────────────────────────────────────

class RecipeDetailScreen extends StatefulWidget {
  final int recipeId;
  final String recipeName;

  const RecipeDetailScreen({
    super.key,
    required this.recipeId,
    required this.recipeName,
  });

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  RecipeDetailData? _data;
  bool _isLoading = true;
  String _error = '';

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
        '/api/costing/recipes/${widget.recipeId}',
        parser: RecipeDetailData.fromJson,
        cacheTtl: const Duration(minutes: 5),
      );
      if (!mounted) return;
      setState(() {
        _data = response.data;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recipeName),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE2E8F0)),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error.isNotEmpty
                ? EmptyState(
                    title: '레시피를 불러오지 못했습니다.',
                    message: _error,
                    action: FilledButton(
                        onPressed: _load, child: const Text('다시 시도')),
                  )
                : _buildBody(_data!),
      ),
    );
  }

  Widget _buildBody(RecipeDetailData data) {
    final r = data.recipe;
    final s = data.summary;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _MetricGrid(
            cards: [
              StatCard(
                label: '총 원가',
                value: '${_won(s.totalCost)}원',
                accent: r.isOverCost,
              ),
              StatCard(
                label: '원가율',
                value: '${(s.costRatio * 100).toStringAsFixed(1)}%',
                sub: '목표 ${(r.targetCostRatio * 100).toStringAsFixed(0)}%',
              ),
              StatCard(
                label: '판매가',
                value: r.sellingPrice > 0 ? '${_won(r.sellingPrice)}원' : '-',
              ),
              StatCard(
                label: '마진',
                value: '${_won(s.marginAmount)}원',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Panel(
            title: '재료 구성',
            subtitle: '재료 ${s.itemCount}종',
            child: Column(
              children: data.items.map((item) {
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.ingredientName),
                  subtitle: Text('${item.qty} ${item.ingredientBaseUnit}'),
                  trailing: item.lineCost == null
                      ? const Text('-',
                          style: TextStyle(color: Color(0xFF94A3B8)))
                      : Text(
                          '${item.lineCost!.toStringAsFixed(0)}원',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                );
              }).toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Ingredient Detail Screen ─────────────────────────────────────────────────

class IngredientDetailScreen extends StatefulWidget {
  final int ingredientId;
  final String ingredientName;

  const IngredientDetailScreen({
    super.key,
    required this.ingredientId,
    required this.ingredientName,
  });

  @override
  State<IngredientDetailScreen> createState() => _IngredientDetailScreenState();
}

class _IngredientDetailScreenState extends State<IngredientDetailScreen> {
  List<IngredientPrice>? _prices;
  bool _isLoading = true;
  String _error = '';

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
        '/api/costing/ingredients/${widget.ingredientId}/prices',
        parser: (json) {
          final raw = json['prices'];
          if (raw is! List) return const <IngredientPrice>[];
          return raw
              .whereType<Map>()
              .map(
                  (e) => IngredientPrice.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false);
        },
        cacheTtl: const Duration(minutes: 5),
      );
      if (!mounted) return;
      setState(() {
        _prices = response.data;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ingredientName),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE2E8F0)),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error.isNotEmpty
                ? EmptyState(
                    title: '단가 이력을 불러오지 못했습니다.',
                    message: _error,
                    action: FilledButton(
                        onPressed: _load, child: const Text('다시 시도')),
                  )
                : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final prices = _prices ?? const <IngredientPrice>[];
    if (prices.isEmpty) {
      return const EmptyState(title: '등록된 단가 이력이 없습니다.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemCount: prices.length,
      itemBuilder: (context, index) {
        final p = prices[index];
        return ListTile(
          dense: true,
          title: Text(
            '${p.unitCost.toStringAsFixed(p.unitCost < 10 ? 2 : 0)}원',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '적용일 ${p.effectiveDate.isEmpty ? '-' : p.effectiveDate}'
            '${p.supplierName.isEmpty ? '' : ' · ${p.supplierName}'}',
          ),
          trailing: p.packageCost == null
              ? null
              : Text('묶음 ${p.packageCost!.toStringAsFixed(0)}원'),
        );
      },
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

void _pushRecipeDetail(BuildContext context, RecipeSummaryRow recipe) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => RecipeDetailScreen(
        recipeId: recipe.recipeId,
        recipeName: recipe.menuName,
      ),
    ),
  );
}

void _pushIngredientDetail(BuildContext context, Ingredient ingredient) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => IngredientDetailScreen(
        ingredientId: ingredient.ingredientId,
        ingredientName: ingredient.name,
      ),
    ),
  );
}

class _MetricGrid extends StatelessWidget {
  final List<Widget> cards;
  const _MetricGrid({required this.cards});

  @override
  Widget build(BuildContext context) {
    return ResponsiveWrapGrid(
      minItemWidth: 280,
      maxColumns: 2,
      children: cards,
    );
  }
}

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
