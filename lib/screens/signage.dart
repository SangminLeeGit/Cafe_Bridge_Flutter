import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/async_request_guard.dart';
import '../navigation/app_navigation.dart';
import '../state/app_state.dart';
import '../widgets/empty_state.dart';

const bool _allowStructuralEditing = false;

// ─── 모델 ─────────────────────────────────────────────────────────────────────

dynamic _cloneJsonValue(dynamic value) {
  if (value is Map) {
    return value.map<String, dynamic>(
      (key, nestedValue) =>
          MapEntry(key.toString(), _cloneJsonValue(nestedValue)),
    );
  }
  if (value is List) {
    return value.map(_cloneJsonValue).toList();
  }
  return value;
}

Map<String, dynamic> _stringKeyedMap(dynamic value) {
  if (value is! Map) {
    return <String, dynamic>{};
  }
  return value.map<String, dynamic>(
    (key, nestedValue) => MapEntry(key.toString(), nestedValue),
  );
}

Map<String, dynamic> _extractExtraFields(
  Map<String, dynamic> source,
  Set<String> knownKeys,
) {
  final extras = <String, dynamic>{};
  for (final entry in source.entries) {
    if (!knownKeys.contains(entry.key)) {
      extras[entry.key] = _cloneJsonValue(entry.value);
    }
  }
  return extras;
}

Map<String, dynamic> _cloneJsonMap(Map<String, dynamic> source) {
  return source.map(
    (key, value) => MapEntry(key, _cloneJsonValue(value)),
  );
}

class _SignageItem {
  String korean;
  String english;
  int price;
  String note;
  final Map<String, dynamic> extraFields;

  _SignageItem({
    required this.korean,
    required this.english,
    required this.price,
    this.note = '',
    Map<String, dynamic>? extraFields,
  }) : extraFields = extraFields ?? <String, dynamic>{};

  factory _SignageItem.fromJson(Map<String, dynamic> j) => _SignageItem(
        korean: (j['korean'] ?? '').toString(),
        english: (j['english'] ?? '').toString(),
        price: parseSignagePrice(j['price']) ?? 0,
        note: (j['note'] ?? '').toString(),
        extraFields:
            _extractExtraFields(j, {'korean', 'english', 'price', 'note'}),
      );

  Map<String, dynamic> toJson() => {
        ...extraFields,
        'korean': korean,
        'english': english,
        'price': price,
        'note': note.isEmpty ? null : note,
      };

  _SignageItem clone() => _SignageItem(
        korean: korean,
        english: english,
        price: price,
        note: note,
        extraFields: _cloneJsonMap(extraFields),
      );
}

class _SignageCategory {
  String id;
  String title;
  String description;
  List<_SignageItem> items;
  final Map<String, dynamic> extraFields;

  _SignageCategory({
    required this.id,
    required this.title,
    this.description = '',
    required this.items,
    Map<String, dynamic>? extraFields,
  }) : extraFields = extraFields ?? <String, dynamic>{};

  factory _SignageCategory.fromJson(Map<String, dynamic> j) => _SignageCategory(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        items: (j['items'] is List ? j['items'] as List : const [])
            .whereType<Map>()
            .map((e) => _SignageItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        extraFields:
            _extractExtraFields(j, {'id', 'title', 'description', 'items'}),
      );

  Map<String, dynamic> toJson() => {
        ...extraFields,
        'id': id,
        'title': title,
        'description': description.isEmpty ? null : description,
        'items': items.map((e) => e.toJson()).toList(),
      };

  _SignageCategory clone() => _SignageCategory(
        id: id,
        title: title,
        description: description,
        items: items.map((e) => e.clone()).toList(),
        extraFields: _cloneJsonMap(extraFields),
      );
}

class _SignageMenu {
  String shopName;
  String shopNameLine1;
  String shopNameLine2;
  String announcementText;
  List<_SignageCategory> categories;
  final Map<String, dynamic> extraFields;
  final Map<String, dynamic> announcementExtraFields;

  _SignageMenu({
    required this.shopName,
    required this.shopNameLine1,
    required this.shopNameLine2,
    required this.announcementText,
    required this.categories,
    Map<String, dynamic>? extraFields,
    Map<String, dynamic>? announcementExtraFields,
  })  : extraFields = extraFields ?? <String, dynamic>{},
        announcementExtraFields =
            announcementExtraFields ?? <String, dynamic>{};

