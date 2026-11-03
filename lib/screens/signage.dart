import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/async_request_guard.dart';
import '../models/editor_context.dart';
import '../navigation/app_navigation.dart';
import '../services/api.dart';
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

class _SignageDraftEnvelope {
  final String scopeId;
  final String? baseRemoteHash;
  final _SignageMenu baseMenu;
  final _SignageMenu menu;
  final String revision;
  final String updatedAt;

  const _SignageDraftEnvelope({
    required this.scopeId,
    required this.baseRemoteHash,
    required this.baseMenu,
    required this.menu,
    required this.revision,
    required this.updatedAt,
  });

  factory _SignageDraftEnvelope.fromJson(Map<String, dynamic> json) {
    final rawBaseMenu = json['base_menu'];
    final rawMenu = json['menu'];
    final revision = json['revision']?.toString().trim() ?? '';
    final scopeId = json['scope_id']?.toString().trim() ?? '';
    if (rawBaseMenu is! Map || rawMenu is! Map || revision.isEmpty) {
      throw const FormatException('사이니지 초안 응답의 버전 또는 메뉴 데이터가 없습니다.');
    }
    if (scopeId.isEmpty) {
      throw const FormatException('사이니지 초안 응답에 편집 범위가 없습니다.');
    }
    return _SignageDraftEnvelope(
      scopeId: scopeId,
      baseRemoteHash: json['base_remote_hash']?.toString(),
      baseMenu: _SignageMenu.fromJson(Map<String, dynamic>.from(rawBaseMenu)),
      menu: _SignageMenu.fromJson(Map<String, dynamic>.from(rawMenu)),
      revision: revision,
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }
}

class _PendingSignageSave {
  final String requestId;
  final String expectedRevision;
  final String? baseRemoteHash;
  final _SignageMenu snapshot;
  final int localEditRevision;
  final Map<String, dynamic> body;

  _PendingSignageSave({
    required this.requestId,
    required this.expectedRevision,
    required this.baseRemoteHash,
    required this.snapshot,
    required this.localEditRevision,
  }) : body = Map<String, dynamic>.unmodifiable({
          'request_id': requestId,
          'expected_revision': expectedRevision,
          'base_remote_hash': baseRemoteHash,
          'menu': snapshot.toJson(),
        });
}

enum _PublicationPhase { idle, publishing, published, ambiguous, failed }

class _SignagePublication {
  final _PublicationPhase phase;
  final String publicationId;
  final String status;
  final String draftRevision;
  final String startedAt;
  final String finishedAt;
  final String errorCode;
  final String errorMessage;
  final String localMessage;

  const _SignagePublication({
    required this.phase,
    required this.publicationId,
    required this.status,
    required this.draftRevision,
    this.startedAt = '',
    this.finishedAt = '',
    this.errorCode = '',
    this.errorMessage = '',
    this.localMessage = '',
  });

  factory _SignagePublication.fromJson(
    Map<String, dynamic> json, {
    required String fallbackId,
    required String fallbackRevision,
  }) {
    final status = (json['status'] ?? '').toString().trim().toLowerCase();
    final phase = switch (status) {
      'confirmed' => _PublicationPhase.published,
      'prepared' ||
      'dispatching' ||
      'unknown' ||
      'needs-review' =>
        _PublicationPhase.ambiguous,
      _ => _PublicationPhase.failed,
    };
    return _SignagePublication(
      phase: phase,
      publicationId: (json['publication_id'] ?? fallbackId).toString(),
      status: status.isEmpty ? 'unknown' : status,
      draftRevision: (json['draft_revision'] ?? fallbackRevision).toString(),
      startedAt: (json['started_at'] ?? '').toString(),
      finishedAt: (json['finished_at'] ?? '').toString(),
      errorCode: (json['error_code'] ?? '').toString(),
      errorMessage: (json['error_message'] ?? '').toString(),
    );
  }

  _SignagePublication withLocalMessage(String message) => _SignagePublication(
        phase: phase,
        publicationId: publicationId,
        status: status,
        draftRevision: draftRevision,
        startedAt: startedAt,
        finishedAt: finishedAt,
        errorCode: errorCode,
        errorMessage: errorMessage,
        localMessage: message,
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
  _SignageMenu? _baseRemote;
  _SignageMenu? _draft;
  _SignageDraftEnvelope? _conflictSnapshot;
  _PendingSignageSave? _pendingSave;
  _SignagePublication? _publication;
  EditorContext? _editorContext;
  String _scopeId = '';
  String _baseRemoteHash = '';
  String _serverRevision = '';
  String _serverUpdatedAt = '';
  bool _loading = true;
  String _error = '';
  bool _pushing = false;
  bool _dirty = false;
  String _successMessage = '';
  String _capabilityError = '';
  int _localEditRevision = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadEditorContext();
  }

