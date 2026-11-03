import 'package:cafe_bridge_flutter/models/touchkey_layout.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _envelope({
  List<Map<String, dynamic>>? slots,
  String revision = '4',
}) {
  final placements = <String, String?>{
    for (var v = 1; v <= 2; v++)
      for (var h = 1; h <= 2; h++) '$h:$v': null,
  };
  placements.addAll({
    for (final slot in slots ?? const <Map<String, dynamic>>[])
      '${slot['h']}:${slot['v']}': slot['product_code']?.toString(),
  });
  return {
    'scope_id': 'scope-a',
    'definition': {
      'layout_id': 'touchkey-layout-a',
      'class_code': '01',
      'sort_value': '1',
      'page': 2,
      'columns': 2,
      'rows': 2,
      'complete': true,
      'issues': [],
    },
    'base': {
      'snapshot_id': 'base-snapshot-1',
      'revision': '0',
      'complete': true,
      'placements': placements,
      'issues': [],
    },
    'saved': {
      'snapshot_id': 'saved-snapshot-4',
      'revision': revision,
      'complete': true,
      'placements': placements,
      'issues': [],
    },
    'products': {
      '100': {
        'product_code': '100',
        'name': '아메리카노',
        'price': 4500,
        'placeable': true,
      },
    },
    'capabilities': {
      'edit': {'enabled': true, 'reasons': []},
      'apply': {
        'enabled': false,
        'reasons': ['capability_disabled']
      },
    },
  };
}

void main() {
  test('parses scoped source, saved slots, products, and disabled apply', () {
    final raw = _envelope(
      slots: [
        {'h': 1, 'v': 1, 'product_code': '100'},
      ],
    );
    final envelope = TouchkeyLayoutEnvelope.fromJson(raw);

    expect(envelope.scopeId, 'scope-a');
    expect(envelope.definition.page, 2);
    expect(envelope.saved.placements['1:1'], '100');
    expect(envelope.products['100']?.name, '아메리카노');
    expect(envelope.canEdit, isTrue);
    expect(envelope.canApply, isFalse);
  });

  test('builds every slot in stable row-major order with nullable blanks', () {
    final envelope = TouchkeyLayoutEnvelope.fromJson(_envelope());
    final body = buildTouchkeyLayoutSavePayload(
      envelope: envelope,
      placements: {
        '1:1': '100',
        '2:1': null,
        '1:2': '200',
        '2:2': null,
      },
      requestId: '12345678-1234-4234-8234-123456789abc',
    );

    expect(body['expected_revision'], '4');
    expect(body['base_snapshot_id'], 'base-snapshot-1');
    expect(body['class_code'], '01');
    expect(body['sort_value'], '1');
    expect(body['page'], 2);
    expect(body['slots'], [
      {'h': 1, 'v': 1, 'product_code': '100'},
      {'h': 2, 'v': 1, 'product_code': null},
      {'h': 1, 'v': 2, 'product_code': '200'},
      {'h': 2, 'v': 2, 'product_code': null},
    ]);
  });

  test('rejects incomplete layouts, missing slots, and duplicate products', () {
    final incomplete = _envelope();
    (incomplete['definition'] as Map<String, dynamic>)['complete'] = false;
    final envelope = TouchkeyLayoutEnvelope.fromJson(incomplete);
    expect(
      () => buildTouchkeyLayoutSavePayload(
        envelope: envelope,
        placements: const {},
        requestId: '12345678-1234-4234-8234-123456789abc',
      ),
      throwsStateError,
    );

    final ready = TouchkeyLayoutEnvelope.fromJson(_envelope());
    expect(
      () => buildTouchkeyLayoutSavePayload(
        envelope: ready,
        placements: const {
          '1:1': '100',
          '2:1': '100',
          '1:2': null,
          '2:2': null,
        },
        requestId: '12345678-1234-4234-8234-123456789abc',
      ),
      throwsStateError,
    );
  });
}
