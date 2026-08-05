import 'dart:async';

import 'package:cafe_bridge_flutter/screens/daily_report_monitor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses nullable and loosely typed daily report contracts', () {
    final settings = DailyReportSettingsSummary.fromJson({
      'settings': {
        'enabled': 'true',
        'schedule_time': 930,
        'timezone': null,
        'weekdays': ['mon', 'fri', null],
      },
      'next_run_at': '2026-07-24T00:30:00Z',
      'secret_status': {
        'telegram_bot_token': {'configured': true},
        'opencode_go_api_token': {'configured': 'false'},
        'future_secret': null,
      },
    });
    final runs = DailyReportRun.parseList({
      'runs': [
        {
          'id': 'run-1',
          'status': 'RUNNING',
          'records_collected': '1,234',
          'attempts': 2.8,
          'error_message': ['first', 'second'],
          'warning_message': '',
          'report': {'title': '제목', 'content': null},
        },
        'invalid row',
        {'status': 'missing id'},
      ],
    });
    final audits = DailyReportAudit.parseList({
      'audits': [
        {'id': 7, 'detail': null},
      ],
    });

    expect(settings.enabled, isTrue);
    expect(settings.scheduleTime, '930');
    expect(settings.timezone, isNull);
    expect(settings.weekdayLabel, '월, 금');
    expect(settings.secretStatus['telegram_bot_token'], isTrue);
    expect(settings.secretStatus['opencode_go_api_token'], isFalse);
    expect(settings.secretStatus['future_secret'], isNull);
    expect(runs, hasLength(1));
    expect(runs.single.isActive, isTrue);
    expect(runs.single.recordsCollected, 1234);
    expect(runs.single.attempts, 2);
    expect(runs.single.errorMessage, 'first; second');
    expect(runs.single.warningMessage, isNull);
    expect(audits.single.id, '7');
    expect(DailyReportFormat.kst(settings.nextRunAt), '2026-07-24 09:30 KST');
    expect(DailyReportFormat.kst('not-a-date'), 'not-a-date');
    expect(DailyReportFormat.kst(null), '-');
  });

  testWidgets('renders the narrow read-only monitor and loads run detail',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final calls = <String>[];
    final queries = <String, Map<String, Object?>?>{};
    Future<Map<String, dynamic>> fetch(
      String endpoint, {
      Map<String, Object?>? params,
    }) async {
      calls.add(endpoint);
      queries[endpoint] = params == null ? null : Map.of(params);
      if (endpoint.endsWith('/settings')) {
        return {
          'settings': {
            'enabled': true,
            'schedule_time': '08:30',
            'timezone': 'Asia/Seoul',
            'weekdays': ['mon', 'tue', 'wed', 'thu', 'fri'],
          },
          'next_run_at': '2026-07-25T00:00:00Z',
          'secret_status': {
            'telegram_bot_token': {'configured': true},
          },
        };
      }
      if (endpoint.endsWith('/runs')) {
        return {
          'runs': [
            {
              'id': 'run-1',
              'target_date': '2026-07-24',
              'status': 'succeeded',
              'trigger': 'scheduled',
              'created_at': '2026-07-24T00:00:00Z',
            },
          ],
        };
      }
      if (endpoint.endsWith('/audits')) {
        return {'audits': []};
      }
      if (endpoint.endsWith('/runs/run-1')) {
        return {
          'run': {
            'id': 'run-1',
            'target_date': '2026-07-24',
            'status': 'succeeded',
            'records_collected': 42,
            'attempts': 1,
            'report': {'title': '7월 24일 보고서', 'content': '매출 요약 본문'},
          },
        };
      }
      throw StateError('unexpected endpoint: $endpoint');
    }

    await tester.pumpWidget(
      MaterialApp(
          home: Scaffold(body: DailyReportMonitorScreen(fetchJson: fetch))),
    );
    await tester.pumpAndSettle();

    expect(find.text('일일보고서 모니터'), findsOneWidget);
    expect(find.textContaining('웹 관리자 화면'), findsOneWidget);
    expect(find.text('2026-07-24'), findsOneWidget);
    expect(
        calls,
        containsAll(<String>[
          '/api/admin/daily-reports/settings',
          '/api/admin/daily-reports/runs',
          '/api/admin/daily-reports/audits',
        ]));
    expect(queries['/api/admin/daily-reports/runs'], {'limit': 30});
    expect(queries['/api/admin/daily-reports/audits'], {'limit': 30});

    await tester.tap(find.text('2026-07-24'));
    await tester.pumpAndSettle();

    expect(calls, contains('/api/admin/daily-reports/runs/run-1'));
    expect(find.text('7월 24일 보고서'), findsOneWidget);
    expect(find.text('매출 요약 본문'), findsOneWidget);
    expect(find.text('수집 42'), findsOneWidget);
    expect(find.text('시도 1'), findsOneWidget);
  });

  testWidgets('active run polling stays sequential and stops on dispose',
      (tester) async {
    var runCalls = 0;
    var inFlight = 0;
    var maximumInFlight = 0;
    final blockedPoll = Completer<Map<String, dynamic>>();

    Future<Map<String, dynamic>> fetch(
      String endpoint, {
      Map<String, Object?>? params,
    }) async {
      if (endpoint.endsWith('/settings')) {
        return {'settings': <String, dynamic>{}};
      }
      if (endpoint.endsWith('/audits')) {
        return {'audits': <dynamic>[]};
      }
      if (endpoint.endsWith('/runs')) {
        runCalls += 1;
        inFlight += 1;
        maximumInFlight =
            inFlight > maximumInFlight ? inFlight : maximumInFlight;
        if (runCalls == 1) {
          inFlight -= 1;
          return {
            'runs': [
              {'id': 'active', 'status': 'pending'},
            ],
          };
        }
        final result = await blockedPoll.future;
        inFlight -= 1;
        return result;
      }
      throw StateError('unexpected endpoint: $endpoint');
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DailyReportMonitorScreen(
            fetchJson: fetch,
            pollingInterval: const Duration(milliseconds: 20),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(runCalls, 2);
    expect(maximumInFlight, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    blockedPoll.complete({'runs': <dynamic>[]});
    await tester.pump(const Duration(milliseconds: 100));

    expect(runCalls, 2);
    expect(tester.takeException(), isNull);
  });
}