  Future<_SignageDraftEnvelope> _fetchDraft() async {
    final result =
        await context.read<AppState>().fetchMapParsed<_SignageDraftEnvelope>(
              '/api/editor/signage/draft',
              parser: _SignageDraftEnvelope.fromJson,
              cacheTtl: Duration.zero,
              allowStaleOnError: false,
            );
    return result.data;
  }

  Future<EditorContext> _fetchEditorContext() async {
    final result = await context.read<AppState>().fetchMapParsed<EditorContext>(
          '/api/editor/context',
          parser: EditorContext.fromJson,
          cacheTtl: Duration.zero,
          allowStaleOnError: false,
        );
    return result.data;
  }

  Future<void> _loadEditorContext() async {
    try {
      final editor = await _fetchEditorContext();
      if (!mounted) return;
      setState(() {
        _editorContext = editor;
        _capabilityError = '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _editorContext = null;
        _capabilityError = error.toString();
      });
    }
  }

  bool get _canSaveDraft =>
      _editorContext?.capability('save_signage_draft')?.enabled ?? false;

  bool get _canPublish =>
      _editorContext?.capability('publish_signage')?.enabled ?? false;

  String get _saveDraftBlockReason {
    if (_capabilityError.isNotEmpty) {
      return '서버 초안 저장 권한을 확인하지 못했습니다. 저장은 차단되었습니다. $_capabilityError';
    }
    final decision = _editorContext?.capability('save_signage_draft');
    if (decision == null) return '서버 초안 저장 권한을 확인할 수 없습니다.';
    if (decision.enabled) return '';
    if (decision.message.isNotEmpty) return decision.message;
    return '서버에서 사이니지 초안 저장을 허용하지 않습니다. (${decision.reasonCode})';
  }

  String get _publishBlockReason {
    if (_capabilityError.isNotEmpty) {
      return '서버 게시 권한을 확인하지 못했습니다. 게시가 차단되었습니다. $_capabilityError';
    }
    final decision = _editorContext?.capability('publish_signage');
    if (decision == null) return '서버 게시 권한을 확인할 수 없습니다.';
    if (!_canPublish) {
      if (decision.message.isNotEmpty) return decision.message;
      return '서버에서 사이니지 게시를 허용하지 않습니다. (${decision.reasonCode})';
    }
    if (_draft == null) return '게시할 서버 초안을 먼저 불러와야 합니다.';
    if (_dirty) return '로컬 변경사항이 있습니다. 먼저 서버 초안에 저장해 주세요.';
    if (_pushing) return '저장 또는 게시 요청을 처리 중입니다.';
    if (_pendingSave != null) return '저장 결과를 확인한 뒤 게시할 수 있습니다.';
    if (_serverRevision.isEmpty) return '서버 초안 revision을 확인할 수 없습니다.';
    if (_baseRemoteHash.isEmpty) return '원격 게시본 기준 hash를 확인할 수 없습니다.';
    final publication = _publication;
    final publicationPhase = publication?.phase ?? _PublicationPhase.idle;
    if (publicationPhase == _PublicationPhase.publishing) {
      return '게시 요청을 처리 중입니다.';
    }
    if (publicationPhase == _PublicationPhase.ambiguous) {
      return '이전 게시 결과가 확인되지 않았습니다. 먼저 게시 상태를 조회하거나 조정해 주세요.';
    }
    if (publicationPhase == _PublicationPhase.failed) {
      return '이전 요청이 완료되지 않았습니다. 서버 초안을 새로고침한 뒤 다시 확인해 주세요.';
    }
    if (publicationPhase == _PublicationPhase.published &&
        publication?.draftRevision == _serverRevision) {
      return '현재 초안 revision은 이미 게시 확인되었습니다. 내용을 변경해 새 revision으로 저장한 뒤 게시해 주세요.';
    }
    return '';
  }

  bool get _canStartPublish => _publishBlockReason.isEmpty;

  Future<bool> _confirmDiscardChanges({
    required String title,
    required String message,
    required String actionLabel,
  }) async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('계속 편집'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    return discard == true;
  }

