import 'api_contracts.dart';

String normalizeTouchkeyPriceText(Object? value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty || raw == '-') {
    return '';
  }

  final normalized = raw
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[\[\](){}]'), '')
      .replaceAll(
        RegExp(
          r'(판매가|가격|금액|정가|vat|부가세|포함|별도|면세|과세|krw)',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'[￦₩원]'), '');

  if (!RegExp(r'^-?\d[\d,]*(?::\d+)?$').hasMatch(normalized)) {
    return '';
  }

  final numeric = normalized.split(':').first.replaceAll(',', '');
  final parsed = int.tryParse(numeric);
  if (parsed == null) {
    return '';
  }

  return parsed.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (match) => ',',
      );
}

class TouchkeyPayload {
  final String label;
  final String description;
  final String programKey;
  final String programCode;
  final String programPath;
  final int rowLimit;
  final String fetchedAt;
  final String loadStatus;
  final Map<String, dynamic> openResult;
  final Map<String, int> datasetCounts;
  final Map<String, dynamic> selectedClass;
  final List<TouchkeyLoadStep> loadSteps;
  final List<Map<String, dynamic>> runtimeNodes;
  final List<TouchkeySourceSummary> sources;
  final List<TouchkeySourceError> sourceErrors;
  final List<TouchkeyTable> tables;

  const TouchkeyPayload({
    required this.label,
    required this.description,
    required this.programKey,
    required this.programCode,
    required this.programPath,
    required this.rowLimit,
    required this.fetchedAt,
    required this.loadStatus,
    required this.openResult,
    required this.datasetCounts,
    required this.selectedClass,
    required this.loadSteps,
    required this.runtimeNodes,
    required this.sources,
    required this.sourceErrors,
    required this.tables,
  });

  factory TouchkeyPayload.fromJson(Map<String, dynamic> json) {
    final programKey = asString(json['program_key']).trim().toLowerCase();
    final gridPrep = asMap(json['grid_prep']);
    final rawLoadSteps = json['load_steps'] is List
        ? asListOfMaps(json['load_steps'])
        : asListOfMaps(gridPrep['actions']);
    final rawTables = asListOfMaps(json['tables']);
    final rawSources = asListOfMaps(json['sources']);
    final rawSourceErrors = asListOfMaps(json['source_errors']);

    return TouchkeyPayload(
      label: asString(json['label']),
      description: asString(json['description']),
      programKey: programKey.isEmpty ? 'touchkey' : programKey,
      programCode: asString(json['program_code']),
      programPath: asString(json['program_path']),
      rowLimit: asInt(json['row_limit']),
      fetchedAt: asString(json['fetched_at']),
      loadStatus: asString(json['load_status']),
      openResult: asMap(json['open_result']),
      datasetCounts: asIntMap(json['dataset_counts']),
      selectedClass: asMap(json['selected_class']),
      loadSteps:
          rawLoadSteps.map(TouchkeyLoadStep.fromJson).toList(growable: false),
      runtimeNodes: asListOfMaps(asMap(json['runtime'])['nodes']),
      sources: rawSources
          .map(TouchkeySourceSummary.fromJson)
          .toList(growable: false),
      sourceErrors: rawSourceErrors
          .map(TouchkeySourceError.fromJson)
          .toList(growable: false),
      tables: List<TouchkeyTable>.generate(
        rawTables.length,
        (index) => TouchkeyTable.fromJson(rawTables[index], index: index),
        growable: false,
      ),
    );
  }
}

class TouchkeyLoadStep {
  final String type;
  final String reason;
  final String classCode;
  final String sortValue;
  final String sourceProgramKey;
  final String sourceProgramCode;
  final String sourceLabel;

  const TouchkeyLoadStep({
    required this.type,
    required this.reason,
    required this.classCode,
    required this.sortValue,
    required this.sourceProgramKey,
    required this.sourceProgramCode,
    required this.sourceLabel,
  });

  factory TouchkeyLoadStep.fromJson(Map<String, dynamic> json) {
    return TouchkeyLoadStep(
      type: asString(json['type']),
      reason: asString(json['reason']),
      classCode: asString(json['class_code']),
      sortValue: asString(json['sort_value']),
      sourceProgramKey: asString(json['source_program_key']),
      sourceProgramCode: asString(json['source_program_code']),
      sourceLabel: asString(json['source_label']),
    );
  }