  factory _SignageMenu.fromJson(Map<String, dynamic> j) {
    final announcement = _stringKeyedMap(j['announcement']);
    final text = (announcement['text'] ?? '').toString();
    return _SignageMenu(
      shopName: (j['shopName'] ?? '').toString(),
      shopNameLine1: (j['shopNameLine1'] ?? '').toString(),
      shopNameLine2: (j['shopNameLine2'] ?? '').toString(),
      announcementText: text,
      categories: (j['categories'] is List ? j['categories'] as List : const [])
          .whereType<Map>()
          .map((e) => _SignageCategory.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      extraFields: _extractExtraFields(
        j,
        {
          'shopName',
          'shopNameLine1',
          'shopNameLine2',
          'announcement',
          'categories'
        },
      ),
      announcementExtraFields: _extractExtraFields(announcement, {'text'}),
    );
  }

  Map<String, dynamic> toJson() => {
        ...extraFields,
        'shopName': shopName,
        'shopNameLine1': shopNameLine1,
        'shopNameLine2': shopNameLine2,
        'announcement': {
          ...announcementExtraFields,
          'text': announcementText,
        },
        'categories': categories.map((e) => e.toJson()).toList(),
      };

  _SignageMenu clone() => _SignageMenu(
        shopName: shopName,
        shopNameLine1: shopNameLine1,
        shopNameLine2: shopNameLine2,
        announcementText: announcementText,
        categories: categories.map((e) => e.clone()).toList(),
        extraFields: _cloneJsonMap(extraFields),
        announcementExtraFields: _cloneJsonMap(announcementExtraFields),
      );
}

// ─── 메인 화면 ────────────────────────────────────────────────────────────────

class SignageScreen extends StatefulWidget {
  const SignageScreen({super.key});

