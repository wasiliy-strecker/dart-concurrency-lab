import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'batch_dispatcher.dart';
import 'batch_models.dart';
import 'record_parser.dart';

/// Long-lived isolate pool with one safe retry after an unexpected worker exit.
final class IsolateBatchDispatcher implements BatchDispatcher {
  IsolateBatchDispatcher._({
    required this.workerCount,
    required Duration workerDelayForTesting,
  }) : _workerDelayMicros = workerDelayForTesting.inMicroseconds;

  /// Starts [workerCount] parser isolates and waits until all are ready.
  static Future<IsolateBatchDispatcher> start({
    required int workerCount,
    Duration workerDelayForTesting = Duration.zero,
  }) async {
    if (workerCount < 1) {
      throw ArgumentError.value(workerCount, 'workerCount', 'must be positive');
    }
    final dispatcher = IsolateBatchDispatcher._(
      workerCount: workerCount,
      workerDelayForTesting: workerDelayForTesting,
    );
    try {
      for (var index = 0; index < workerCount; index += 1) {
        await dispatcher._spawnSlot(index);
      }
      return dispatcher;
    } on Object {
      await dispatcher.close();
      rethrow;
    }
  }

  /// Number of live worker slots maintained by this pool.
  final int workerCount;

  final int _workerDelayMicros;
  final Map<int, _WorkerSlot> _slots = <int, _WorkerSlot>{};
  final Queue<_PendingBatch> _pending = Queue<_PendingBatch>();
  final Map<int, _PendingBatch> _jobs = <int, _PendingBatch>{};
  var _tokenSeed = 0;
  var _closing = false;
  var _workerRestarts = 0;

  @override
  int get workerRestarts => _workerRestarts;

  @override
  Future<ParsedBatch> submit({
    required int batchId,
    required List<SourceLine> lines,
    required int maxErrors,
    required int slowestEventLimit,
  }) {
    if (_closing) {
      return Future<ParsedBatch>.error(
        StateError('Cannot submit work after the dispatcher is closed.'),
      );
    }
    if (_jobs.containsKey(batchId)) {
      return Future<ParsedBatch>.error(
        ArgumentError.value(batchId, 'batchId', 'must be unique'),
      );
    }
    final pending = _PendingBatch(
      batchId: batchId,
      lines: List<SourceLine>.unmodifiable(lines),
      maxErrors: maxErrors,
      slowestEventLimit: slowestEventLimit,
    );
    _jobs[batchId] = pending;
    _pending.addLast(pending);
    _dispatch();
    return pending.completer.future;
  }

  /// Terminates one worker to exercise restart behavior in focused tests.
  Future<void> terminateWorkerForTesting([int index = 0]) async {
    if (_closing) throw StateError('The dispatcher is closed.');
    final slot = _slots[index];
    if (slot == null || slot.isolate == null) {
      throw RangeError.index(index, _slots, 'index');
    }
    final previousToken = slot.token;
    final expectedRestarts = _workerRestarts + 1;
    slot.isolate!.kill(priority: Isolate.immediate);

    await Future<void>(() async {
      while (_workerRestarts < expectedRestarts ||
          _slots[index]?.token == previousToken ||
          _slots[index]?.commandPort == null) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }).timeout(const Duration(seconds: 5));
  }

  @override
  Future<void> close() async {
    if (_closing) return;
    _closing = true;

    final failure = StateError('The isolate dispatcher was closed.');
    for (final job in _jobs.values) {
      if (!job.completer.isCompleted) {
        job.completer.completeError(failure, StackTrace.current);
      }
    }
    _jobs.clear();
    _pending.clear();

    final slots = _slots.values.toList(growable: false);
    _slots.clear();
    for (final slot in slots) {
      slot.failed = true;
      slot.commandPort?.send(const _ShutdownWorker());
      slot.isolate?.kill(priority: Isolate.immediate);
      slot.receivePort.close();
      await slot.subscription?.cancel();
    }
  }

