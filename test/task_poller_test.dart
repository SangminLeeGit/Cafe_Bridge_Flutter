import 'dart:async';

import 'package:cafe_bridge_flutter/services/task_poller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('polls sequentially and returns direct terminal success', () async {
    var calls = 0;
    var inFlight = 0;
    var maximumInFlight = 0;
    final poller = TaskPoller<Map<String, dynamic>>(
      interval: Duration.zero,
      timeout: const Duration(seconds: 1),
      adapter: TaskStatusAdapter<Map<String, dynamic>>.directMap(),
      fetch: () async {
        calls += 1;
        inFlight += 1;
        maximumInFlight =
            inFlight > maximumInFlight ? inFlight : maximumInFlight;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlight -= 1;
        return {'status': calls == 3 ? 'SUCCEEDED' : 'running'};
      },
    );

    final first = poller.poll();
    final second = poller.poll();
    expect(identical(first, second), isTrue);
    expect((await first)['status'], 'SUCCEEDED');
    expect(calls, 3);
    expect(maximumInFlight, 1);
  });

  test('supports wrapped status and reports terminal failure', () async {
    final value = <String, dynamic>{
      'task': {'status': 'failed'},
    };
    final poller = TaskPoller<Map<String, dynamic>>(
      adapter: TaskStatusAdapter<Map<String, dynamic>>.wrappedMap(),
      fetch: () async => value,
    );

    await expectLater(
      poller.poll(),
      throwsA(
        isA<TaskPollingFailedException<Map<String, dynamic>>>()
            .having((error) => error.status, 'status', 'failed')
            .having((error) => error.value, 'value', same(value)),
      ),
    );
  });

  test('recognizes every backend terminal status family', () {
    final adapter = TaskStatusAdapter<Map<String, dynamic>>.directMap();
    for (final status in [
      'succeeded',
      'success',
      'completed',
      'sent',
      'skipped'
    ]) {
      expect(adapter.isSuccess(status), isTrue, reason: status);
    }
    for (final status in [
      'failed',
      'partial_failed',
      'ambiguous',
      'cancelled',
      'canceled',
      'timed_out',
    ]) {
      expect(adapter.isFailure(status), isTrue, reason: status);
    }
  });

  test('cancel interrupts the wait and timeout is enforced', () async {
    final poller = TaskPoller<Map<String, dynamic>>(
      interval: const Duration(seconds: 10),
      timeout: const Duration(minutes: 1),
      adapter: TaskStatusAdapter<Map<String, dynamic>>.directMap(),
      fetch: () async => {'status': 'running'},
    );
    final result = poller.poll();
    await Future<void>.delayed(Duration.zero);
    poller.cancel();
    await expectLater(result, throwsA(isA<TaskPollingCancelledException>()));

    final timedOut = TaskPoller<Map<String, dynamic>>(
      interval: const Duration(milliseconds: 20),
      timeout: const Duration(milliseconds: 5),
      adapter: TaskStatusAdapter<Map<String, dynamic>>.directMap(),
      fetch: () async => {'status': 'running'},
    );
    await expectLater(timedOut.poll(), throwsA(isA<TimeoutException>()));
  });
}