  String get title {
    final prefix = sourceLabel.isEmpty ? '' : '$sourceLabel · ';
    switch (type) {
      case 'fnSelectTouchKeyClassList':
        return '$prefix분류 목록 로드';
      case 'fnSelectTouchKeyList':
        return '$prefix기본 상품 목록 로드';
      case 'fn_SelectTouchKeyList':
        return '$prefix위치형 슬롯 로드';
      case 'skip-class-load':
        return '$prefix분류 재조회 생략';
      case 'skip-touchkey-load':
        return '$prefix상품 로드 생략';
      default:
        return type.isEmpty ? '-' : '$prefix$type';
    }
  }

  String get detail {
    switch (type) {
      case 'fnSelectTouchKeyClassList':
        return '터치키 분류 데이터셋을 초기 조회했습니다.';
      case 'fnSelectTouchKeyList':
        return '선택 분류 ${classCode.isEmpty ? '-' : classCode} / 순번 ${sortValue.isEmpty ? '-' : sortValue} 기준으로 상품 목록을 조회했습니다.';
      case 'fn_SelectTouchKeyList':
        return '위치형 화면에서 순번 ${sortValue.isEmpty ? '-' : sortValue} 기준 슬롯을 렌더링했습니다.';
      case 'skip-class-load':
        return reason == 'touchkey-class-already-loaded'
            ? '기존 분류 데이터가 이미 메모리에 있어 재사용했습니다.'
            : (reason.isEmpty ? '-' : reason);
      case 'skip-touchkey-load':
        switch (reason) {
          case 'no-touchkey-class-rows':
            return '분류 행이 없어 상품 조회를 진행하지 않았습니다.';
          case 'touchkey-already-loaded':
            return '분류 ${classCode.isEmpty ? '-' : classCode} / 순번 ${sortValue.isEmpty ? '-' : sortValue} 결과가 이미 로드되어 있었습니다.';
          case 'touchkey-list-function-missing':
            return '화면 내부 조회 함수가 없어 추가 로드를 생략했습니다.';
          default:
            return reason.isEmpty ? '-' : reason;
        }
      default:
        final parts = <String>[
          if (reason.isNotEmpty) reason,
          if (classCode.isNotEmpty) '분류 $classCode',
          if (sortValue.isNotEmpty) '순번 $sortValue',
        ];
        return parts.isEmpty ? '-' : parts.join(' · ');
    }
  }
}

class TouchkeySourceSummary {
  final String programKey;
  final String programCode;
  final String label;
  final String programPath;
  final String loadStatus;
  final int tableCount;
  final String fetchedAt;

  const TouchkeySourceSummary({
    required this.programKey,
    required this.programCode,
    required this.label,
    required this.programPath,
    required this.loadStatus,
    required this.tableCount,
    required this.fetchedAt,
  });

  factory TouchkeySourceSummary.fromJson(Map<String, dynamic> json) {
    return TouchkeySourceSummary(
      programKey: asString(json['program_key']),
      programCode: asString(json['program_code']),
      label: asString(json['label']),
      programPath: asString(json['program_path']),
      loadStatus: asString(json['load_status']),
      tableCount: asInt(json['table_count']),
      fetchedAt: asString(json['fetched_at']),
    );
  }
}

class TouchkeySourceError {
  final String programKey;
  final String programCode;
  final String label;
  final String programPath;
  final String error;

  const TouchkeySourceError({
    required this.programKey,
    required this.programCode,
    required this.label,
    required this.programPath,
    required this.error,
  });

  factory TouchkeySourceError.fromJson(Map<String, dynamic> json) {
    return TouchkeySourceError(
      programKey: asString(json['program_key']),
      programCode: asString(json['program_code']),
      label: asString(json['label']),
      programPath: asString(json['program_path']),
      error: asString(json['error']),
    );
  }
}

class TouchkeyTable {
  final String gridKey;
  final String gridName;
  final String gridPath;
  final String sourceProgramKey;
  final String sourceProgramCode;
  final String sourceLabel;
  final String binddataset;
  final String binddatasetResolved;
  final int rowCount;
  final List<String> columns;
  final List<List<String>> rows;
  final int bodyCellCount;
  final int formatLength;
  final int filledCells;
  final String displayKind;

