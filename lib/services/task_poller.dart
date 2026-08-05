import 'dart:async';

typedef TaskStatusReader<T> = String? Function(T value);

class TaskStatusAdapter<T> {
  const TaskStatusAdapter({
    required this.statusOf,
    this.successStatuses = const {
      'success',
      'succeeded',
      'completed',
      'done',
      'sent',
      'skipped',
    },
    this.failureStatuses = const {
      'failure',
      'failed',
      'error',
      'partial_failed',
      'ambiguous',
      'cancelled',
      'canceled',
      'timed_out',
    },
  });

  factory TaskStatusAdapter.directMap({String statusKey = 'status'}) {
    return TaskStatusAdapter<T>(
      statusOf: (value) {
        if (value is! Map) {
          return null;
        }
        return value[statusKey]?.toString();
      },
    );
  }

  factory TaskStatusAdapter.wrappedMap({
    String wrapperKey = 'task',
    String statusKey = 'status',
  }) {
    return TaskStatusAdapter<T>(
      statusOf: (value) {
        if (value is! Map) {
          return null;
        }
        final wrapped = value[wrapperKey];
        if (wrapped is! Map) {
          return null;
        }
        return wrapped[statusKey]?.toString();
      },
    );
  }

  final TaskStatusReader<T> statusOf;
  final Set<String> successStatuses;
  final Set<String> failureStatuses;

  bool isSuccess(String status) =>
      successStatuses.contains(status.trim().toLowerCase());

  bool isFailure(String status) =>
      failureStatuses.contains(status.trim().toLowerCase());
}

class TaskPoller<T> {
  TaskPoller({
    required this.fetch,
    required this.adapter,
    this.interval = const Duration(seconds: 2),
    this.timeout = const Duration(minutes: 2),
  });

  final Future<T> Function() fetch;
  final TaskStatusAdapter<T> adapter;
  final Duration interval;
  final Duration timeout;

  Future<T>? _activePoll;
  Completer<void>? _cancelled;

  Future<T> poll() {
    final active = _activePoll;
    if (active != null) {
      return active;
    }
    _cancelled = Completer<void>();
    final future = _runAndClear();
    _activePoll = future;
    return future;
  }

  void cancel() {
    final cancelled = _cancelled;
    if (cancelled != null && !cancelled.isCompleted) {
      cancelled.complete();
    }
  }

  Future<T> _run() async {
    final stopwatch = Stopwatch()..start();
    while (true) {
      _throwIfCancelled();
      final remaining = timeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('Task polling timed out.', timeout);
      }

      final value = await Future.any<T>([
        fetch(),
        _cancelled!.future.then<T>(
          (_) => throw const TaskPollingCancelledException(),
        ),
      ]).timeout(remaining);
      _throwIfCancelled();
      final status = adapter.statusOf(value)?.trim() ?? '';
      if (adapter.isSuccess(status)) {
        return value;
      }
      if (adapter.isFailure(status)) {
        throw TaskPollingFailedException<T>(status, value);
      }

      final remainingAfterFetch = timeout - stopwatch.elapsed;
      if (remainingAfterFetch <= Duration.zero) {
        throw TimeoutException('Task polling timed out.', timeout);
      }
      if (interval == Duration.zero) {
        continue;
      }
      final delay =
          interval < remainingAfterFetch ? interval : remainingAfterFetch;
      await Future.any<void>([
        Future<void>.delayed(delay),
        _cancelled!.future,
      ]);
      _throwIfCancelled();
    }
  }

  Future<T> _runAndClear() async {
    try {
      return await _run();
    } finally {
      _activePoll = null;
    }
  }

  void _throwIfCancelled() {
    if (_cancelled?.isCompleted == true) {
      throw const TaskPollingCancelledException();
    }
  }
}

class TaskPollingFailedException<T> implements Exception {
  const TaskPollingFailedException(this.status, this.value);

  final String status;
  final T value;

  @override
  String toString() => 'Task failed with status: $status';
}

class TaskPollingCancelledException implements Exception {
  const TaskPollingCancelledException();

  @override
  String toString() => 'Task polling was cancelled.';
}