  Future<void> _load({bool discardDirty = false}) async {
    if (!mounted || _pushing) return;
    if (_pendingSave != null) {
      setState(() {
        _error = '저장 결과 확인 전에는 새로고침할 수 없습니다. 같은 요청으로 결과를 먼저 확인해 주세요.';
      });
      return;
    }
    if (_dirty && !discardDirty) {
      final discard = await _confirmDiscardChanges(
        title: '로컬 변경사항 새로고침',
        message: '새로고침하면 저장되지 않은 로컬 편집이 사라집니다. 계속하시겠습니까?',
        actionLabel: '새로고침',
      );
      if (!discard || !mounted) return;
    }
    final request = beginAsyncRequest();
    final revisionBeforeLoad = _localEditRevision;
    setState(() {
      _loading = true;
      _error = '';
      _successMessage = '';
    });
    try {
      final result = await _fetchDraft();
      if (!isCurrentAsyncRequest(request)) return;
      if (_draft != null && _localEditRevision != revisionBeforeLoad) {
        setState(() {
          _loading = false;
          _error = '새로고침 중 편집 내용이 바뀌어 로컬 초안을 유지했습니다.';
        });
        return;
      }
      setState(() {
        _scopeId = result.scopeId;
        _baseRemoteHash = result.baseRemoteHash ?? '';
        _baseRemote = result.baseMenu.clone();
        _saved = result.menu.clone();
        _draft = result.menu.clone();
        _serverRevision = result.revision;
        _serverUpdatedAt = result.updatedAt;
        _conflictSnapshot = null;
        _pendingSave = null;
        if (_publication?.phase == _PublicationPhase.failed) {
          _publication = null;
        }
        _localEditRevision += 1;
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
    setState(() {
      _localEditRevision += 1;
      _dirty = true;
      _successMessage = '';
    });
  }

  Future<void> _resetDraft() async {
    if (_saved == null || _pushing || _pendingSave != null) return;
    if (_dirty) {
      final discard = await _confirmDiscardChanges(
        title: '로컬 변경사항 되돌리기',
        message: '저장되지 않은 편집을 서버에 저장된 초안으로 되돌립니다. 계속하시겠습니까?',
        actionLabel: '되돌리기',
      );
      if (!discard || !mounted) return;
    }
    setState(() {
      _draft = _saved!.clone();
      _localEditRevision += 1;
      _dirty = false;
      _successMessage = '';
      _error = '';
    });
  }

  Future<void> _handleBlockedPop() async {
    if (_pendingSave != null || _pushing) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('저장 결과 확인 필요'),
          content: const Text(
            '저장 요청 결과가 확정되지 않았습니다. 같은 요청으로 저장 결과를 확인한 뒤 화면을 나가 주세요.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('계속 편집'),
            ),
          ],
        ),
      );
      return;
    }
    if (_dirty) {
      final discard = await _confirmDiscardChanges(
        title: '로컬 변경사항 폐기',
        message: '저장되지 않은 변경사항이 있습니다. 이 화면을 나가시겠습니까?',
        actionLabel: '나가기',
      );
      if (!discard || !mounted) return;
    }
    setState(() => _dirty = false);
    Navigator.of(context).pop();
  }

