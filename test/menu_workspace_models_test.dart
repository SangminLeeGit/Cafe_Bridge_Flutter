import 'package:cafe_bridge_flutter/models/menu_workspace_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WorkspaceTaskHistoryEntry parses applied new-item task result', () {
    final entry = WorkspaceTaskHistoryEntry.fromJson({
      'task_id': 'task-1',
      'status': 'succeeded',
      'reason': 'mobile-new-item-apply',
      'actor': 'operator1',
      'started_at': '2026-04-25 10:00:00',
      'finished_at': '2026-04-25 10:00:08',
      'error_message': '',
      'execute': true,
      'item_name': '아이스 라떼',
      'item_code': '000123',
      'target_price': 4500,
      'result': {
        'status': 'applied',
        'message': '신규 메뉴 저장 완료',
      },
    });

    expect(entry.taskId, 'task-1');
    expect(entry.status, 'succeeded');
    expect(entry.execute, isTrue);
    expect(entry.itemName, '아이스 라떼');
    expect(entry.itemCode, '000123');
    expect(entry.targetPrice, 4500);
    expect(entry.resultStatus, 'applied');
    expect(entry.resultMessage, '신규 메뉴 저장 완료');
    expect(entry.displayTitle, '아이스 라떼');
  });

  test('WorkspaceTaskHistoryEntry falls back when result payload is absent',
      () {
    final entry = WorkspaceTaskHistoryEntry.fromJson({
      'task_id': 'task-2',
      'status': 'failed',
      'reason': 'preview',
      'actor': 'operator1',
      'item_name': '콜드브루',
      'item_code': '',
      'error_message': '분류를 찾지 못했습니다.',
    });

    expect(entry.resultStatus, isEmpty);
    expect(entry.resultMessage, isEmpty);
    expect(entry.errorMessage, '분류를 찾지 못했습니다.');
    expect(entry.displayTitle, '콜드브루');
    expect(entry.displaySubtitle, 'preview');
  });

  test('menu entry copy keeps details while applying an optimistic edit', () {
    final entry = MenuEntry.fromJson({
      'id': 1,
      'revision': 7,
      'kind': 'price_update',
      'status': 'draft',
      'item_code': '000001',
      'item_name': '아메리카노',
      'current_price': 3000,
      'target_price': 3500,
      'pending_submission_key': '',
    });

    final updated =
        entry.copyWith(status: 'ready', targetPrice: 3800, revision: 8);

    expect(updated.status, 'ready');
    expect(updated.targetPrice, 3800);
    expect(updated.itemCode, entry.itemCode);
    expect(updated.currentPrice, entry.currentPrice);
    expect(entry.revision, 7);
    expect(updated.revision, 8);
    expect(entry.isSubmissionReserved, isFalse);
  });

  test('workspace category options retain the current scoped catalog snapshot',
      () {
    final options = WorkspaceFormOptions.fromJson({
      'defaults': {
        'unit_name': 'EA',
        'tax_mode': '과세',
        'use_mode': '사용',
        'stock_mode': 'N',
      },
      'options': {
        'unit_name': ['EA', '잔'],
        'tax_mode': ['과세', '면세'],
        'use_mode': ['사용', '미사용'],
        'stock_mode': ['N', 'Y'],
      },
      'profile': {
        'default_major_category': '음료',
        'default_middle_category': '커피',
        'default_minor_category': '기본',
      },
      'category_options': {
        'available': true,
        'complete': true,
        'snapshot_id': 'catalog-42',
        'tenant_id': 'tenant-a',
        'shop_no': 'shop-1',
        'environment': 'prod',
        'credential_ref': 'easypos-main',
        'upstream_origin': 'https://easypos.example',
        'major_options': ['음료'],
        'middle_options_by_major': {
          '음료': ['커피'],
        },
        'minor_options_by_major_middle': {
          '음료__커피': ['기본'],
        },
      },
    });

    final catalog = options.categoryOptions;
    expect(catalog.containsPath('음료', '커피', '기본'), isTrue);
    expect(catalog.containsPath('음료', '커피', '디저트'), isFalse);
    expect(catalog.snapshotId, 'catalog-42');
    expect(catalog.hasExecutionScope, isTrue);
    expect(options.profileDefault('major_category'), '음료');
    expect(options.profileDefault('unit_name'), 'EA');
    expect(options.optionValues('tax_mode'), ['과세', '면세']);
  });

  test('incomplete category catalogs cannot validate a draft category path',
      () {
    final catalog = WorkspaceCategoryOptions.fromJson({
      'available': true,
      'complete': false,
      'snapshot_id': 'incomplete-snapshot',
      'major_options': ['음료'],
      'middle_options_by_major': {'음료': ['커피']},
      'minor_options_by_major_middle': {'음료__커피': ['기본']},
    });

    expect(catalog.containsPath('음료', '커피', '기본'), isFalse);
    expect(catalog.hasExecutionScope, isFalse);
  });

  test('draft payload targets workspace draft API without legacy mutation flags',
      () {
    final payload = buildNewItemDraftRequestBody(
      itemName: ' 딸기라떼 ',
      targetPrice: 5500,
      majorCategory: ' 음료 ',
      middleCategory: '커피',
      minorCategory: '기본',
      unitName: 'EA',
      taxMode: '과세',
      useMode: '사용',
      stockMode: 'N',
      barcode: '880-123',
      description: '',
      notes: '테스트',
      costPrice: 1800,
    );

    expect(payload['item_name'], '딸기라떼');
    expect(payload['target_price'], 5500);
    expect(payload['major_category'], '음료');
    expect(payload['cost_price'], 1800);
    expect(payload.containsKey('supply_price'), isFalse);
    expect(payload.containsKey('item_code'), isFalse);
    expect(payload.containsKey('execute'), isFalse);
    expect(payload.containsKey('reason'), isFalse);
  });

  test('workspace edits always carry a positive optimistic revision', () {
    final body = buildRevisionGuardedMenuEntryUpdateBody(
      fields: {'item_name': '딸기라떼'},
      expectedRevision: 12,
    );

    expect(body, {'item_name': '딸기라떼', 'expected_revision': 12});
    expect(
      () => buildRevisionGuardedMenuEntryUpdateBody(
        fields: const {'status': 'reviewed'},
        expectedRevision: 0,
      ),
      throwsArgumentError,
    );
  });

  test('menu entry carries reservation and catalog fields from the workspace',
      () {
    final entry = MenuEntry.fromJson({
      'id': 15,
      'revision': 3,
      'kind': 'new_item',
      'status': 'draft',
      'item_name': '딸기라떼',
      'placement_json': '{"page":1,"h":2,"v":1}',
      'category_node_id': 'minor-5',
      'catalog_snapshot_id': 'catalog-42',
      'pending_submission_key': 'submit-1',
    });

    expect(entry.revision, 3);
    expect(entry.placementJson, '{"page":1,"h":2,"v":1}');
    expect(entry.categoryNodeId, 'minor-5');
    expect(entry.catalogSnapshotId, 'catalog-42');
    expect(entry.isSubmissionReserved, isTrue);
  });
}