  @override
  State<SignageScreen> createState() => _SignageScreenState();
}

class _SignageScreenState extends State<SignageScreen>
    with AsyncRequestGuard<SignageScreen> {
  _SignageMenu? _saved;
  _SignageMenu? _draft;
  bool _loading = true;
  String _error = '';
  bool _pushing = false;
  bool _dirty = false;
  String _successMessage = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final request = beginAsyncRequest();
    final appState = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = '';
      _successMessage = '';
    });
    try {
      final result = await appState.fetchMapParsed<_SignageMenu>(
        '/api/signage/menu',
        parser: _SignageMenu.fromJson,
        cacheTtl: Duration.zero,
      );
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _saved = result.data;
        _draft = result.data.clone();
        _dirty = false;
        _loading = false;
      });
    } catch (e) {
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
    if (_successMessage.isNotEmpty) setState(() => _successMessage = '');
  }

  void _resetDraft() {
    if (_saved == null) return;
    setState(() {
      _draft = _saved!.clone();
      _dirty = false;
      _successMessage = '';
    });
  }

  Future<void> _handleBlockedPop() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('변경사항 폐기'),
        content: const Text('저장되지 않은 변경사항이 있습니다. 이 화면을 나가시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('계속 편집'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    setState(() => _dirty = false);
    Navigator.of(context).pop();
  }

  Future<void> _push() async {
    final draft = _draft;
    if (draft == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('메뉴판에 반영'),
        content: const Text('현재 편집된 내용을 사이니지 서버에 즉시 반영합니다.\n계속하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('반영'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _pushing = true;
      _error = '';
      _successMessage = '';
    });

    try {
      final appState = context.read<AppState>();
      final result = await appState.postJson(
        '/api/signage/menu',
        body: draft.toJson(),
      );
      if (!mounted) return;
      final rawBackup = result['backup'];
      final backup = rawBackup is String && rawBackup.trim().isNotEmpty
          ? rawBackup.trim()
          : null;
      setState(() {
        _saved = draft.clone();
        _dirty = false;
        _pushing = false;
        _successMessage = backup != null
            ? '메뉴판이 업데이트되었습니다. (백업: ${backup.split('/').last})'
            : '메뉴판이 성공적으로 업데이트되었습니다.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _pushing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF0D9488)));
    }

    if (_error.isNotEmpty && _draft == null) {
      return EmptyState(
        title: '메뉴판 데이터를 불러오지 못했습니다.',
        message: _error,
        action: FilledButton(onPressed: _load, child: const Text('다시 시도')),
      );
    }

    final draft = _draft;
    if (draft == null) {
      return EmptyState(
        title: '데이터 없음',
        action: FilledButton(onPressed: _load, child: const Text('새로고침')),
      );
    }

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBlockedPop();
      },
      child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
            children: [
              // 오류/성공 배너
              if (_error.isNotEmpty) _Banner(text: _error, isError: true),
              if (_successMessage.isNotEmpty)
                _Banner(text: _successMessage, isError: false),

              const _EditingNotice(),

              // 가게 정보
              _SectionCard(
                title: '가게 정보',
                child: Column(
                  children: [
                    _LabeledField(
                      label: '가게명',
                      value: draft.shopName,
                      onChanged: (v) {
                        draft.shopName = v;
                        _markDirty();
                      },
                    ),
                    const SizedBox(height: 8),
                    _LabeledField(
                      label: '가게명 1줄',
                      value: draft.shopNameLine1,
                      onChanged: (v) {
                        draft.shopNameLine1 = v;
                        _markDirty();
                      },
                    ),
                    const SizedBox(height: 8),
                    _LabeledField(
                      label: '가게명 2줄',
                      value: draft.shopNameLine2,
                      onChanged: (v) {
                        draft.shopNameLine2 = v;
                        _markDirty();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 공지 사항
              _SectionCard(
                title: '공지 사항',
                child: _LabeledField(
                  label: '공지 내용',
                  value: draft.announcementText,
                  maxLines: 3,
                  onChanged: (v) {
                    draft.announcementText = v;
                    _markDirty();
                  },
                ),
              ),
              const SizedBox(height: 12),

              // 카테고리 목록
              ...draft.categories.asMap().entries.map((entry) {
                final catIdx = entry.key;
                final cat = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _CategoryCard(
                    category: cat,
                    onChanged: _markDirty,
                    onDelete: () => setState(() {
                      draft.categories.removeAt(catIdx);
                      _markDirty();
                    }),
                  ),
                );
              }),

              // 카테고리 추가
              if (_allowStructuralEditing)
                OutlinedButton.icon(
                  onPressed: () => setState(() {
                    draft.categories.add(
                      _SignageCategory(id: '', title: '', items: []),
                    );
                    _markDirty();
                  }),
                  icon: const Icon(Icons.add),
                  label: const Text('카테고리 추가'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0D9488),
                    side: const BorderSide(color: Color(0xFF0D9488)),
                  ),
                ),
            ],
          ),

          // 하단 스티키 액션 바
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ActionBar(
              dirty: _dirty,
              pushing: _pushing,
              onRefresh: _loading || _pushing ? null : _load,
              onReset: _dirty && !_pushing ? _resetDraft : null,
              onPush: _dirty && !_pushing ? _push : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 서브 위젯 ────────────────────────────────────────────────────────────────

class _Banner extends StatelessWidget {
  final String text;
  final bool isError;

  const _Banner({required this.text, required this.isError});

  @override
  Widget build(BuildContext context) {
    final bg = isError ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7);
    final border = isError ? const Color(0xFFEF4444) : const Color(0xFF22C55E);
    final fg = isError ? const Color(0xFFB91C1C) : const Color(0xFF15803D);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(color: fg, fontSize: 13)),
    );
  }
}

class _EditingNotice extends StatelessWidget {
  const _EditingNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDFA),
        border: Border.all(color: const Color(0xFF99F6E4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        '이 화면에서는 가게명, 공지, 카테고리와 메뉴 기본 정보만 편집할 수 있습니다. 표시되지 않은 설정은 변경하지 않고 그대로 보존합니다.',
        style: TextStyle(fontSize: 12, color: Color(0xFF0F766E)),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _LabeledField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final int maxLines;

  const _LabeledField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.maxLines = 1,
  });

  @override
  State<_LabeledField> createState() => _LabeledFieldState();
}

class _LabeledFieldState extends State<_LabeledField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_LabeledField old) {
    super.didUpdateWidget(old);
    if (widget.value != _ctrl.text) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _ctrl,
          maxLines: widget.maxLines,
          onChanged: widget.onChanged,
          style: const TextStyle(fontSize: 14),
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
      ],
    );
  }
}