  _PendingSignageSave _newPendingSave(_SignageMenu draft) {
    return _PendingSignageSave(
      requestId: _newUuidV4(),
      expectedRevision: _serverRevision,
      baseRemoteHash: _baseRemoteHash.isEmpty ? null : _baseRemoteHash,
      snapshot: draft.clone(),
      localEditRevision: _localEditRevision,
    );
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

  Future<void> _publishDraft() async {
    final draft = _draft;
    if (draft == null || !_canStartPublish) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('외부 메뉴판에 게시'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '게시를 진행하면 외부 메뉴판이 이 서버 초안의 내용으로 변경됩니다. '
                '서버 초안 저장과 외부 메뉴판 게시는 별개의 작업입니다.',
              ),
              const SizedBox(height: 12),
              Text('게시할 서버 초안 revision: $_serverRevision'),
              const SizedBox(height: 6),
              Text('가게·메뉴: ${_menuOutline(draft)}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('게시 진행'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    if (!_canStartPublish) {
      setState(() => _error = _publishBlockReason);
      return;
    }

    setState(() {
      _pushing = true;
      _error = '';
      _successMessage = '';
    });
    var requestId = '';
    var requestAttempted = false;
    var expectedRevision = _serverRevision;
    try {
      // Re-check the server-owned publish capability immediately before send.
      final editorContext = await _fetchEditorContext();
      if (!mounted) return;
      setState(() {
        _editorContext = editorContext;
        _capabilityError = '';
      });
      if (editorContext.scopeId != _scopeId) {
        throw const ApiException(
          '로그인 또는 편집 범위가 바뀌었습니다. 현재 초안은 다른 범위로 게시하지 않았습니다.',
          statusCode: 409,
          code: 'editor_scope_changed',
        );
      }
      final capability = editorContext.capability('publish_signage');
      if (capability?.enabled != true) {
        throw ApiException(
          capability?.message.isNotEmpty == true
              ? capability!.message
              : '서버에서 사이니지 게시를 허용하지 않습니다.',
          statusCode: 503,
          code: capability?.reasonCode ?? 'capability_disabled',
        );
      }
      if (_dirty || _pendingSave != null || _draft == null) {
        throw const ApiException(
          '로컬 변경사항 또는 저장 중인 요청이 있습니다. 서버 초안을 저장하고 결과를 확인한 뒤 게시해 주세요.',
          statusCode: 409,
          code: 'publication_precondition_required',
        );
      }
      expectedRevision = _serverRevision;
      final expectedRemoteHash = _baseRemoteHash;
      if (expectedRevision.isEmpty || expectedRemoteHash.isEmpty) {
        throw const ApiException(
          '서버 초안 revision 또는 원격 게시본 기준 hash가 없어 게시할 수 없습니다.',
          statusCode: 422,
          code: 'publication_precondition_required',
        );
      }
      requestId = _newUuidV4();
      setState(() {
        _publication = _SignagePublication(
          phase: _PublicationPhase.publishing,
          publicationId: requestId,
          status: 'dispatching',
          draftRevision: expectedRevision,
        );
      });
      requestAttempted = true;
      final response = await context.read<AppState>().postJson(
        '/api/editor/signage/publish',
        body: {
          'request_id': requestId,
          'expected_draft_revision': expectedRevision,
          'expected_remote_hash': expectedRemoteHash,
        },
      );
      final publication = _SignagePublication.fromJson(
        response,
        fallbackId: requestId,
        fallbackRevision: expectedRevision,
      );
      if (!mounted) return;
      setState(() => _publication = publication);
      if (publication.phase == _PublicationPhase.published) {
        await _refreshDraftAfterPublication(publication);
      }
    } catch (error) {
      if (!mounted) return;
      if (requestAttempted && requestId.isNotEmpty) {
        final apiError = error is ApiException ? error : null;
        // publication_in_progress means a different publication is active and
        // this request was never accepted. It is not an ambiguous outcome of
        // this request, so keep no publication id and require a fresh attempt
        // after the active publication finishes.
        final inProgress = apiError?.code == 'publication_in_progress';
        final ambiguous = !inProgress &&
            (apiError == null ||
                apiError.isTransportError ||
                (apiError.statusCode != null && apiError.statusCode! >= 500) ||
                const {
                  'publication_unknown',
                  'publication_missing',
                }.contains(apiError.code));
        final message = _formatError(error);
        setState(() {
          _publication = _SignagePublication(
            phase: inProgress
                ? _PublicationPhase.failed
                : ambiguous
                    ? _PublicationPhase.ambiguous
                    : _PublicationPhase.failed,
            publicationId: inProgress ? '' : requestId,
            status: inProgress
                ? 'publication_in_progress'
                : ambiguous
                    ? 'unknown'
                    : 'request_failed',
            draftRevision: expectedRevision,
            errorCode: apiError?.code ?? '',
            errorMessage: message,
            localMessage: inProgress
                ? '다른 게시 요청이 진행 중이라 이 요청은 접수되지 않았습니다. 완료된 뒤 서버 초안을 새로고침하고 다시 시도해 주세요.'
                : ambiguous
                    ? '게시 요청 응답을 확정하지 못했습니다. 같은 요청 ID를 보존했습니다.'
                    : '',
          );
          _error = '';
        });
      } else {
        setState(() => _error = _formatError(error));
      }
    } finally {
      if (mounted) setState(() => _pushing = false);
    }
  }

  Future<void> _lookupPublication() async {
    final publication = _publication;
    if (publication == null ||
        publication.phase != _PublicationPhase.ambiguous ||
        publication.publicationId.isEmpty ||
        _pushing) {
      return;
    }
    setState(() {
      _pushing = true;
      _error = '';
    });
    try {
      final response =
          await context.read<AppState>().fetchMapParsed<Map<String, dynamic>>(
                '/api/editor/signage/publications/${Uri.encodeComponent(publication.publicationId)}',
                parser: (json) => json,
                cacheTtl: Duration.zero,
                allowStaleOnError: false,
              );
      final updated = _SignagePublication.fromJson(
        response.data,
        fallbackId: publication.publicationId,
        fallbackRevision: publication.draftRevision,
      );
      if (!mounted) return;
      setState(() => _publication = updated);
      if (updated.phase == _PublicationPhase.published) {
        await _refreshDraftAfterPublication(updated);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _publication = publication.withLocalMessage(
              '게시 상태 조회에 실패했습니다. 같은 게시 ID를 보존했습니다. ${_formatError(error)}',
            ));
      }
    } finally {
      if (mounted) setState(() => _pushing = false);
    }
  }