  Future<void> _spawnSlot(int index) async {
    if (_closing) return;
    final receivePort = ReceivePort('ndjson-worker-$index-events');
    final ready = Completer<void>();
    final slot = _WorkerSlot(
      index: index,
      token: _tokenSeed += 1,
      receivePort: receivePort,
      ready: ready,
    );
    _slots[index] = slot;
    slot.subscription = receivePort.listen(
      (Object? message) => _handleWorkerMessage(slot, message),
    );

    try {
      slot.isolate = await Isolate.spawn<_WorkerBootstrap>(
        _workerMain,
        _WorkerBootstrap(
          token: slot.token,
          replyPort: receivePort.sendPort,
          delayMicros: _workerDelayMicros,
        ),
        onError: receivePort.sendPort,
        onExit: receivePort.sendPort,
        debugName: 'ndjson-parser-$index-${slot.token}',
      );
      await ready.future.timeout(const Duration(seconds: 5));
    } on Object {
      if (_slots[index] == slot) _slots.remove(index);
      slot.failed = true;
      slot.isolate?.kill(priority: Isolate.immediate);
      receivePort.close();
      await slot.subscription?.cancel();
      rethrow;
    }
  }

  void _handleWorkerMessage(_WorkerSlot slot, Object? message) {
    if (_closing || slot.failed || _slots[slot.index] != slot) return;

    switch (message) {
      case _WorkerReady(:final token, :final commandPort)
          when token == slot.token:
        slot.commandPort = commandPort;
        if (!slot.ready.isCompleted) slot.ready.complete();
        _dispatch();
      case _WorkerCompleted(:final token, :final batch)
          when token == slot.token:
        _completeBatch(slot, batch);
      case null:
        unawaited(_handleWorkerFailure(slot, 'Worker exited unexpectedly.'));
      case [_, _]:
        unawaited(_handleWorkerFailure(slot, 'Worker raised an error.'));
      default:
        unawaited(
          _handleWorkerFailure(
            slot,
            'Worker sent an invalid protocol message.',
          ),
        );
    }
  }

  void _completeBatch(_WorkerSlot slot, ParsedBatch batch) {
    if (slot.busyBatchId != batch.batchId) {
      unawaited(
        _handleWorkerFailure(slot, 'Worker returned the wrong batch ID.'),
      );
      return;
    }
    slot.busyBatchId = null;
    final job = _jobs.remove(batch.batchId);
    if (job != null && !job.completer.isCompleted) {
      job.completer.complete(batch);
    }
    _dispatch();
  }

  Future<void> _handleWorkerFailure(
    _WorkerSlot slot,
    String description,
  ) async {
    if (_closing || slot.failed || _slots[slot.index] != slot) return;
    slot.failed = true;
    _slots.remove(slot.index);
    slot.isolate?.kill(priority: Isolate.immediate);
    slot.receivePort.close();
    await slot.subscription?.cancel();

    if (!slot.ready.isCompleted) {
      slot.ready.completeError(StateError(description), StackTrace.current);
      return;
    }

    final busyBatchId = slot.busyBatchId;
    if (busyBatchId != null) {
      final job = _jobs[busyBatchId];
      if (job != null && !job.completer.isCompleted) {
        if (job.attempts < 2) {
          _pending.addFirst(job);
        } else {
          _jobs.remove(busyBatchId);
          job.completer.completeError(
            WorkerBatchException(
              batchId: busyBatchId,
              message: '$description Retry exhausted.',
            ),
            StackTrace.current,
          );
        }
      }
    }

    _workerRestarts += 1;
    try {
      await _spawnSlot(slot.index);
      _dispatch();
    } on Object catch (error, stackTrace) {
      _failAll(error, stackTrace);
    }
  }