  const TouchkeyTable({
    required this.gridKey,
    required this.gridName,
    required this.gridPath,
    required this.sourceProgramKey,
    required this.sourceProgramCode,
    required this.sourceLabel,
    required this.binddataset,
    required this.binddatasetResolved,
    required this.rowCount,
    required this.columns,
    required this.rows,
    required this.bodyCellCount,
    required this.formatLength,
    required this.filledCells,
    required this.displayKind,
  });

  factory TouchkeyTable.fromJson(
    Map<String, dynamic> json, {
    required int index,
  }) {
    final columns = _normalizeColumns(json['columns']);
    final rows = _normalizeRows(json['rows'], columns);
    final filledCells = rows.fold<int>(
      0,
      (count, row) =>
          count +
          row.where((cell) => cell.trim().isNotEmpty && cell != '-').length,
    );
    final gridPath = asString(json['grid_path']).trim();
    final gridName = asString(json['grid_name']).trim();
    final rowCount = asInt(json['rowcount']);
    final binddataset = asString(json['binddataset']);
    final binddatasetResolved = asString(json['binddataset_resolved']);

    return TouchkeyTable(
      gridKey: gridPath.isNotEmpty
          ? gridPath
          : (gridName.isNotEmpty ? gridName : 'grid-$index'),
      gridName: gridName.isEmpty ? '그리드' : gridName,
      gridPath: gridPath,
      sourceProgramKey: asString(json['source_program_key']),
      sourceProgramCode: asString(json['source_program_code']),
      sourceLabel: asString(json['source_label']),
      binddataset: binddataset,
      binddatasetResolved: binddatasetResolved,
      rowCount: rowCount > 0 ? rowCount : rows.length,
      columns: columns,
      rows: rows,
      bodyCellCount: asInt(json['body_cell_count']),
      formatLength: asInt(json['format_length']),
      filledCells: filledCells,
      displayKind: _describeDisplayKind(
        columns,
        binddataset: binddataset,
        binddatasetResolved: binddatasetResolved,
      ),
    );
  }

  List<Map<String, String>> get objectRows => rows
      .map((row) => <String, String>{
            for (var index = 0; index < columns.length; index++)
              columns[index]: index < row.length ? row[index] : '-',
          })
      .toList(growable: false);

  static List<String> _normalizeColumns(Object? source) {
    if (source is! List) {
      return const [];
    }
    return source
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static List<List<String>> _normalizeRows(
    Object? source,
    List<String> columns,
  ) {
    if (source is! List) {
      return const [];
    }
    return source.map<List<String>>((row) {
      if (row is Map) {
        final mapped = Map<String, dynamic>.from(row);
        return columns
            .map((column) => _normalizeCell(mapped[column]))
            .toList(growable: false);
      }
      if (row is List) {
        if (columns.isNotEmpty) {
          return List<String>.generate(
            columns.length,
            (index) => index < row.length ? _normalizeCell(row[index]) : '-',
            growable: false,
          );
        }
        return row.map(_normalizeCell).toList(growable: false);
      }
      return columns.map((_) => '-').toList(growable: false);
    }).toList(growable: false);
  }

  static String _normalizeCell(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '-' : text;
  }

  static String _describeDisplayKind(
    List<String> columns, {
    required String binddataset,
    required String binddatasetResolved,
  }) {
    final datasetNames = <String>[
      _normalizeDatasetName(binddatasetResolved),
      _normalizeDatasetName(binddataset),
    ].where((value) => value.isNotEmpty).toList(growable: false);
    if (datasetNames
        .any((value) => _matchesDatasetHint(value, 'dstouchkeyclass'))) {
      return '분류 데이터셋';
    }
    if (datasetNames.any((value) => _matchesDatasetHint(value, 'dstouchkey'))) {
      return '상품 데이터셋';
    }
    if (columns.isNotEmpty &&
        columns.every((column) =>
            RegExp(r'^slot_\d+$', caseSensitive: false).hasMatch(column))) {
      return '렌더링 슬롯';
    }
    if (columns.any((column) => column.contains('분류'))) {
      return '분류 데이터셋';
    }
    if (columns.any(
      (column) => column.contains('상품') || column.contains('판매가'),
    )) {
      return '상품 데이터셋';
    }
    return '그리드 데이터';
  }

  static String _normalizeDatasetName(String value) {
    return value.trim().toLowerCase();
  }

  static bool _matchesDatasetHint(String value, String hint) {
    return value == hint || value.endsWith('.$hint') || value.contains(hint);
  }
}