  Future<void> _reconcilePublication() async {
    final publication = _publication;
    if (publication == null ||
        publication.phase != _PublicationPhase.ambiguous ||
        publication.publicationId.isEmpty ||
        _pushing) {
      return;
    }
    setState(() {
      _pushing = true;
      _error = '';
    });
    try {
      final response = await context.read<AppState>().postJson(
        '/api/editor/signage/publications/${Uri.encodeComponent(publication.publicationId)}/reconcile',
        body: {'request_id': publication.publicationId},
      );
      final updated = _SignagePublication.fromJson(
        response,
        fallbackId: publication.publicationId,
        fallbackRevision: publication.draftRevision,
      );
      if (!mounted) return;
      setState(() => _publication = updated);
      if (updated.phase == _PublicationPhase.published) {
        await _refreshDraftAfterPublication(updated);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _publication = publication.withLocalMessage(
              '게시 상태 조정에 실패했습니다. 외부 게시 결과는 아직 확인되지 않았습니다. ${_formatError(error)}',
            ));
      }
    } finally {
      if (mounted) setState(() => _pushing = false);
    }
  }

  Future<void> _refreshDraftAfterPublication(
    _SignagePublication publication,
  ) async {
    try {
      final latest = await _fetchDraft();
      if (!mounted) return;
      if (_scopeId.isNotEmpty && latest.scopeId != _scopeId) {
        throw const FormatException('게시 후 초안의 편집 범위가 현재 화면과 다릅니다.');
      }
      setState(() {
        _scopeId = latest.scopeId;
        _baseRemoteHash = latest.baseRemoteHash ?? '';
        _baseRemote = latest.baseMenu.clone();
        _saved = latest.menu.clone();
        _draft = latest.menu.clone();
        _serverRevision = latest.revision;
        _serverUpdatedAt = latest.updatedAt;
        _conflictSnapshot = null;
        _pendingSave = null;
        _dirty = false;
        _successMessage =
            '외부 메뉴판 게시가 확인되었습니다. 서버 초안 revision ${publication.draftRevision}을 게시했습니다. 게시와 초안 저장은 별개입니다.';
        _error = '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _successMessage =
            '외부 메뉴판 게시가 확인되었습니다. 서버 초안 기준을 새로 불러오지 못했습니다. 게시 결과는 아래 상태를 확인해 주세요.';
        _error = '게시 후 초안 새로고침 실패: ${_formatError(error)}';
      });
    }
  }

  Future<_SignageDraftEnvelope?> _lookupWriteReceipt(
    _PendingSignageSave pending,
  ) async {
    try {
      final response =
          await context.read<AppState>().fetchMapParsed<_SignageDraftEnvelope>(
                '/api/editor/write-receipts/${pending.requestId}',
                params: const {'operation': 'signage.draft'},
                parser: _SignageDraftEnvelope.fromJson,
                cacheTtl: Duration.zero,
                allowStaleOnError: false,
              );
      return response.data;
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  void _acceptSavedEnvelope(
    _SignageDraftEnvelope envelope,
    _PendingSignageSave pending,
  ) {
    if (_scopeId.isNotEmpty && envelope.scopeId != _scopeId) {
      throw const FormatException('저장 응답의 편집 범위가 현재 초안과 다릅니다.');
    }
    setState(() {
      _scopeId = envelope.scopeId;
      _baseRemoteHash = envelope.baseRemoteHash ?? '';
      _baseRemote = envelope.baseMenu.clone();
      _saved = envelope.menu.clone();
      _serverRevision = envelope.revision;
      _serverUpdatedAt = envelope.updatedAt;
      _pendingSave = null;
      _conflictSnapshot = null;
      if (_localEditRevision == pending.localEditRevision) {
        _draft = envelope.menu.clone();
        _dirty = false;
      } else {
        _dirty = true;
      }
      _successMessage = _localEditRevision == pending.localEditRevision
          ? '서버 초안 ${envelope.revision}번으로 저장했습니다. 외부 메뉴판에는 게시되지 않았습니다.'
          : '제출한 내용은 서버 초안으로 저장했습니다. 저장 중 편집한 변경사항은 아직 저장되지 않았습니다.';
      _error = '';
    });
  }

  bool _isSignageConflict(ApiException error) => const {
        'draft_changed',
        'remote_changed',
        'signage_draft_conflict',
        'request_id_reused',
      }.contains(error.code);

  Future<void> _saveDraft() async {
    final draft = _draft;
    if (draft == null || !_dirty || _pushing) return;

    setState(() {
      _pushing = true;
      _error = '';
      _successMessage = '';
    });

    var writeAttempted = false;
    final previousPending = _pendingSave;
    final appState = context.read<AppState>();
    try {
      // Check the server-owned capability before creating or sending a write.
      final editorContext = await _fetchEditorContext();
      if (!mounted) return;
      setState(() {
        _editorContext = editorContext;
        _capabilityError = '';
      });
      if (_scopeId.isNotEmpty && editorContext.scopeId != _scopeId) {
        throw const ApiException(
          '로그인 또는 편집 범위가 바뀌었습니다. 현재 로컬 초안은 다른 범위로 전송하지 않았습니다.',
          statusCode: 409,
          code: 'editor_scope_changed',
        );
      }
      final capability = editorContext.capability('save_signage_draft');
      if (capability?.enabled != true) {
        throw ApiException(
          _saveDraftBlockReason,
          statusCode: 503,
          code: capability?.reasonCode ?? 'capability_disabled',
        );
      }

      final pending = previousPending ?? _newPendingSave(draft);
      if (previousPending != null) {
        final receipt = await _lookupWriteReceipt(previousPending);
        if (receipt != null) {
          if (!mounted) return;
          _acceptSavedEnvelope(receipt, previousPending);
          return;
        }
      }
      if (_pendingSave == null) setState(() => _pendingSave = pending);
      writeAttempted = true;
      final result = await appState.postJson(
        '/api/editor/signage/draft',
        method: 'PUT',
        body: pending.body,
      );
      final envelope = _SignageDraftEnvelope.fromJson(result);
      if (!mounted) return;
      _acceptSavedEnvelope(envelope, pending);
    } catch (error) {
      if (!mounted) return;
      final pending = _pendingSave ?? previousPending;
      if (writeAttempted && pending != null) {
        try {
          final receipt = await _lookupWriteReceipt(pending);
          if (receipt != null) {
            if (mounted) _acceptSavedEnvelope(receipt, pending);
            return;
          }
        } catch (_) {
          // Keep the immutable request for a same-ID retry; the receipt lookup
          // itself may also be unavailable.
        }
      }
      if (!mounted) return;
      if (error is ApiException && _isSignageConflict(error)) {
        setState(() {
          _pendingSave = null;
          _error =
              '서버 초안 버전이 바뀌었습니다. 로컬 편집은 보존했습니다. 최신 초안을 비교해 주세요. ${error.message}';
        });
        try {
          final latest = await _fetchDraft();
          if (mounted && latest.scopeId == _scopeId) {
            setState(() => _conflictSnapshot = latest);
          }
        } catch (_) {
          // The local draft remains available even if comparison fetch fails.
        }
      } else if (writeAttempted) {
        setState(() {
          _error =
              '저장 결과가 확정되지 않았습니다. 로컬 입력을 보존하고 동일 요청으로 결과 확인/재시도를 대기합니다. ${_formatError(error)}';
        });
      } else {
        setState(() {
          if (previousPending == null) _pendingSave = null;
          _error = _formatError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _pushing = false);
    }
  }

  String _formatError(Object error) {
    if (error is ApiException && error.code == 'upgrade_required') {
      return '서버가 새 편집 계약을 요구합니다. 구형 게시 경로로 우회하지 않습니다. ${error.message}';
    }
    if (error is ApiException && error.code == 'capability_disabled') {
      return '서버에서 초안 저장을 허용하지 않습니다. ${error.message}';
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  void _useConflictRevision() {
    final latest = _conflictSnapshot;
    if (latest == null) return;
    setState(() {
      // Adopt only the server revision/base preconditions. Keep the user's
      // edited menu intact; the explicit next save is a reviewed overwrite.
      _scopeId = latest.scopeId;
      _baseRemoteHash = latest.baseRemoteHash ?? '';
      _baseRemote = latest.baseMenu.clone();
      _saved = latest.menu.clone();
      _serverRevision = latest.revision;
      _serverUpdatedAt = latest.updatedAt;
      _conflictSnapshot = null;
      _localEditRevision += 1;
      _dirty = true;
      _error = '';
      _successMessage =
          '서버 rev ${latest.revision}과 비교했습니다. 로컬 초안은 유지했으며, 저장을 누르면 새 서버 버전을 기준으로 제출합니다.';
    });
  }

  String _menuOutline(_SignageMenu? menu) {
    if (menu == null) return '확인할 메뉴 데이터가 없습니다.';
    final categories = menu.categories.map((category) {
      final items = category.items
          .map((item) => '${item.korean} ${_priceFormatted(item.price)}원')
          .join(', ');
      return '${category.title}: ${items.isEmpty ? '항목 없음' : items}';
    }).join(' · ');
    return categories.isEmpty
        ? menu.shopName
        : '${menu.shopName} · $categories';
  }

  String _publicationStatusLabel(_SignagePublication publication) {
    return switch (publication.status) {
      'confirmed' => '게시 완료 확인 (confirmed)',
      'prepared' => '게시 결과 확인 필요 (prepared)',
      'dispatching' => '게시 결과 확인 필요 (dispatching)',
      'unknown' => '외부 게시 결과 미확인 (unknown)',
      'needs-review' => '게시 결과 검토 필요 (needs-review)',
      'rejected' => '게시 거부 (rejected)',
      'failed' => '게시 실패 (failed)',
      'publication_in_progress' => '다른 게시 요청 진행 중',
      'request_failed' => '게시 요청 실패',
      _ => publication.status.isEmpty ? '상태 확인 필요' : publication.status,
    };
  }

  String _publicationNextStep(_SignagePublication publication) {
    return switch (publication.phase) {
      _PublicationPhase.publishing => '게시 요청을 처리하고 있습니다.',
      _PublicationPhase.published =>
        '서버 상태가 confirmed로 확인되었습니다. 이것만 게시 완료로 간주합니다.',
      _PublicationPhase.ambiguous
          when publication.status == 'publication_in_progress' =>
        '다른 게시 요청이 진행 중입니다. 이 요청 ID를 보존했으며, 새 요청을 만들지 말고 상태 조회 또는 조정을 진행해 주세요.',
      _PublicationPhase.ambiguous =>
        '외부 게시 결과는 아직 알 수 없습니다. 성공으로 간주하지 마세요. 새 게시 요청을 만들지 말고 같은 ID로 상태 조회 또는 조정을 진행해 주세요.',
      _PublicationPhase.failed =>
        '게시 완료로 확인되지 않았습니다. 원인을 확인하고 서버 초안을 새로고침한 뒤 다시 진행해 주세요.',
      _ => '게시 요청을 시작하지 않았습니다.',
    };
  }

  Widget _publicationStatusCard(_SignagePublication publication) {
    return _SectionCard(
      title: '게시 상태',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('상태: ${_publicationStatusLabel(publication)}'),
          if (publication.publicationId.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('publication_id: ${publication.publicationId}'),
          ],
          const SizedBox(height: 4),
          Text('게시 초안 revision: ${publication.draftRevision}'),
          if (publication.startedAt.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('시작 시각: ${publication.startedAt}'),
          ],
          if (publication.finishedAt.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('종료 시각: ${publication.finishedAt}'),
          ],
          if (publication.errorCode.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('오류 코드: ${publication.errorCode}'),
          ],
          if (publication.errorMessage.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('오류 내용: ${publication.errorMessage}'),
          ],
          if (publication.localMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              publication.localMessage,
              style: const TextStyle(color: Color(0xFFB45309)),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            _publicationNextStep(publication),
            style: const TextStyle(fontSize: 13),
          ),
          if (publication.phase == _PublicationPhase.ambiguous) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _pushing ? null : _lookupPublication,
                  icon: const Icon(Icons.search),
                  label: const Text('게시 상태 조회'),
                ),
                OutlinedButton.icon(
                  onPressed: _pushing ? null : _reconcilePublication,
                  icon: const Icon(Icons.sync),
                  label: const Text('게시 상태 조정'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _draft == null) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF0D9488)));
    }

    if (_error.isNotEmpty && _draft == null) {
      return EmptyState(
        title: '메뉴판 데이터를 불러오지 못했습니다.',
        message: _error,
        action:
            FilledButton(onPressed: () => _load(), child: const Text('다시 시도')),
      );
    }

    final draft = _draft;
    if (draft == null) {
      return EmptyState(
        title: '데이터 없음',
        action:
            FilledButton(onPressed: () => _load(), child: const Text('새로고침')),
      );
    }
    final shortBaseHash = _baseRemoteHash.isEmpty
        ? '-'
        : _baseRemoteHash.length > 12
            ? _baseRemoteHash.substring(0, 12)
            : _baseRemoteHash;

    return PopScope(
      canPop: !_dirty && !_pushing && _pendingSave == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBlockedPop();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                // 오류/성공 배너
                if (_error.isNotEmpty) _Banner(text: _error, isError: true),
                if (_successMessage.isNotEmpty)
                  _Banner(text: _successMessage, isError: false),

                _SectionCard(
                  title: '게시본과 서버 초안',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '서버 초안 revision: ${_serverRevision.isEmpty ? '-' : _serverRevision}'),
                      const SizedBox(height: 4),
                      Text('원격 게시본 기준 hash: $shortBaseHash'),
                      if (_serverUpdatedAt.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('서버 초안 저장 시각: $_serverUpdatedAt'),
                      ],
                      const SizedBox(height: 8),
                      Text('게시본: ${_menuOutline(_baseRemote)}'),
                      const SizedBox(height: 4),
                      Text('저장된 서버 초안: ${_menuOutline(_saved)}'),
                      const SizedBox(height: 8),
                      const _Banner(
                        text: '아래 저장 동작은 서버 초안만 저장합니다. 외부 메뉴판/POS에는 게시하지 않습니다.',
                        isError: false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_conflictSnapshot != null)
                  _SectionCard(
                    title: '서버 초안 충돌 비교',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('최신 서버 revision: ${_conflictSnapshot!.revision}'),
                        const SizedBox(height: 6),
                        Text('서버 초안: ${_menuOutline(_conflictSnapshot!.menu)}'),
                        const SizedBox(height: 4),
                        Text('내 로컬 초안: ${_menuOutline(_draft)}'),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _pushing ? null : _useConflictRevision,
                          icon: const Icon(Icons.compare_arrows),
                          label: const Text('비교한 서버 버전 기준으로 계속 편집'),
                        ),
                      ],
                    ),
                  ),
                if (_conflictSnapshot != null) const SizedBox(height: 12),
                if (!_canSaveDraft) ...[
                  _Banner(text: _saveDraftBlockReason, isError: true),
                  const SizedBox(height: 12),
                ],

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
                const SizedBox(height: 12),
                _SectionCard(
                  title: '외부 메뉴판 게시',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '게시하면 외부 메뉴판이 저장된 서버 초안으로 변경됩니다. '
                        '서버 초안 저장만으로는 외부 메뉴판이 바뀌지 않습니다.',
                        style: TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _canStartPublish ? _publishDraft : null,
                        icon: const Icon(Icons.publish_outlined),
                        label: Text(
                          _pushing ? '게시 처리 중...' : '외부 메뉴판 게시',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0D9488),
                          minimumSize: const Size(double.infinity, 44),
                        ),
                      ),
                      if (!_canStartPublish) ...[
                        const SizedBox(height: 8),
                        Text(
                          _publishBlockReason,
                          style: const TextStyle(
                            color: Color(0xFFB91C1C),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_publication != null) ...[
                  const SizedBox(height: 12),
                  _publicationStatusCard(_publication!),
                ],
              ],
            ),
          ),

          // 하단 스티키 액션 바
          _ActionBar(
            dirty: _dirty,
            pushing: _pushing,
            onRefresh: _loading || _pushing || _pendingSave != null
                ? null
                : () => _load(),
            onReset: _dirty && !_pushing && _pendingSave == null
                ? () => _resetDraft()
                : null,
            onSaveDraft:
                _dirty && !_pushing && _canSaveDraft ? _saveDraft : null,
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
  final VoidCallback? onSaveDraft;

  const _ActionBar({
    required this.dirty,
    required this.pushing,
    required this.onRefresh,
    required this.onReset,
    required this.onSaveDraft,
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
                  dirty ? '저장되지 않은 변경사항' : '서버 초안 저장됨 (외부 게시 전)',
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
                  onPressed: onSaveDraft,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9488),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    pushing ? '서버 저장 중...' : '서버 초안 저장',
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
