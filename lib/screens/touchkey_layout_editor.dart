import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/async_request_guard.dart';
import '../models/editor_context.dart';
import '../models/touchkey_layout.dart';
import '../services/api.dart';
import '../state/app_state.dart';
import '../widgets/empty_state.dart';

class TouchkeyLayoutEditorScreen extends StatefulWidget {
  final String classCode;
  final String sortValue;
  final String className;
  final int page;

  const TouchkeyLayoutEditorScreen({
    super.key,
    required this.classCode,
    required this.sortValue,
    required this.className,
    required this.page,
  });

  @override
  State<TouchkeyLayoutEditorScreen> createState() =>
      _TouchkeyLayoutEditorScreenState();
}

class _TouchkeyLayoutEditorScreenState extends State<TouchkeyLayoutEditorScreen>
    with AsyncRequestGuard<TouchkeyLayoutEditorScreen> {
  TouchkeyLayoutEnvelope? _envelope;
  Map<String, String?> _placements = const {};
  bool _loading = true;
  bool _saving = false;
  bool _contextCanSaveDraft = false;
  String _capabilityMessage = '';
  String _error = '';
  String _successMessage = '';
  bool _revisionConflict = false;
  _PendingTouchkeySave? _pendingSave;

  bool get _dirty {
    final envelope = _envelope;
    if (envelope == null) {
      return false;
    }
    if (envelope.saved.placements.length != _placements.length) return true;
    return !envelope.saved.placements.entries
        .every((entry) => _placements[entry.key] == entry.value);
  }

  bool get _canEdit {
    final envelope = _envelope;
    return envelope != null &&
        _contextCanSaveDraft &&
        envelope.canEdit &&
        envelope.definition.complete &&
        envelope.definition.hasSafeDimensions &&
        envelope.base.complete &&
        envelope.saved.complete &&
        !_loading &&
        _pendingSave == null &&
        !_revisionConflict;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final request = beginAsyncRequest();
    final appState = context.read<AppState>();
    setState(() {
      _loading = true;
      _envelope = null;
      _placements = const {};
      _contextCanSaveDraft = false;
      _capabilityMessage = '';
      _error = '';
      _successMessage = '';
      _revisionConflict = false;
      _pendingSave = null;
    });
    try {
      final editorResult = await appState.fetchMapParsed<EditorContext>(
        '/api/editor/context',
        parser: EditorContext.fromJson,
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      if (!isCurrentAsyncRequest(request)) return;
      final editor = editorResult.data;
      if (editor.scopeId == null || editor.scopeId!.trim().isEmpty) {
        throw StateError('편집 범위가 설정되지 않아 터치키 초안을 조회할 수 없습니다.');
      }
      final capability = editor.capability('save_touchkey_draft');
      setState(() {
        _contextCanSaveDraft = capability?.enabled ?? false;
        _capabilityMessage = capability?.message.trim().isNotEmpty == true
            ? capability!.message
            : '서버에서 터치키 초안 저장을 허용하지 않습니다.';
      });

      final response = await appState.fetchMapParsed<TouchkeyLayoutEnvelope>(
        '/api/editor/touchkey/layout',
        params: {
          'class_code': widget.classCode,
          'sort_value': widget.sortValue,
          'page': widget.page,
        },
        parser: TouchkeyLayoutEnvelope.fromJson,
        cacheTtl: Duration.zero,
        allowStaleOnError: false,
      );
      if (!isCurrentAsyncRequest(request)) return;
      if (response.data.scopeId != editor.scopeId) {
        throw const FormatException('터치키 초안의 편집 범위가 현재 세션과 다릅니다.');
      }
      setState(() {
        _envelope = response.data;
        _placements = Map<String, String?>.from(response.data.saved.placements);
        _loading = false;
      });
    } catch (error) {
      if (!isCurrentAsyncRequest(request)) return;
      setState(() {
        _error = error.toString().replaceFirst('Bad state: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _reloadWithConfirmation() async {
    if (_pendingSave != null) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('편집 내용 다시 불러오기'),
          content: const Text('저장하지 않은 슬롯 변경은 사라집니다. 서버 초안을 다시 불러올까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('계속 편집'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('다시 불러오기'),
            ),
          ],
        ),
      );
      if (!mounted || discard != true) return;
    }
    await _load();
  }

  Future<void> _selectSlot(String key) async {
    final envelope = _envelope;
    if (!_canEdit || envelope == null) return;
    final currentCode = _placements[key];
    final products = envelope.products.values
        .where((product) => product.placeable || product.code == currentCode)
        .toList(growable: false)
      ..sort((left, right) {
        final byName =
            left.name.toLowerCase().compareTo(right.name.toLowerCase());
        return byName == 0 ? left.code.compareTo(right.code) : byName;
      });
    final choice = await showModalBottomSheet<_TouchkeyProductChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TouchkeyProductPicker(
        products: products,
        selectedCode: currentCode,
      ),
    );
    if (!mounted || choice == null) return;
    final selectedCode = choice.code;
    if (selectedCode != null &&
        _placements.entries.any(
          (entry) => entry.key != key && entry.value == selectedCode,
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('같은 상품을 두 슬롯에 배치할 수 없습니다.')),
      );
      return;
    }
    setState(() {
      _placements = {..._placements, key: selectedCode};
      _successMessage = '';
      _error = '';
    });
  }

  Future<void> _saveDraft() async {
    final envelope = _envelope;
    if (!mounted || envelope == null || _saving || _revisionConflict) return;
    if (_pendingSave == null && (!_canEdit || !_dirty)) return;

    if (_pendingSave == null) {
      try {
        final requestId = _newUuidV4();
        final payload = buildTouchkeyLayoutSavePayload(
          envelope: envelope,
          placements: _placements,
          requestId: requestId,
        );
        final slots = (payload['slots'] as List)
            .map((slot) => Map<String, dynamic>.unmodifiable(
                  Map<String, dynamic>.from(slot as Map),
                ))
            .toList(growable: false);
        _pendingSave = _PendingTouchkeySave(
          body: Map<String, dynamic>.unmodifiable({...payload, 'slots': slots}),
        );
      } catch (error) {
        setState(
            () => _error = error.toString().replaceFirst('Bad state: ', ''));
        return;
      }
    }

    final pending = _pendingSave!;
    final request = beginAsyncRequest();
    setState(() {
      _saving = true;
      _error = '';
      _successMessage = '';
    });
    try {
      final response = await context.read<AppState>().postJson(
            '/api/editor/touchkey/layouts/${Uri.encodeComponent(envelope.definition.layoutId)}',
            method: 'PUT',
            body: pending.body,
          );
      final updated = TouchkeyLayoutEnvelope.fromJson(response);
      if (!isCurrentAsyncRequest(request)) return;
      if (updated.scopeId != envelope.scopeId) {
        throw const FormatException('저장 응답의 편집 범위가 현재 세션과 다릅니다.');
      }
      setState(() {
        _envelope = updated;
        _placements = Map<String, String?>.from(updated.saved.placements);
        _pendingSave = null;
        _saving = false;
        _revisionConflict = false;
        _successMessage = '서버 초안을 저장했습니다. POS 변경은 실행하지 않았습니다.';
      });
    } catch (error) {
      if (!isCurrentAsyncRequest(request)) return;
      final status = error is ApiException ? error.statusCode : null;
      setState(() {
        _saving = false;
        _error = error.toString();
        if (status == 409) {
          _pendingSave = null;
          _revisionConflict = true;
        } else if (status != null && status < 500) {
          _pendingSave = null;
        }
        // Transport/5xx outcomes are ambiguous; keep the immutable request so
        // a retry reuses its original request ID and byte-for-byte body.
      });
    }
  }

  String _newUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  @override
  Widget build(BuildContext context) {
    final envelope = _envelope;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.className.isEmpty ? '터치키 초안' : widget.className),
        actions: [
          IconButton(
            tooltip: '서버 초안 다시 불러오기',
            onPressed: _loading || _saving || _pendingSave != null
                ? null
                : _reloadWithConfirmation,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading && envelope == null
            ? const Center(child: CircularProgressIndicator())
            : envelope == null
                ? EmptyState(
                    title: '터치키 초안을 불러오지 못했습니다.',
                    message: _error,
                    action: FilledButton(
                      onPressed: _load,
                      child: const Text('다시 시도'),
                    ),
                  )
                : _buildEditor(envelope),
      ),
    );
  }

  Widget _buildEditor(TouchkeyLayoutEnvelope envelope) {
    final definition = envelope.definition;
    final locked = !_canEdit;
    final saveBlockedReason = !_contextCanSaveDraft
        ? _capabilityMessage
        : !definition.complete ||
                !envelope.base.complete ||
                !envelope.saved.complete
            ? '원본 또는 서버 초안이 완전하지 않아 저장할 수 없습니다.'
            : '현재 서버 초안은 편집할 수 없습니다.';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '분류 ${definition.classCode} · 순번 ${definition.sortValue} · 페이지 ${definition.page}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${definition.columns} × ${definition.rows} 슬롯 · revision ${envelope.saved.revision}',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
              if (locked) ...[
                const SizedBox(height: 8),
                Text(
                  _revisionConflict
                      ? '저장 기준이 바뀌었습니다. 서버 초안을 다시 불러와 변경사항을 비교해 주세요.'
                      : saveBlockedReason,
                  style: const TextStyle(color: Color(0xFFB45309), height: 1.4),
                ),
              ],
              if (definition.issues.isNotEmpty ||
                  envelope.saved.issues.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final issue in [
                  ...definition.issues,
                  ...envelope.saved.issues
                ])
                  Text(
                    '${issue.code}: ${issue.message}',
                    style:
                        const TextStyle(color: Color(0xFFB91C1C), fontSize: 12),
                  ),
              ],
            ],
          ),
        ),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              _error,
              style: const TextStyle(color: Color(0xFFB91C1C)),
            ),
          ),
        if (_successMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              _successMessage,
              style: const TextStyle(color: Color(0xFF047857)),
            ),
          ),
        Expanded(
          child: !definition.hasSafeDimensions
              ? const EmptyState(title: '편집 가능한 슬롯 크기 정보가 없습니다.')
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: definition.columns * 104.0,
                    child: GridView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: definition.slotCount,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: definition.columns,
                        crossAxisSpacing: 6,
                        mainAxisSpacing: 6,
                        childAspectRatio: 1.15,
                      ),
                      itemBuilder: (context, index) {
                        final horizontal = index % definition.columns + 1;
                        final vertical = index ~/ definition.columns + 1;
                        final key = '$horizontal:$vertical';
                        final code = _placements[key];
                        final product =
                            code == null ? null : envelope.products[code];
                        return Material(
                          color: code == null
                              ? const Color(0xFFF8FAFC)
                              : const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            onTap: locked ? null : () => _selectSlot(key),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: const Color(0xFFCBD5E1)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$horizontal-$vertical',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF64748B),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    product?.name ?? (code ?? '빈 슬롯'),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  if (code != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      code,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF64748B),
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
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading || _saving || _pendingSave != null
                      ? null
                      : _reloadWithConfirmation,
                  icon: const Icon(Icons.refresh),
                  label: const Text('다시 불러오기'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving
                      ? null
                      : _pendingSave != null
                          ? _saveDraft
                          : (_canEdit && _dirty ? _saveDraft : null),
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(_pendingSave == null
                          ? Icons.save_outlined
                          : Icons.replay),
                  label: Text(
                    _saving
                        ? '저장 중...'
                        : _pendingSave == null
                            ? '서버 초안 저장'
                            : '같은 요청 재시도',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PendingTouchkeySave {
  final Map<String, dynamic> body;

  const _PendingTouchkeySave({required this.body});
}

class _TouchkeyProductChoice {
  final String? code;
  const _TouchkeyProductChoice(this.code);
}

class _TouchkeyProductPicker extends StatefulWidget {
  final List<TouchkeyLayoutProduct> products;
  final String? selectedCode;

  const _TouchkeyProductPicker({
    required this.products,
    required this.selectedCode,
  });

  @override
  State<_TouchkeyProductPicker> createState() => _TouchkeyProductPickerState();
}

class _TouchkeyProductPickerState extends State<_TouchkeyProductPicker> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final rows = widget.products.where((product) {
      if (query.isEmpty) return true;
      return product.name.toLowerCase().contains(query) ||
          product.code.toLowerCase().contains(query);
    }).toList(growable: false);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: '상품명 또는 코드 검색',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.clear),
              title: const Text('빈 슬롯으로 설정'),
              onTap: () =>
                  Navigator.pop(context, const _TouchkeyProductChoice(null)),
            ),
            const Divider(height: 1),
            Expanded(
              child: rows.isEmpty
                  ? const EmptyState(title: '선택할 수 있는 상품이 없습니다.')
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final product = rows[index];
                        return ListTile(
                          selected: product.code == widget.selectedCode,
                          title: Text(product.name.isEmpty
                              ? product.code
                              : product.name),
                          subtitle: Text([
                            product.code,
                            if (product.price.isNotEmpty) '${product.price}원',
                          ].join(' · ')),
                          onTap: () => Navigator.pop(
                            context,
                            _TouchkeyProductChoice(product.code),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