// ─── 카테고리 카드 ────────────────────────────────────────────────────────────

class _CategoryCard extends StatelessWidget {
  final _SignageCategory category;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  const _CategoryCard({
    required this.category,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final itemCount = category.items.length;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 카테고리 헤더
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            color: const Color(0xFF0D9488),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.menu_book_outlined,
                              size: 16, color: Colors.white),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              category.title.isEmpty
                                  ? '(제목 없음)'
                                  : category.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$itemCount개',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (category.id.isNotEmpty ||
                          category.description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            [category.id, category.description]
                                .where((s) => s.isNotEmpty)
                                .join(' · '),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_allowStructuralEditing)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    tooltip: '카테고리 삭제',
                    color: Colors.white70,
                    onPressed: onDelete,
                  ),
              ],
            ),
          ),

          // 카테고리 필드 편집
          if (_allowStructuralEditing)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LabeledField(
                    label: '카테고리 제목',
                    value: category.title,
                    onChanged: (v) {
                      category.title = v;
                      onChanged();
                    },
                  ),
                  const SizedBox(height: 8),
                  _LabeledField(
                    label: 'ID (영문)',
                    value: category.id,
                    onChanged: (v) {
                      category.id = v;
                      onChanged();
                    },
                  ),
                  const SizedBox(height: 8),
                  _LabeledField(
                    label: '설명 (선택)',
                    value: category.description,
                    onChanged: (v) {
                      category.description = v;
                      onChanged();
                    },
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),
          const Divider(height: 1, indent: 14, endIndent: 14),

          if (itemCount == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  '품목이 없습니다. 아래 버튼으로 추가하세요.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 0),
              itemCount: itemCount,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, idx) => _ItemRow(
                item: category.items[idx],
                index: idx + 1,
                onChanged: onChanged,
                onDelete: () {
                  category.items.removeAt(idx);
                  onChanged();
                },
              ),
            ),

          // 품목 추가 버튼
          if (_allowStructuralEditing)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: OutlinedButton.icon(
                onPressed: () {
                  category.items
                      .add(_SignageItem(korean: '', english: '', price: 0));
                  onChanged();
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('품목 추가', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0D9488),
                  side: const BorderSide(color: Color(0xFF0D9488)),
                  minimumSize: const Size(double.infinity, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── 아이템 행 (compact summary tile) ────────────────────────────────────────

String _priceFormatted(int price) => price
    .toString()
    .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

class _ItemRow extends StatelessWidget {
  final _SignageItem item;
  final int index;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  const _ItemRow({
    required this.item,
    required this.index,
    required this.onChanged,
    required this.onDelete,
  });

  void _openEditSheet(BuildContext context) {
    AppNavigation.pushGuarded(
      context,
      minimumRole: UserRole.operator,
      child: _ItemEditSheet(
        item: item,
        index: index,
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasEnglish = item.english.isNotEmpty;
    final hasNote = item.note.isNotEmpty;
    return InkWell(
      onTap: () => _openEditSheet(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 번호 배지
            Container(
              width: 24,
              height: 24,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D9488),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                '$index',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            // 이름 + 영문/비고
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.korean.isEmpty ? '(이름 없음)' : item.korean,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: item.korean.isEmpty
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF0F172A),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hasEnglish || hasNote)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        [
                          if (hasEnglish) item.english,
                          if (hasNote) item.note,
                        ].join(' · '),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 가격
            Text(
              '₩${_priceFormatted(item.price)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F766E),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.edit_outlined, size: 15, color: Color(0xFFCBD5E1)),
            // 삭제 버튼
            if (_allowStructuralEditing)
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                tooltip: '삭제',
                color: const Color(0xFF94A3B8),
                onPressed: onDelete,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── 품목 편집 Screen ────────────────────────────────────────────────────────

class _ItemEditSheet extends StatefulWidget {
  final _SignageItem item;
  final int index;
  final VoidCallback onChanged;

  const _ItemEditSheet({
    required this.item,
    required this.index,
    required this.onChanged,
  });

  @override
  State<_ItemEditSheet> createState() => _ItemEditSheetState();
}

class _ItemEditSheetState extends State<_ItemEditSheet> {
  late final TextEditingController _koreanCtrl;
  late final TextEditingController _englishCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _noteCtrl;
  String? _priceError;
  bool _dirty = false;
  bool _committed = false;

  @override
  void initState() {
    super.initState();
    _koreanCtrl = TextEditingController(text: widget.item.korean);
    _englishCtrl = TextEditingController(text: widget.item.english);
    _priceCtrl = TextEditingController(text: widget.item.price.toString());
    _noteCtrl = TextEditingController(text: widget.item.note);
    for (final controller in [
      _koreanCtrl,
      _englishCtrl,
      _priceCtrl,
      _noteCtrl
    ]) {
      controller.addListener(_updateDirtyState);
    }
  }

  @override
  void dispose() {
    _koreanCtrl.dispose();
    _englishCtrl.dispose();
    _priceCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final price = parseSignagePrice(_priceCtrl.text);
    if (price == null || price < 0) {
      setState(() => _priceError = '0 이상의 숫자를 입력해 주세요.');
      return;
    }
    widget.item.korean = _koreanCtrl.text;
    widget.item.english = _englishCtrl.text;
    widget.item.price = price;
    widget.item.note = _noteCtrl.text;
    _committed = true;
    widget.onChanged();
    Navigator.of(context).pop();
  }

  void _updateDirtyState() {
    final nextDirty = _koreanCtrl.text != widget.item.korean ||
        _englishCtrl.text != widget.item.english ||
        _priceCtrl.text != widget.item.price.toString() ||
        _noteCtrl.text != widget.item.note;
    if (nextDirty != _dirty || _priceError != null) {
      setState(() {
        _dirty = nextDirty;
        _priceError = null;
      });
    }
  }

  Future<void> _handleBlockedPop() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('편집 내용 폐기'),
        content: const Text('저장하지 않은 품목 편집 내용을 버리시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('계속 편집'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('버리기'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    _committed = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _committed || !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBlockedPop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('품목 편집'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: const Color(0xFFE2E8F0)),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D9488),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${widget.index}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    '메뉴 항목 정보',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _SheetField(
                label: '한글명',
                controller: _koreanCtrl,
                hint: '메뉴 이름',
                autofocus: true,
              ),
              const SizedBox(height: 14),
              _SheetField(
                label: 'English',
                controller: _englishCtrl,
                hint: 'Menu name',
              ),
              const SizedBox(height: 14),
              _SheetField(
                label: '가격 (원)',
                controller: _priceCtrl,
                hint: '0',
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
                errorText: _priceError,
              ),
              const SizedBox(height: 14),
              _SheetField(
                label: '비고 (선택)',
                controller: _noteCtrl,
                hint: '예: 매운맛, 계절한정 등',
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0D9488),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text('저장', style: TextStyle(fontSize: 15)),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType keyboardType;
  final TextAlign textAlign;
  final bool autofocus;
  final String? errorText;

  const _SheetField({
    required this.label,
    required this.controller,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.textAlign = TextAlign.start,
    this.autofocus = false,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textAlign: textAlign,
          autofocus: autofocus,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            border: const OutlineInputBorder(),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }
}

int? parseSignagePrice(Object? value) {
  if (value is int) return value;
  if (value is double && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  final normalized = value?.toString().trim().replaceAll(',', '') ?? '';
  return int.tryParse(normalized);
}

// ─── 하단 액션 바 ─────────────────────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  final bool dirty;
  final bool pushing;
  final VoidCallback? onRefresh;
  final VoidCallback? onReset;
  final VoidCallback? onPush;

  const _ActionBar({
    required this.dirty,
    required this.pushing,
    required this.onRefresh,
    required this.onReset,
    required this.onPush,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, bottomPadding + 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: dirty ? const Color(0xFF0D9488) : const Color(0xFFE2E8F0),
            width: dirty ? 2 : 1,
          ),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                dirty ? Icons.edit_outlined : Icons.check_circle_outline,
                size: 14,
                color:
                    dirty ? const Color(0xFF0F766E) : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  dirty ? '저장되지 않은 변경사항' : '저장된 상태',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: dirty
                        ? const Color(0xFF0F766E)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onRefresh,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('새로고침', style: TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onReset,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('되돌리기', style: TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: onPush,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9488),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    pushing ? '반영 중...' : '메뉴판에 반영',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
