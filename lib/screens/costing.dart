import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/async_request_guard.dart';
import '../navigation/app_navigation.dart';
import '../models/costing_models.dart';
import '../services/api.dart';
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
      length: 4,
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
                    Tab(text: '임시 계산'),
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
                _RecipeCalculatorTab(),
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

class _CostingDashboardTabState extends State<_CostingDashboardTab>
    with AsyncRequestGuard<_CostingDashboardTab> {
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

  Future<void> _load({bool force = false}) async {
    if (!mounted) return;
    final request = beginAsyncRequest();
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
        cacheTtl: force ? Duration.zero : const Duration(minutes: 10),
      );
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _data = response.data;
        _fromCache = response.fromCache;
        _cachedAt = response.cachedAt;
        _isLoading = false;
      });
    } catch (error) {
      if (!isCurrentAsyncRequest(request)) return;
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
        action: FilledButton(
          onPressed: () => _load(force: true),
          child: const Text('다시 시도'),
        ),
      );
    }
    final data = _data;
    if (data == null) {
      return EmptyState(
        title: '데이터가 없습니다.',
        action: FilledButton(
          onPressed: () => _load(force: true),
          child: const Text('새로고침'),
        ),
      );
    }

    final s = data.summary;
    return RefreshIndicator(
      onRefresh: () => _load(force: true),
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
                    : _safeDateLabel(s.lastPriceChangeAt),
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

class _IngredientsTabState extends State<_IngredientsTab>
    with AsyncRequestGuard<_IngredientsTab> {
  List<Ingredient>? _list;
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (!mounted) return;
    final request = beginAsyncRequest();
    final appState = context.read<AppState>();
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final response = await appState.fetchMapParsed(
        '/api/costing/ingredients',
        parser: (json) => _parseIngredients(json),
        cacheTtl: force ? Duration.zero : const Duration(minutes: 10),
        allowStaleOnError: !force,
      );
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _list = response.data;
        _isLoading = false;
      });
    } catch (error) {
      if (!isCurrentAsyncRequest(request)) return;
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

  Future<void> _createIngredient() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _IngredientCreateDialog(),
    );
    if (created == true && mounted) await _load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return EmptyState(
        title: '재료 목록을 불러오지 못했습니다.',
        message: _error,
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: () => _load(force: true),
              child: const Text('다시 시도'),
            ),
            if (context.watch<AppState>().hasOperatorAccess)
              TextButton.icon(
                onPressed: _createIngredient,
                icon: const Icon(Icons.add),
                label: const Text('새 재료 등록'),
              ),
          ],
        ),
      );
    }
    final list = _list ?? const <Ingredient>[];
    final canManage = context.watch<AppState>().hasOperatorAccess;
    if (list.isEmpty) {
      return EmptyState(
        title: '등록된 재료가 없습니다.',
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canManage)
              FilledButton.icon(
                onPressed: _createIngredient,
                icon: const Icon(Icons.add),
                label: const Text('새 재료 등록'),
              ),
            TextButton(
              onPressed: () => _load(force: true),
              child: const Text('새로고침'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemCount: list.length + (canManage ? 1 : 0),
        itemBuilder: (context, index) {
          if (canManage && index == 0) {
            return Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('새 재료 등록'),
                subtitle: const Text('원가 계산 단위와 기본 정보를 추가합니다.'),
                onTap: _createIngredient,
              ),
            );
          }
          final ingredientIndex = index - (canManage ? 1 : 0);
          final item = list[ingredientIndex];
          return _IngredientCard(
            ingredient: item,
            onTap: () => _pushIngredientDetail(
              context,
              item,
              onUpdated: () => _load(force: true),
            ),
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
                '${i.currentUnitCost!.toStringAsFixed(i.currentUnitCost! < 10 ? 2 : 0)}원/${i.baseUnit}',
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

class _RecipesTabState extends State<_RecipesTab>
    with AsyncRequestGuard<_RecipesTab> {
  List<RecipeSummaryRow>? _list;
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (!mounted) return;
    final request = beginAsyncRequest();
    final appState = context.read<AppState>();
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final response = await appState.fetchMapParsed(
        '/api/costing/recipes',
        parser: (json) => _parseRecipes(json),
        cacheTtl: force ? Duration.zero : const Duration(minutes: 10),
        allowStaleOnError: !force,
      );
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _list = response.data;
        _isLoading = false;
      });
    } catch (error) {
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _createRecipe() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _RecipeEditorDialog(),
    );
    if (created == true && mounted) await _load(force: true);
  }

  Future<void> _openRecipe(RecipeSummaryRow recipe) async {
    await AppNavigation.pushGuarded<void>(
      context,
      minimumRole: UserRole.operator,
      child: RecipeDetailScreen(
        recipeId: recipe.recipeId,
        recipeName: recipe.menuName,
      ),
    );
    if (mounted) await _load(force: true);
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
    final canManage = context.watch<AppState>().hasOperatorAccess;
    if (list.isEmpty) {
      return EmptyState(
        title: '등록된 레시피가 없습니다.',
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canManage)
              FilledButton.icon(
                onPressed: _createRecipe,
                icon: const Icon(Icons.add),
                label: const Text('새 레시피 등록'),
              ),
            TextButton(
              onPressed: () => _load(force: true),
              child: const Text('새로고침'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemCount: list.length + (canManage ? 1 : 0),
        itemBuilder: (context, index) {
          if (canManage && index == 0) {
            return Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('새 레시피 등록'),
                subtitle: const Text('등록된 재료로 레시피 원가를 관리합니다.'),
                onTap: _createRecipe,
              ),
            );
          }
          final item = list[index - (canManage ? 1 : 0)];
          return _RecipeCard(
            recipe: item,
            onTap: () => _openRecipe(item),
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

class _RecipeDetailScreenState extends State<RecipeDetailScreen>
    with AsyncRequestGuard<RecipeDetailScreen> {
  RecipeDetailData? _data;
  bool _isLoading = true;
  bool _deleting = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (!mounted) return;
    final request = beginAsyncRequest();
    final appState = context.read<AppState>();
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final response = await appState.fetchMapParsed(
        '/api/costing/recipes/${widget.recipeId}',
        parser: RecipeDetailData.fromJson,
        cacheTtl: force ? Duration.zero : const Duration(minutes: 5),
        allowStaleOnError: !force,
      );
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _data = response.data;
        _isLoading = false;
      });
    } catch (error) {
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _editRecipe() async {
    final data = _data;
    if (data == null || data.recipe.versionNo == null) return;
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _RecipeEditorDialog(initialData: data),
    );
    if (updated == true && mounted) await _load(force: true);
  }

  Future<void> _deleteRecipe() async {
    final recipe = _data?.recipe;
    final versionNo = recipe?.versionNo;
    if (recipe == null || versionNo == null || _deleting) return;
    if (!context.read<AppState>().hasOperatorAccess) return;
    setState(() => _deleting = true);
    Map<String, dynamic>? pendingBody;
    var saving = false;
    var revisionConflict = false;
    var deleteError = '';
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => PopScope<bool>(
          canPop: pendingBody == null || revisionConflict,
          child: AlertDialog(
            title: const Text('레시피 삭제'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${recipe.menuName} 레시피를 영구 삭제합니다.'),
                const SizedBox(height: 8),
                const Text(
                  '삭제 후에는 복구할 수 없습니다. 계속하시겠습니까?',
                  style: TextStyle(color: Color(0xFFB91C1C)),
                ),
                if (deleteError.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    deleteError,
                    style: const TextStyle(color: Color(0xFFB91C1C)),
                  ),
                ],
                if (pendingBody != null && !saving && !revisionConflict) ...[
                  const SizedBox(height: 8),
                  const Text(
                    '결과를 확인하지 못했습니다. 같은 요청 ID와 revision으로 재시도합니다.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: saving || (pendingBody != null && !revisionConflict)
                    ? null
                    : () => Navigator.pop(dialogContext, revisionConflict),
                child: Text(revisionConflict ? '닫고 새로고침' : '취소'),
              ),
              FilledButton(
                onPressed: saving || revisionConflict
                    ? null
                    : () async {
                        pendingBody ??= Map<String, dynamic>.unmodifiable(
                          buildCostingRecipeDeletePayload(
                            expectedVersionNo: versionNo,
                            requestId: _newCostingRequestId(),
                          ),
                        );
                        setDialogState(() {
                          saving = true;
                          deleteError = '';
                        });
                        try {
                          await context.read<AppState>().postJson(
                                '/api/costing/recipes/${recipe.recipeId}',
                                method: 'DELETE',
                                body: pendingBody!,
                              );
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } catch (error) {
                          if (!dialogContext.mounted) return;
                          final status =
                              error is ApiException ? error.statusCode : null;
                          setDialogState(() {
                            saving = false;
                            deleteError = error.toString();
                            if (status == 409) {
                              pendingBody = null;
                              revisionConflict = true;
                              deleteError =
                                  '레시피가 다른 요청으로 변경되었습니다. 최신 정보를 다시 불러와 주세요.';
                            } else if (status != null && status < 500) {
                              pendingBody = null;
                            }
                          });
                        }
                      },
                child: Text(
                  saving
                      ? '삭제 중...'
                      : pendingBody == null
                          ? '영구 삭제'
                          : '같은 요청 재시도',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _deleting = false);
    if (result == true) {
      Navigator.of(context).pop();
    } else if (result == false) {
      await _load(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_data?.recipe.menuName ?? widget.recipeName),
        actions: [
          if (context.watch<AppState>().hasOperatorAccess)
            IconButton(
              tooltip: '레시피 수정',
              onPressed: _isLoading || _data?.recipe.versionNo == null
                  ? null
                  : _editRecipe,
              icon: const Icon(Icons.edit_outlined),
            ),
          if (context.watch<AppState>().hasOperatorAccess)
            IconButton(
              tooltip: '레시피 삭제',
              onPressed:
                  _isLoading || _deleting || _data?.recipe.versionNo == null
                      ? null
                      : _deleteRecipe,
              icon: const Icon(Icons.delete_outline),
            ),
          IconButton(
            tooltip: '새로고침',
            onPressed: _isLoading ? null : () => _load(force: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
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
                        onPressed: () => _load(force: true),
                        child: const Text('다시 시도')),
                  )
                : _buildBody(_data!),
      ),
    );
  }

  Widget _buildBody(RecipeDetailData data) {
    final r = data.recipe;
    final s = data.summary;
    return RefreshIndicator(
      onRefresh: () => _load(force: true),
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
                  subtitle: Text('${item.quantity} ${item.ingredientBaseUnit}'),
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

class _RecipeEditorDialog extends StatefulWidget {
  final RecipeDetailData? initialData;

  const _RecipeEditorDialog({this.initialData});

  @override
  State<_RecipeEditorDialog> createState() => _RecipeEditorDialogState();
}

class _RecipeEditorDialogState extends State<_RecipeEditorDialog>
    with AsyncRequestGuard<_RecipeEditorDialog> {
  late final _menuName = TextEditingController(
    text: widget.initialData?.recipe.menuName ?? '',
  );
  late final _menuCode = TextEditingController(
    text: widget.initialData?.recipe.menuCode ?? '',
  );
  late final _sizeCode = TextEditingController(
    text: widget.initialData?.recipe.sizeCode ?? '',
  );
  late final _temperatureCode = TextEditingController(
    text: widget.initialData?.recipe.temperatureCode ?? '',
  );
  late final _sellingPrice = TextEditingController(
    text: (widget.initialData?.recipe.sellingPrice ?? 0) > 0
        ? '${widget.initialData!.recipe.sellingPrice}'
        : '',
  );
  late final _targetRatio = TextEditingController(
    text:
        ((widget.initialData?.recipe.targetCostRatio ?? 0.3) * 100).toString(),
  );
  late final _notes = TextEditingController(
    text: widget.initialData?.recipe.notes ?? '',
  );
  late String _status = widget.initialData?.recipe.status ?? 'draft';
  late final List<_RecipeEditorLine> _lines = widget.initialData?.items
          .map((item) => _RecipeEditorLine(
                ingredientId: item.ingredientId,
                quantity: item.quantity.toString(),
              ))
          .toList() ??
      [_RecipeEditorLine()];
  List<Ingredient> _ingredients = const [];
  Map<String, dynamic>? _pendingBody;
  bool _loadingIngredients = true;
  bool _saving = false;
  bool _revisionConflict = false;
  String _error = '';

  bool get _isEditing => widget.initialData != null;

  @override
  void initState() {
    super.initState();
    _loadIngredients();
  }

  @override
  void dispose() {
    _menuName.dispose();
    _menuCode.dispose();
    _sizeCode.dispose();
    _temperatureCode.dispose();
    _sellingPrice.dispose();
    _targetRatio.dispose();
    _notes.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _loadIngredients() async {
    if (!mounted) return;
    final request = beginAsyncRequest();
    setState(() {
      _loadingIngredients = true;
      _error = '';
    });
    try {
      final response = await context.read<AppState>().fetchMapParsed(
            '/api/costing/ingredients',
            parser: _IngredientsTabState._parseIngredients,
            cacheTtl: Duration.zero,
            allowStaleOnError: false,
          );
      if (!isCurrentAsyncRequest(request)) return;
      final byId = <int, Ingredient>{
        for (final ingredient in response.data)
          if (ingredient.isActive && ingredient.currentUnitCost != null)
            ingredient.ingredientId: ingredient,
      };
      for (final item in widget.initialData?.items ?? const <RecipeItem>[]) {
        if (!item.ingredientActive || item.currentUnitCost == null) continue;
        byId.putIfAbsent(
          item.ingredientId,
          () => Ingredient(
            ingredientId: item.ingredientId,
            name: item.ingredientName,
            category: '',
            baseUnit: item.ingredientBaseUnit,
            supplierName: '',
            isActive: true,
            notes: '',
            priceCount: 0,
            currentUnitCost: item.currentUnitCost,
          ),
        );
      }
      final ingredients = byId.values.toList(growable: false);
      final ids = ingredients.map((item) => item.ingredientId).toSet();
      for (final line in _lines) {
        if (line.ingredientId != null && !ids.contains(line.ingredientId)) {
          line.ingredientId = null;
        }
      }
      setState(() {
        _ingredients = ingredients;
        _loadingIngredients = false;
      });
    } catch (error) {
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _error = error.toString();
        _loadingIngredients = false;
      });
    }
  }

  Ingredient? _ingredientById(int? id) {
    if (id == null) return null;
    for (final ingredient in _ingredients) {
      if (ingredient.ingredientId == id) return ingredient;
    }
    return null;
  }

  void _addLine() {
    setState(() => _lines.add(_RecipeEditorLine()));
  }

  void _removeLine(_RecipeEditorLine line) {
    if (_lines.length <= 1) return;
    setState(() {
      _lines.remove(line);
      line.dispose();
    });
  }

  Map<String, dynamic>? _buildPayload() {
    if (_menuName.text.trim().isEmpty) {
      setState(() => _error = '메뉴명을 입력해 주세요.');
      return null;
    }
    final sellingPrice = _parseOptionalNonnegativeInt(_sellingPrice.text);
    if (_sellingPrice.text.trim().isNotEmpty && sellingPrice == null) {
      setState(() => _error = '판매가는 0 이상의 숫자로 입력해 주세요.');
      return null;
    }
    final targetPercent = _parseNumber(_targetRatio.text);
    if (targetPercent == null || targetPercent <= 0 || targetPercent >= 100) {
      setState(() => _error = '목표 원가율은 0보다 크고 100보다 작아야 합니다.');
      return null;
    }
    final items = <CostingCalculationItem>[];
    for (final line in _lines) {
      final ingredient = _ingredientById(line.ingredientId);
      final quantity = _parseNumber(line.quantity.text);
      if (ingredient == null ||
          ingredient.currentUnitCost == null ||
          quantity == null ||
          quantity <= 0) {
        setState(() => _error = '단가가 등록된 재료와 0보다 큰 사용량을 모두 입력해 주세요.');
        return null;
      }
      items.add(CostingCalculationItem(
        ingredientId: ingredient.ingredientId,
        quantity: quantity,
        unit: ingredient.baseUnit,
      ));
    }
    final versionNo = widget.initialData?.recipe.versionNo;
    if (_isEditing && versionNo == null) {
      setState(() => _error = '레시피 revision이 없어 안전하게 수정할 수 없습니다.');
      return null;
    }
    return Map<String, dynamic>.unmodifiable(
      buildCostingRecipePayload(
        menuName: _menuName.text,
        menuCode: _menuCode.text,
        sizeCode: _sizeCode.text,
        temperatureCode: _temperatureCode.text,
        sellingPrice: sellingPrice,
        targetCostRatio: targetPercent / 100,
        status: _status,
        notes: _notes.text,
        items: items,
        requestId: _newCostingRequestId(),
        expectedVersionNo: versionNo,
      ),
    );
  }

  Future<void> _submit() async {
    if (_saving || _revisionConflict) return;
    if (!context.read<AppState>().hasOperatorAccess) {
      setState(() => _error = '레시피를 수정할 권한이 없습니다.');
      return;
    }
    _pendingBody ??= _buildPayload();
    if (_pendingBody == null) return;
    setState(() {
      _saving = true;
      _error = '';
    });
    final recipeId = widget.initialData?.recipe.recipeId;
    try {
      await context.read<AppState>().postJson(
            _isEditing
                ? '/api/costing/recipes/$recipeId'
                : '/api/costing/recipes',
            method: _isEditing ? 'PATCH' : 'POST',
            body: _pendingBody!,
          );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      final status = error is ApiException ? error.statusCode : null;
      setState(() {
        _saving = false;
        _error = error.toString();
        if (status == 409) {
          _pendingBody = null;
          _revisionConflict = true;
          _error = '레시피가 다른 요청으로 변경되었습니다. 최신 정보를 다시 불러와 주세요.';
        } else if (status != null && status < 500) {
          _pendingBody = null;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fieldsEnabled = !_loadingIngredients &&
        !_saving &&
        _pendingBody == null &&
        !_revisionConflict;
    final title = _isEditing ? '레시피 수정' : '새 레시피 등록';
    return PopScope<bool>(
      canPop: _pendingBody == null || _revisionConflict,
      child: AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.65,
          ),
          child: _loadingIngredients
              ? const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                )
              : _error.isNotEmpty && _ingredients.isEmpty
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error),
                        TextButton(
                          onPressed: _loadIngredients,
                          child: const Text('재료 다시 불러오기'),
                        ),
                      ],
                    )
                  : _ingredients.isEmpty
                      ? const SizedBox(
                          height: 160,
                          child: Center(
                            child: Text(
                              '단가가 등록된 활성 재료가 없습니다. 재료 단가를 등록한 뒤 다시 시도해 주세요.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                controller: _menuName,
                                enabled: fieldsEnabled,
                                decoration:
                                    const InputDecoration(labelText: '메뉴명 *'),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _menuCode,
                                      enabled: fieldsEnabled,
                                      decoration: const InputDecoration(
                                          labelText: '메뉴 코드'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _sizeCode,
                                      enabled: fieldsEnabled,
                                      decoration: const InputDecoration(
                                          labelText: '사이즈 코드'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _temperatureCode,
                                      enabled: fieldsEnabled,
                                      decoration: const InputDecoration(
                                          labelText: '온도 코드'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _sellingPrice,
                                      enabled: fieldsEnabled,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                          labelText: '판매가'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _targetRatio,
                                      enabled: fieldsEnabled,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: const InputDecoration(
                                          labelText: '목표 원가율 (%) *'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _status,
                                      decoration: const InputDecoration(
                                          labelText: '상태'),
                                      items: const [
                                        DropdownMenuItem(
                                            value: 'draft',
                                            child: Text('작성 중')),
                                        DropdownMenuItem(
                                            value: 'active',
                                            child: Text('사용 중')),
                                        DropdownMenuItem(
                                            value: 'archived',
                                            child: Text('보관됨')),
                                      ],
                                      onChanged: fieldsEnabled
                                          ? (value) => setState(
                                                () =>
                                                    _status = value ?? _status,
                                              )
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _notes,
                                enabled: fieldsEnabled,
                                maxLines: 2,
                                decoration:
                                    const InputDecoration(labelText: '메모'),
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '재료 구성',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              ..._lines.map((line) {
                                final ingredient =
                                    _ingredientById(line.ingredientId);
                                return Card(
                                  key: line.key,
                                  margin: const EdgeInsets.only(top: 8),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Column(
                                      children: [
                                        DropdownButtonFormField<int>(
                                          initialValue: line.ingredientId,
                                          isExpanded: true,
                                          decoration: const InputDecoration(
                                              labelText: '재료 *'),
                                          items: _ingredients
                                              .map((item) => DropdownMenuItem(
                                                    value: item.ingredientId,
                                                    child: Text(
                                                        '${item.name} (${item.baseUnit})'),
                                                  ))
                                              .toList(growable: false),
                                          onChanged: fieldsEnabled
                                              ? (value) => setState(
                                                    () => line.ingredientId =
                                                        value,
                                                  )
                                              : null,
                                        ),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextField(
                                                controller: line.quantity,
                                                enabled: fieldsEnabled,
                                                keyboardType:
                                                    const TextInputType
                                                        .numberWithOptions(
                                                        decimal: true),
                                                decoration: InputDecoration(
                                                  labelText:
                                                      '사용량 *${ingredient == null ? '' : ' (${ingredient.baseUnit})'}',
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: '재료 제거',
                                              onPressed: !fieldsEnabled ||
                                                      _lines.length == 1
                                                  ? null
                                                  : () => _removeLine(line),
                                              icon: const Icon(
                                                  Icons.remove_circle_outline),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: fieldsEnabled ? _addLine : null,
                                  icon: const Icon(Icons.add),
                                  label: const Text('재료 추가'),
                                ),
                              ),
                              if (_error.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _error,
                                  style:
                                      const TextStyle(color: Color(0xFFB91C1C)),
                                ),
                              ],
                              if (_pendingBody != null && !_saving) ...[
                                const SizedBox(height: 8),
                                const Text(
                                  '결과를 확인하지 못했습니다. 같은 요청 ID와 revision으로 재시도합니다.',
                                  style: TextStyle(
                                      fontSize: 12, color: Color(0xFF92400E)),
                                ),
                              ],
                            ],
                          ),
                        ),
        ),
        actions: [
          TextButton(
            onPressed: _saving || (_pendingBody != null && !_revisionConflict)
                ? null
                : () => Navigator.pop(context, _revisionConflict),
            child: Text(_revisionConflict ? '닫고 새로고침' : '취소'),
          ),
          FilledButton(
            onPressed: _loadingIngredients ||
                    _ingredients.isEmpty ||
                    _saving ||
                    _revisionConflict
                ? null
                : _submit,
            child: Text(
              _saving
                  ? '저장 중...'
                  : _pendingBody == null
                      ? '저장'
                      : '같은 요청 재시도',
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipeEditorLine {
  final Key key = UniqueKey();
  int? ingredientId;
  final TextEditingController quantity;

  _RecipeEditorLine({this.ingredientId, String quantity = ''})
      : quantity = TextEditingController(text: quantity);

  void dispose() => quantity.dispose();
}

// ─── Ingredient Detail Screen ─────────────────────────────────────────────────

class IngredientDetailScreen extends StatefulWidget {
  final int ingredientId;
  final String ingredientName;
  final Future<void> Function()? onUpdated;

  const IngredientDetailScreen({
    super.key,
    required this.ingredientId,
    required this.ingredientName,
    this.onUpdated,
  });

  @override
  State<IngredientDetailScreen> createState() => _IngredientDetailScreenState();
}

class _IngredientDetailScreenState extends State<IngredientDetailScreen>
    with AsyncRequestGuard<IngredientDetailScreen> {
  Ingredient? _ingredient;
  List<IngredientPrice>? _prices;
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (!mounted) return;
    final request = beginAsyncRequest();
    final appState = context.read<AppState>();
    setState(() {
      _isLoading = true;
      _error = '';
      _ingredient = null;
    });
    try {
      final response =
          await appState.fetchMapParsed<IngredientPriceHistoryData>(
        '/api/costing/ingredients/${widget.ingredientId}/prices',
        parser: IngredientPriceHistoryData.fromJson,
        cacheTtl: force ? Duration.zero : const Duration(minutes: 5),
        allowStaleOnError: !force,
      );
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _ingredient = response.data.ingredient;
        _prices = response.data.prices;
        _isLoading = false;
      });
    } catch (error) {
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _addPrice() async {
    final ingredient = _ingredient;
    final revision = ingredient?.editRevision;
    if (ingredient == null || revision == null || revision < 1) return;
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => _IngredientPriceDialog(
        ingredientId: widget.ingredientId,
        baseUnit: ingredient.baseUnit,
        supplierName: ingredient.supplierName,
        expectedEditRevision: revision,
      ),
    );
    if (added == true && mounted) {
      await _load(force: true);
      final onUpdated = widget.onUpdated;
      if (onUpdated != null) await onUpdated();
    }
  }

  Future<void> _editIngredient() async {
    final ingredient = _ingredient;
    if (ingredient?.editRevision == null) return;
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _IngredientEditDialog(ingredient: ingredient!),
    );
    if (updated == true && mounted) {
      await _load(force: true);
      final onUpdated = widget.onUpdated;
      if (onUpdated != null) await onUpdated();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_ingredient?.name ?? widget.ingredientName),
        actions: [
          if (context.watch<AppState>().hasOperatorAccess)
            IconButton(
              tooltip: '재료 정보 수정',
              onPressed: _isLoading || _ingredient?.editRevision == null
                  ? null
                  : _editIngredient,
              icon: const Icon(Icons.edit_outlined),
            ),
          IconButton(
            tooltip: '새로고침',
            onPressed: _isLoading ? null : () => _load(force: true),
            icon: const Icon(Icons.refresh),
          ),
          if (context.watch<AppState>().hasOperatorAccess)
            IconButton(
              tooltip: '단가 등록',
              onPressed: _isLoading || _ingredient?.editRevision == null
                  ? null
                  : _addPrice,
              icon: const Icon(Icons.add),
            ),
        ],
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
                        onPressed: () => _load(force: true),
                        child: const Text('다시 시도')),
                  )
                : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final prices = _prices ?? const <IngredientPrice>[];
    final canManage = context.watch<AppState>().hasOperatorAccess &&
        (_ingredient?.editRevision ?? 0) > 0;
    if (prices.isEmpty) {
      return EmptyState(
        title: '등록된 단가 이력이 없습니다.',
        action: canManage
            ? FilledButton.icon(
                onPressed: _addPrice,
                icon: const Icon(Icons.add),
                label: const Text('단가 등록'),
              )
            : null,
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemCount: prices.length + (canManage ? 1 : 0),
        itemBuilder: (context, index) {
          if (canManage && index == 0) {
            return ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('새 단가 이력 등록'),
              onTap: _addPrice,
            );
          }
          final priceIndex = index - (canManage ? 1 : 0);
          final p = prices[priceIndex];
          return ListTile(
            dense: true,
            title: Text(
              '${p.unitCost.toStringAsFixed(p.unitCost < 10 ? 2 : 0)}원',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '구매 ${p.purchasePrice.toStringAsFixed(p.purchasePrice < 10 ? 2 : 0)}원'
              ' · ${p.purchaseQty} ${p.purchaseUnit}'
              ' · 적용일 ${p.effectiveFrom.isEmpty ? '-' : p.effectiveFrom}'
              '${p.supplierName.isEmpty ? '' : ' · ${p.supplierName}'}',
            ),
            trailing: Text(
              '단위 ${p.unitCost.toStringAsFixed(p.unitCost < 10 ? 2 : 0)}원',
              style: const TextStyle(fontSize: 11),
            ),
          );
        },
      ),
    );
  }
}

class _IngredientEditDialog extends StatefulWidget {
  final Ingredient ingredient;

  const _IngredientEditDialog({required this.ingredient});

  @override
  State<_IngredientEditDialog> createState() => _IngredientEditDialogState();
}

class _IngredientEditDialogState extends State<_IngredientEditDialog> {
  late final _name = TextEditingController(text: widget.ingredient.name);
  late final _category =
      TextEditingController(text: widget.ingredient.category);
  late final _supplier =
      TextEditingController(text: widget.ingredient.supplierName);
  late final _notes = TextEditingController(text: widget.ingredient.notes);
  late String _baseUnit = widget.ingredient.baseUnit;
  late bool _isActive = widget.ingredient.isActive;
  Map<String, dynamic>? _pendingBody;
  bool _saving = false;
  bool _revisionConflict = false;
  String _error = '';

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _supplier.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || _revisionConflict) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '재료명을 입력해 주세요.');
      return;
    }
    _pendingBody ??= Map<String, dynamic>.unmodifiable(
      buildCostingIngredientUpdatePayload(
        name: _name.text,
        category: _category.text,
        baseUnit: _baseUnit,
        supplierName: _supplier.text,
        notes: _notes.text,
        isActive: _isActive,
        expectedEditRevision: widget.ingredient.editRevision!,
        requestId: _newCostingRequestId(),
      ),
    );
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await context.read<AppState>().postJson(
            '/api/costing/ingredients/${widget.ingredient.ingredientId}',
            method: 'PATCH',
            body: _pendingBody!,
          );
      if (!mounted) return;
      setState(() {
        _pendingBody = null;
        _saving = false;
      });
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      final status = error is ApiException ? error.statusCode : null;
      setState(() {
        _saving = false;
        _error = error.toString();
        if (status == 409) {
          _pendingBody = null;
          _revisionConflict = true;
          _error = '재료가 다른 요청으로 변경되었습니다. 최신 재료 정보를 다시 불러와 주세요.';
        } else if (status != null && status < 500) {
          _pendingBody = null;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !_saving && _pendingBody == null && !_revisionConflict;
    return PopScope<bool>(
      canPop: _pendingBody == null && !_revisionConflict,
      child: AlertDialog(
        title: const Text('재료 정보 수정'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                enabled: enabled,
                decoration: const InputDecoration(labelText: '재료명 *'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _category,
                enabled: enabled,
                decoration: const InputDecoration(labelText: '분류'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _baseUnit,
                decoration: InputDecoration(
                  labelText: '원가 계산 단위',
                  helperText: widget.ingredient.priceCount > 0
                      ? '단가 이력이 있어 변경할 수 없습니다.'
                      : null,
                ),
                items: const ['g', 'ml', 'ea']
                    .map((unit) => DropdownMenuItem(
                          value: unit,
                          child: Text(unit),
                        ))
                    .toList(growable: false),
                onChanged: enabled && widget.ingredient.priceCount == 0
                    ? (value) => setState(() => _baseUnit = value ?? _baseUnit)
                    : null,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _supplier,
                enabled: enabled,
                decoration: const InputDecoration(labelText: '공급처'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notes,
                enabled: enabled,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '메모'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isActive,
                title: const Text('활성 재료'),
                onChanged: enabled
                    ? (value) => setState(() => _isActive = value)
                    : null,
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_error, style: const TextStyle(color: Color(0xFFB91C1C))),
              ],
              if (_pendingBody != null && !_saving) ...[
                const SizedBox(height: 8),
                const Text(
                  '결과를 확인하지 못했습니다. 같은 요청 ID와 revision으로 재시도합니다.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving || (_pendingBody != null && !_revisionConflict)
                ? null
                : () => Navigator.pop(context, _revisionConflict),
            child: Text(_revisionConflict ? '닫고 새로고침' : '취소'),
          ),
          FilledButton(
            onPressed: _saving || _revisionConflict ? null : _submit,
            child: Text(
              _saving
                  ? '저장 중...'
                  : _pendingBody == null
                      ? '저장'
                      : '같은 요청 재시도',
            ),
          ),
        ],
      ),
    );
  }
}

class _IngredientCreateDialog extends StatefulWidget {
  const _IngredientCreateDialog();

  @override
  State<_IngredientCreateDialog> createState() =>
      _IngredientCreateDialogState();
}

class _IngredientCreateDialogState extends State<_IngredientCreateDialog> {
  final _name = TextEditingController();
  final _supplier = TextEditingController();
  final _notes = TextEditingController();
  String _category = 'other';
  String _baseUnit = 'g';
  Map<String, dynamic>? _pendingBody;
  bool _saving = false;
  String _error = '';

  @override
  void dispose() {
    _name.dispose();
    _supplier.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (_pendingBody == null) {
      if (_name.text.trim().isEmpty) {
        setState(() => _error = '재료명을 입력해 주세요.');
        return;
      }
      _pendingBody = Map<String, dynamic>.unmodifiable(
        buildCostingIngredientCreatePayload(
          name: _name.text,
          category: _category,
          baseUnit: _baseUnit,
          supplierName: _supplier.text,
          notes: _notes.text,
          requestId: _newCostingRequestId(),
        ),
      );
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await context.read<AppState>().postJson(
            '/api/costing/ingredients',
            body: _pendingBody!,
          );
      if (!mounted) return;
      setState(() {
        _pendingBody = null;
        _saving = false;
      });
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      final status = error is ApiException ? error.statusCode : null;
      setState(() {
        _saving = false;
        _error = error.toString();
        if (status != null && status < 500) _pendingBody = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fieldsEnabled = !_saving && _pendingBody == null;
    return PopScope<bool>(
      canPop: _pendingBody == null,
      child: AlertDialog(
        title: const Text('새 재료 등록'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                enabled: fieldsEnabled,
                decoration: const InputDecoration(labelText: '재료명 *'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: '분류'),
                items: const [
                  ('other', '기타'),
                  ('coffee', '커피'),
                  ('dairy', '유제품'),
                  ('tea', '차'),
                  ('syrup', '시럽'),
                  ('food', '식품'),
                  ('packaging', '포장재'),
                ]
                    .map((item) => DropdownMenuItem(
                          value: item.$1,
                          child: Text(item.$2),
                        ))
                    .toList(growable: false),
                onChanged: fieldsEnabled
                    ? (value) => setState(() => _category = value ?? 'other')
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _baseUnit,
                decoration: const InputDecoration(labelText: '원가 계산 단위 *'),
                items: const [
                  DropdownMenuItem(value: 'g', child: Text('g · 그램')),
                  DropdownMenuItem(value: 'ml', child: Text('ml · 밀리리터')),
                  DropdownMenuItem(value: 'ea', child: Text('ea · 개')),
                ],
                onChanged: fieldsEnabled
                    ? (value) => setState(() => _baseUnit = value ?? 'g')
                    : null,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _supplier,
                enabled: fieldsEnabled,
                decoration: const InputDecoration(labelText: '기본 공급처 (선택)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                enabled: fieldsEnabled,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '메모 (선택)'),
              ),
              const SizedBox(height: 8),
              const Text(
                '재료 등록은 서버 원가표에만 저장됩니다. 단가는 등록 후 상세 화면에서 추가합니다.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_error, style: const TextStyle(color: Color(0xFFB91C1C))),
              ],
              if (_pendingBody != null && !_saving) ...[
                const SizedBox(height: 8),
                const Text(
                  '결과를 확인하지 못했습니다. 같은 요청 ID와 내용을 재시도해 중복 등록을 막습니다.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving || _pendingBody != null
                ? null
                : () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Text(
              _saving
                  ? '저장 중...'
                  : _pendingBody == null
                      ? '등록'
                      : '같은 요청 재시도',
            ),
          ),
        ],
      ),
    );
  }
}

class _IngredientPriceDialog extends StatefulWidget {
  final int ingredientId;
  final String baseUnit;
  final String supplierName;
  final int expectedEditRevision;

  const _IngredientPriceDialog({
    required this.ingredientId,
    required this.baseUnit,
    required this.supplierName,
    required this.expectedEditRevision,
  });

  @override
  State<_IngredientPriceDialog> createState() => _IngredientPriceDialogState();
}

class _IngredientPriceDialogState extends State<_IngredientPriceDialog> {
  final _purchasePrice = TextEditingController();
  final _purchaseQty = TextEditingController();
  final _usableQty = TextEditingController();
  final _effectiveFrom = TextEditingController();
  final _supplier = TextEditingController();
  final _memo = TextEditingController();
  late String _purchaseUnit = widget.baseUnit;
  Map<String, dynamic>? _pendingBody;
  bool _saving = false;
  bool _revisionConflict = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _supplier.text = widget.supplierName;
  }

  @override
  void dispose() {
    _purchasePrice.dispose();
    _purchaseQty.dispose();
    _usableQty.dispose();
    _effectiveFrom.dispose();
    _supplier.dispose();
    _memo.dispose();
    super.dispose();
  }

  String? _buildPayload() {
    final price = _parseNumber(_purchasePrice.text);
    final purchaseQty = _parseNumber(_purchaseQty.text);
    final usableText = _usableQty.text.trim();
    final usableQty = usableText.isEmpty ? null : _parseNumber(usableText);
    if (price == null || !price.isFinite || price <= 0) {
      return '매입금액은 0보다 큰 숫자로 입력해 주세요.';
    }
    if (purchaseQty == null || !purchaseQty.isFinite || purchaseQty <= 0) {
      return '매입 수량은 0보다 큰 숫자로 입력해 주세요.';
    }
    if (usableText.isNotEmpty &&
        (usableQty == null || !usableQty.isFinite || usableQty <= 0)) {
      return '사용 가능량은 0보다 큰 숫자로 입력해 주세요.';
    }
    final autoConvertible = switch (widget.baseUnit) {
      'g' => _purchaseUnit == 'g' || _purchaseUnit == 'kg',
      'ml' => _purchaseUnit == 'ml' || _purchaseUnit == 'l',
      'ea' => _purchaseUnit == 'ea' || _purchaseUnit == 'shot',
      _ => false,
    };
    if (!autoConvertible && usableQty == null) {
      return '이 매입 단위와 원가 계산 단위는 자동 환산되지 않습니다. 사용 가능량을 입력해 주세요.';
    }
    final effective = _effectiveFrom.text.trim();
    if (effective.isNotEmpty &&
        (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(effective) ||
            DateTime.tryParse(effective) == null)) {
      return '적용일은 YYYY-MM-DD 형식으로 입력해 주세요.';
    }
    _pendingBody = Map<String, dynamic>.unmodifiable(
      buildCostingIngredientPricePayload(
        purchasePrice: price,
        purchaseQty: purchaseQty,
        purchaseUnit: _purchaseUnit,
        usableQty: usableQty,
        expectedEditRevision: widget.expectedEditRevision,
        requestId: _newCostingRequestId(),
        effectiveFrom: effective,
        supplierName: _supplier.text,
        memo: _memo.text,
      ),
    );
    return null;
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (_pendingBody == null) {
      final validation = _buildPayload();
      if (validation != null) {
        setState(() => _error = validation);
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await context.read<AppState>().postJson(
            '/api/costing/ingredients/${widget.ingredientId}/prices',
            body: _pendingBody!,
          );
      if (!mounted) return;
      setState(() {
        _pendingBody = null;
        _saving = false;
      });
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      final status = error is ApiException ? error.statusCode : null;
      setState(() {
        _saving = false;
        _error = error.toString();
        if (status == 409) {
          _pendingBody = null;
          _revisionConflict = true;
          _error = '재료가 다른 요청으로 변경되었습니다. 닫고 최신 단가 이력을 다시 불러와 주세요.';
        } else if (status != null && status < 500) {
          _pendingBody = null;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !_saving && _pendingBody == null && !_revisionConflict;
    return PopScope<bool>(
      canPop: _pendingBody == null && !_revisionConflict,
      child: AlertDialog(
        title: const Text('단가 이력 등록'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _purchasePrice,
                enabled: enabled,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: '매입금액 *'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _purchaseQty,
                      enabled: enabled,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: '매입 수량 *'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _purchaseUnit,
                      decoration: const InputDecoration(labelText: '단위'),
                      items: const [
                        'g',
                        'kg',
                        'ml',
                        'l',
                        'ea',
                        'shot',
                        'bag',
                        'pack',
                        'bottle',
                        'box',
                      ]
                          .map((unit) => DropdownMenuItem(
                                value: unit,
                                child: Text(unit),
                              ))
                          .toList(growable: false),
                      onChanged: enabled
                          ? (value) => setState(
                                () => _purchaseUnit = value ?? widget.baseUnit,
                              )
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _usableQty,
                enabled: enabled,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText:
                      '사용 가능량${widget.baseUnit.isEmpty ? '' : ' (${widget.baseUnit})'}',
                  helperText: '자동 단위 환산이 불가능한 경우 필요합니다.',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _effectiveFrom,
                enabled: enabled,
                decoration: const InputDecoration(
                  labelText: '적용일 (선택)',
                  hintText: 'YYYY-MM-DD',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _supplier,
                enabled: enabled,
                decoration: const InputDecoration(labelText: '공급처 (선택)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _memo,
                enabled: enabled,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '메모 (선택)'),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_error, style: const TextStyle(color: Color(0xFFB91C1C))),
              ],
              if (_pendingBody != null && !_saving) ...[
                const SizedBox(height: 8),
                const Text(
                  '결과를 확인하지 못했습니다. 같은 요청 ID와 revision으로 재시도합니다.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving || (_pendingBody != null && !_revisionConflict)
                ? null
                : () => Navigator.pop(context, _revisionConflict),
            child: Text(_revisionConflict ? '닫고 새로고침' : '취소'),
          ),
          FilledButton(
            onPressed: _saving || _revisionConflict ? null : _submit,
            child: Text(
              _saving
                  ? '저장 중...'
                  : _pendingBody == null
                      ? '단가 등록'
                      : '같은 요청 재시도',
            ),
          ),
        ],
      ),
    );
  }
}

String _newCostingRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex =
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

// ─── Temporary recipe calculator ─────────────────────────────────────────────

class _RecipeCalculatorTab extends StatefulWidget {
  const _RecipeCalculatorTab();

  @override
  State<_RecipeCalculatorTab> createState() => _RecipeCalculatorTabState();
}

class _RecipeCalculatorTabState extends State<_RecipeCalculatorTab>
    with AsyncRequestGuard<_RecipeCalculatorTab> {
  final _menuNameController = TextEditingController(text: '임시 계산');
  final _sellingPriceController = TextEditingController();
  final _targetRatioController = TextEditingController(text: '30');
  final List<_CalculatorLine> _lines = [_CalculatorLine()];
  List<Ingredient> _ingredients = const [];
  RecipeCalculateSummary? _summary;
  List<_CalculatedLine> _calculatedLines = const [];
  bool _loading = true;
  bool _calculating = false;
  String _error = '';
  int _calculationRevision = 0;

  @override
  void initState() {
    super.initState();
    _loadIngredients();
  }

  @override
  void dispose() {
    _menuNameController.dispose();
    _sellingPriceController.dispose();
    _targetRatioController.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _loadIngredients() async {
    if (!mounted) return;
    final request = beginAsyncRequest();
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final response = await context.read<AppState>().fetchMapParsed(
            '/api/costing/ingredients',
            parser: _IngredientsTabState._parseIngredients,
            cacheTtl: Duration.zero,
            allowStaleOnError: false,
          );
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _ingredients = response.data
            .where((ingredient) => ingredient.currentUnitCost != null)
            .toList(growable: false);
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

  Future<void> _calculate() async {
    final sellingPrice =
        _parseOptionalNonnegativeInt(_sellingPriceController.text);
    final targetPercent = _parseNumber(_targetRatioController.text);
    if (_sellingPriceController.text.trim().isNotEmpty &&
        sellingPrice == null) {
      setState(() => _error = '판매가는 0 이상의 숫자로 입력해 주세요.');
      return;
    }
    if (targetPercent == null || targetPercent <= 0 || targetPercent >= 100) {
      setState(() => _error = '목표 원가율은 0보다 크고 100보다 작아야 합니다.');
      return;
    }

    final items = <CostingCalculationItem>[];
    for (final line in _lines) {
      final ingredient = _ingredientById(line.ingredientId);
      final quantity = _parseNumber(line.quantityController.text);
      if (ingredient == null || quantity == null || quantity <= 0) {
        setState(() => _error = '모든 재료와 0보다 큰 사용량을 입력해 주세요.');
        return;
      }
      items.add(CostingCalculationItem(
        ingredientId: ingredient.ingredientId,
        quantity: quantity,
        unit: ingredient.baseUnit,
      ));
    }

    if (!mounted) return;
    final request = beginAsyncRequest();
    final calculationRevision = ++_calculationRevision;
    final appState = context.read<AppState>();
    setState(() {
      _calculating = true;
      _error = '';
      _summary = null;
      _calculatedLines = const [];
    });
    try {
      final response = await appState.postJson(
        '/api/costing/calculate',
        body: {
          'menu_name': _menuNameController.text.trim().isEmpty
              ? '임시 계산'
              : _menuNameController.text.trim(),
          if (sellingPrice != null) 'selling_price': sellingPrice,
          'target_cost_ratio': targetPercent / 100,
          'status': 'draft',
          'items': buildCostingItemsPayload(items),
        },
      );
      final rawError = response['error']?.toString().trim() ?? '';
      if (rawError.isNotEmpty) throw FormatException(rawError);
      final summarySource = response['summary'];
      if (summarySource is! Map) {
        throw const FormatException('계산 결과 형식이 올바르지 않습니다.');
      }
      final rawItems = response['items'];
      final calculatedLines = rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((item) => _CalculatedLine.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList(growable: false)
          : const <_CalculatedLine>[];
      if (!isCurrentAsyncRequest(request) ||
          calculationRevision != _calculationRevision) {
        return;
      }
      setState(() {
        _summary = RecipeCalculateSummary.fromJson(
          Map<String, dynamic>.from(summarySource),
        );
        _calculatedLines = calculatedLines;
        _calculating = false;
      });
    } catch (error) {
      if (!isCurrentAsyncRequest(request) ||
          calculationRevision != _calculationRevision) {
        return;
      }
      setState(() {
        _error = error.toString();
        _calculating = false;
      });
    }
  }

  Ingredient? _ingredientById(int? id) {
    if (id == null) return null;
    for (final ingredient in _ingredients) {
      if (ingredient.ingredientId == id) return ingredient;
    }
    return null;
  }

  void _invalidateCalculation() {
    _calculationRevision += 1;
    if (_summary == null && _calculatedLines.isEmpty && !_calculating) {
      return;
    }
    setState(() {
      _summary = null;
      _calculatedLines = const [];
      _calculating = false;
    });
  }

  void _addLine() {
    setState(() {
      _lines.add(_CalculatorLine());
      _calculationRevision += 1;
      _summary = null;
      _calculatedLines = const [];
      _calculating = false;
    });
  }

  void _removeLine(int index) {
    if (_lines.length == 1) return;
    setState(() {
      _lines.removeAt(index).dispose();
      _calculationRevision += 1;
      _summary = null;
      _calculatedLines = const [];
      _calculating = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_ingredients.isEmpty && _error.isNotEmpty) {
      return EmptyState(
        title: '계산용 재료를 불러오지 못했습니다.',
        message: _error,
        action: FilledButton(
            onPressed: _loadIngredients, child: const Text('다시 시도')),
      );
    }
    if (_ingredients.isEmpty) {
      return const EmptyState(title: '단가가 등록된 활성 재료가 없습니다.');
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Panel(
          title: '임시 레시피 계산',
          subtitle: '계산 결과만 확인하며 레시피로 저장하지 않습니다.',
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _loading || _calculating ? null : _loadIngredients,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('재료·단가 새로고침'),
                ),
              ),
              TextField(
                controller: _menuNameController,
                onChanged: (_) => _invalidateCalculation(),
                decoration: const InputDecoration(labelText: '메뉴명'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _sellingPriceController,
                      onChanged: (_) => _invalidateCalculation(),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '판매가 (선택)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _targetRatioController,
                      onChanged: (_) => _invalidateCalculation(),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: '목표 원가율 (%)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ..._lines.asMap().entries.map((entry) {
                final index = entry.key;
                final line = entry.value;
                final ingredient = _ingredientById(line.ingredientId);
                return Padding(
                  key: line.key,
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<int>(
                          initialValue: line.ingredientId,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: '재료'),
                          items: _ingredients
                              .map((item) => DropdownMenuItem(
                                    value: item.ingredientId,
                                    child:
                                        Text('${item.name} (${item.baseUnit})'),
                                  ))
                              .toList(growable: false),
                          onChanged: (value) => setState(() {
                            line.ingredientId = value;
                            _calculationRevision += 1;
                            _summary = null;
                            _calculatedLines = const [];
                            _calculating = false;
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: line.quantityController,
                          onChanged: (_) => _invalidateCalculation(),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            labelText:
                                '사용량${ingredient == null ? '' : ' (${ingredient.baseUnit})'}',
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _lines.length == 1
                            ? null
                            : () => _removeLine(index),
                        tooltip: '재료 제거',
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                );
              }),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addLine,
                  icon: const Icon(Icons.add),
                  label: const Text('재료 추가'),
                ),
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error,
                    style: const TextStyle(color: Color(0xFFDC2626)),
                  ),
                ),
              FilledButton.icon(
                onPressed: _calculating ? null : _calculate,
                icon: const Icon(Icons.calculate_outlined),
                label: Text(_calculating ? '계산 중...' : '원가 계산'),
              ),
            ],
          ),
        ),
        if (_summary != null) ...[
          const SizedBox(height: 16),
          _MetricGrid(
            cards: [
              StatCard(
                  label: '총 원가',
                  value: '${_won(_summary!.totalCost)}원',
                  accent: true),
              StatCard(
                  label: '원가율',
                  value: '${(_summary!.costRatio * 100).toStringAsFixed(1)}%'),
              StatCard(
                  label: '예상 마진', value: '${_won(_summary!.marginAmount)}원'),
              StatCard(
                  label: '권장 판매가',
                  value: '${_won(_summary!.recommendedPrice)}원'),
            ],
          ),
          const SizedBox(height: 16),
          Panel(
            title: '재료별 원가',
            child: Column(
              children: _calculatedLines
                  .map((line) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(line.name),
                        subtitle: Text('${line.quantity} ${line.unit}'),
                        trailing: Text(
                          '${_won(line.lineCost)}원',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ))
                  .toList(growable: false),
            ),
          ),
        ],
      ],
    );
  }
}

class _CalculatorLine {
  final Key key = UniqueKey();
  int? ingredientId;
  final TextEditingController quantityController = TextEditingController();

  void dispose() => quantityController.dispose();
}

class _CalculatedLine {
  final String name;
  final double quantity;
  final String unit;
  final int lineCost;

  const _CalculatedLine({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.lineCost,
  });

  factory _CalculatedLine.fromJson(Map<String, dynamic> json) {
    return _CalculatedLine(
      name: json['ingredient_name']?.toString() ?? '',
      quantity: _parseNumber(json['quantity']?.toString() ?? '') ?? 0,
      unit: json['unit']?.toString() ?? '',
      lineCost:
          _parseOptionalNonnegativeInt(json['line_cost']?.toString() ?? '') ??
              0,
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

void _pushRecipeDetail(BuildContext context, RecipeSummaryRow recipe) {
  AppNavigation.pushGuarded(
    context,
    minimumRole: UserRole.operator,
    child: RecipeDetailScreen(
      recipeId: recipe.recipeId,
      recipeName: recipe.menuName,
    ),
  );
}

void _pushIngredientDetail(
  BuildContext context,
  Ingredient ingredient, {
  Future<void> Function()? onUpdated,
}) {
  AppNavigation.pushGuarded<void>(
    context,
    minimumRole: UserRole.operator,
    child: IngredientDetailScreen(
      ingredientId: ingredient.ingredientId,
      ingredientName: ingredient.name,
      onUpdated: onUpdated,
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

String _safeDateLabel(String value) {
  final normalized = value.trim().replaceFirst(' ', 'T');
  final parsed = DateTime.tryParse(normalized);
  if (parsed == null) return value;
  return '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
}

double? _parseNumber(String value) {
  final normalized = value.trim().replaceAll(',', '');
  if (normalized.isEmpty) return null;
  return double.tryParse(normalized);
}

int? _parseOptionalNonnegativeInt(String value) {
  final normalized = value.trim().replaceAll(',', '');
  if (normalized.isEmpty) return null;
  final parsed = int.tryParse(normalized);
  return parsed != null && parsed >= 0 ? parsed : null;
}
