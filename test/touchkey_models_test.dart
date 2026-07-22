import 'package:cafe_bridge_flutter/models/touchkey_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TouchkeyPayload parses backend touchkey response', () {
    final payload = TouchkeyPayload.fromJson({
      'program_key': 'touchkey',
      'program_code': 'MST030 + MST124',
      'label': '터치키상품등록',
      'program_path': 'mst::MST030.xfdl + mst::MST124.xfdl',
      'row_limit': 120,
      'fetched_at': '2026-04-26T00:00:00Z',
      'open_result': {
        'method': 'combined',
        'menu_name': '터치키상품등록',
      },
      'sources': [
        {
          'program_key': 'mst030',
          'program_code': 'MST030',
          'label': '터치키상품등록',
          'program_path': 'mst::MST030.xfdl',
          'load_status': 'loaded',
          'table_count': 2,
          'fetched_at': '2026-04-26T00:00:00Z',
        },
        {
          'program_key': 'mst124',
          'program_code': 'MST124',
          'label': '터치키상품등록(위치)',
          'program_path': 'mst::MST124.xfdl',
          'load_status': 'loaded',
          'table_count': 1,
          'fetched_at': '2026-04-26T00:00:01Z',
        },
      ],
      'grid_prep': {
        'actions': [
          {
            'type': 'fnSelectTouchKeyClassList',
            'source_program_key': 'mst030',
            'source_program_code': 'MST030',
            'source_label': '터치키상품등록',
          },
        ],
      },
      'runtime': {
        'nodes': [
          {'id': 'divMain'},
        ],
      },
      'tables': [
        {
          'grid_name': 'grdTouchKeyClass',
          'grid_path': 'main.div.grdTouchKeyClass',
          'source_program_key': 'mst030',
          'source_program_code': 'MST030',
          'source_label': '터치키상품등록',
          'binddataset': 'dsTouchKeyClass',
          'binddataset_resolved': 'dsTouchKeyClass',
          'rowcount': 1,
          'columns': ['분류코드', '분류명', '터치키H', '터치키V'],
          'rows': [
            {
              '분류코드': 'A01',
              '분류명': '커피',
              '터치키H': '4',
              '터치키V': '4',
            },
          ],
          'body_cell_count': 4,
          'format_length': 120,
        },
        {
          'grid_name': 'grdTouchKey',
          'grid_path': 'main.div.grdTouchKey',
          'source_program_key': 'mst030',
          'source_program_code': 'MST030',
          'source_label': '터치키상품등록',
          'binddataset': 'dsTouchKey',
          'binddataset_resolved': 'dsTouchKey',
          'rowcount': 2,
          'columns': ['상품명', '판매가', '터치키H', '터치키V', '터치키페이지'],
          'rows': [
            {
              '상품명': '아메리카노',
              '판매가': 3000,
              '터치키H': 1,
              '터치키V': 1,
              '터치키페이지': 1,
            },
            {
              '상품명': '카페라떼',
              '판매가': 4500,
              '터치키H': 2,
              '터치키V': 1,
              '터치키페이지': 1,
            },
          ],
          'body_cell_count': 10,
          'format_length': 240,
        },
      ],
    });

    expect(payload.programKey, 'touchkey');
    expect(payload.programCode, 'MST030 + MST124');
    expect(payload.loadSteps, hasLength(1));
    expect(payload.runtimeNodes, hasLength(1));
    expect(payload.sources, hasLength(2));
    expect(payload.loadSteps.first.sourceProgramCode, 'MST030');
    expect(payload.tables, hasLength(2));
    expect(payload.tables.first.sourceProgramCode, 'MST030');
    expect(payload.tables.first.displayKind, '분류 데이터셋');
    expect(payload.tables.last.displayKind, '상품 데이터셋');
    expect(payload.tables.last.objectRows.first['상품명'], '아메리카노');
    expect(payload.tables.last.rows.first[1], '3000');
    expect(payload.tables.last.filledCells, 10);
  });

  test('TouchkeyLoadStep describes skip states', () {
    final step = TouchkeyLoadStep.fromJson({
      'type': 'skip-touchkey-load',
      'reason': 'touchkey-already-loaded',
      'class_code': 'B01',
      'sort_value': '3',
      'source_label': '터치키상품등록(위치)',
    });

    expect(step.title, '터치키상품등록(위치) · 상품 로드 생략');
    expect(step.detail, '분류 B01 / 순번 3 결과가 이미 로드되어 있었습니다.');
  });

  test('TouchkeyTable classifies touchkey datasets by binddataset name', () {
    final payload = TouchkeyPayload.fromJson({
      'tables': [
        {
          'grid_name': 'grdTouchKeyClass',
          'binddataset': 'form.dsTouchKeyClass',
          'binddataset_resolved': 'dsTouchKeyClass',
          'columns': ['COL_A', 'COL_B'],
          'rows': [
            ['A01', '커피'],
          ],
        },
        {
          'grid_name': 'grdTouchKey',
          'binddataset': 'dsTouchKey',
          'binddataset_resolved': 'form.dsTouchKey',
          'columns': ['COL_1', 'COL_2', '터치키H', '터치키V'],
          'rows': [
            ['0001', '아메리카노', 1, 1],
          ],
        },
      ],
    });

    expect(payload.tables.first.displayKind, '분류 데이터셋');
    expect(payload.tables.last.displayKind, '상품 데이터셋');
    expect(payload.tables.last.rows.first[1], '아메리카노');
  });

  test('normalizeTouchkeyPriceText accepts decorated price labels', () {
    expect(normalizeTouchkeyPriceText('3,700원'), '3,700');
    expect(normalizeTouchkeyPriceText('￦3,700'), '3,700');
    expect(normalizeTouchkeyPriceText('판매가 3,700원(VAT포함)'), '3,700');
    expect(normalizeTouchkeyPriceText('3000:0'), '3,000');
    expect(normalizeTouchkeyPriceText('샷추가500'), '');
  });
}