  void _dispatch() {
    if (_closing || _pending.isEmpty) return;
    final slots = _slots.values.toList(growable: false)
      ..sort(
        (_WorkerSlot left, _WorkerSlot right) =>
            left.index.compareTo(right.index),
      );
    for (final slot in slots) {
      if (_pending.isEmpty) break;
      if (slot.failed || slot.commandPort == null || slot.busyBatchId != null) {
        continue;
      }

      _PendingBatch? job;
      while (_pending.isNotEmpty && job == null) {
        final candidate = _pending.removeFirst();
        if (!candidate.completer.isCompleted) job = candidate;
      }
      if (job == null) return;

      job.attempts += 1;
      slot.busyBatchId = job.batchId;
      try {
        slot.commandPort!.send(
          _ParseBatch(
            batchId: job.batchId,
            lines: job.lines,
            maxErrors: job.maxErrors,
            slowestEventLimit: job.slowestEventLimit,
          ),
        );
      } on Object {
        unawaited(_handleWorkerFailure(slot, 'Could not send work to worker.'));
      }
    }
  }

  void _failAll(Object error, StackTrace stackTrace) {
    for (final job in _jobs.values) {
      if (!job.completer.isCompleted) {
        job.completer.completeError(error, stackTrace);
      }
    }
    _jobs.clear();
    _pending.clear();
  }
}

final class _PendingBatch {
  _PendingBatch({
    required this.batchId,
    required this.lines,
    required this.maxErrors,
    required this.slowestEventLimit,
  });

  final int batchId;
  final List<SourceLine> lines;
  final int maxErrors;
  final int slowestEventLimit;
  final Completer<ParsedBatch> completer = Completer<ParsedBatch>();
  var attempts = 0;
}

final class _WorkerSlot {
  _WorkerSlot({
    required this.index,
    required this.token,
    required this.receivePort,
    required this.ready,
  });

  final int index;
  final int token;
  final ReceivePort receivePort;
  final Completer<void> ready;
  // Cancelled whenever the slot exits, fails, or the pool closes.
  // ignore: cancel_subscriptions
  StreamSubscription<Object?>? subscription;
  Isolate? isolate;
  SendPort? commandPort;
  int? busyBatchId;
  var failed = false;
}

final class _WorkerBootstrap {
  const _WorkerBootstrap({
    required this.token,
    required this.replyPort,
    required this.delayMicros,
  });

  final int token;
  final SendPort replyPort;
  final int delayMicros;
}

final class _WorkerReady {
  const _WorkerReady({required this.token, required this.commandPort});

  final int token;
  final SendPort commandPort;
}

final class _ParseBatch {
  const _ParseBatch({
    required this.batchId,
    required this.lines,
    required this.maxErrors,
    required this.slowestEventLimit,
  });

  final int batchId;
  final List<SourceLine> lines;
  final int maxErrors;
  final int slowestEventLimit;
}

final class _WorkerCompleted {
  const _WorkerCompleted({required this.token, required this.batch});

  final int token;
  final ParsedBatch batch;
}

final class _ShutdownWorker {
  const _ShutdownWorker();
}

Future<void> _workerMain(_WorkerBootstrap bootstrap) async {
  final commands = ReceivePort('ndjson-worker-${bootstrap.token}-commands');
  bootstrap.replyPort.send(
    _WorkerReady(token: bootstrap.token, commandPort: commands.sendPort),
  );

  await for (final Object? message in commands) {
    switch (message) {
      case _ParseBatch(
        :final batchId,
        :final lines,
        :final maxErrors,
        :final slowestEventLimit,
      ):
        if (bootstrap.delayMicros > 0) {
          await Future<void>.delayed(
            Duration(microseconds: bootstrap.delayMicros),
          );
        }
        final batch = parseRecordBatch(
          batchId: batchId,
          lines: lines,
          maxErrors: maxErrors,
          slowestEventLimit: slowestEventLimit,
        );
        bootstrap.replyPort.send(
          _WorkerCompleted(token: bootstrap.token, batch: batch),
        );
      case _ShutdownWorker():
        commands.close();
        return;
      default:
        throw StateError('Unknown worker protocol message.');
    }
  }
}
