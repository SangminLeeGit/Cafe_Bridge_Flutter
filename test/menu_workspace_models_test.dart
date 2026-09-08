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
      'kind': 'price_update',
      'status': 'draft',
      'item_code': '000001',
      'item_name': '아메리카노',
      'current_price': 3000,
      'target_price': 3500,
    });

    final updated = entry.copyWith(status: 'ready', targetPrice: 3800);

    expect(updated.status, 'ready');
    expect(updated.targetPrice, 3800);
    expect(updated.itemCode, entry.itemCode);
    expect(updated.currentPrice, entry.currentPrice);
  });
}
