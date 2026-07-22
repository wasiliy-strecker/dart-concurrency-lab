import 'dart:async';

import 'cancellation.dart';
import 'input/line_decoder.dart';
import 'model/analysis_options.dart';
import 'model/analysis_progress.dart';
import 'model/analysis_report.dart';
import 'pipeline/analysis_accumulator.dart';
import 'pipeline/batch_dispatcher.dart';
import 'pipeline/batch_models.dart';
import 'pipeline/isolate_batch_dispatcher.dart';

/// Starts bounded, cancellable NDJSON analysis runs.
final class NdjsonAnalyzer {
  /// Creates a stateless analyzer facade.
  const NdjsonAnalyzer();

  /// Starts consuming [input] immediately.
  AnalysisRun start(
    Stream<List<int>> input, {
    AnalysisOptions options = const AnalysisOptions(),
  }) {
    _validateOptions(options);
    final cancellation = CancellationSource();
    // Closed by _analyze's finally block on every completion path.
    // ignore: close_sinks
    final progress = StreamController<AnalysisProgress>.broadcast(sync: true);
    final done = _analyze(
      input,
      options: options,
      cancellation: cancellation,
      progress: progress,
    );
    return AnalysisRun._(
      done: done,
      progress: progress.stream,
      cancellation: cancellation,
    );
  }
}

/// Handle for one active or completed analysis.
final class AnalysisRun {
  const AnalysisRun._({
    required this.done,
    required this.progress,
    required this._cancellation,
  });

  final CancellationSource _cancellation;

  /// Completes with a deterministic complete or partial report.
  final Future<AnalysisReport> done;

  /// Best-effort progress snapshots. Slow listeners never block analysis.
  final Stream<AnalysisProgress> progress;

  /// Whether cancellation or a timeout has been requested.
  bool get isCancelled => _cancellation.isCancelled;

  /// Requests graceful cancellation and returns whether this call won.
  bool cancel() => _cancellation.cancel();
}

Future<AnalysisReport> _analyze(
  Stream<List<int>> input, {
  required AnalysisOptions options,
  required CancellationSource cancellation,
  required StreamController<AnalysisProgress> progress,
}) async {
  Timer? deadline;
  BatchDispatcher? dispatcher;
  StreamIterator<List<int>>? iterator;
  Completer<void>? iteratorFinished;
  Future<void>? cancellationWatcher;

  if (options.timeout case final timeout?) {
    deadline = Timer(
      timeout,
      () => cancellation.cancel(CancellationReason.timedOut),
    );
  }

  try {
    dispatcher = options.sequential
        ? const SequentialBatchDispatcher()
        : await IsolateBatchDispatcher.start(workerCount: options.workerCount);

    final accumulator = AnalysisAccumulator(
      maxErrors: options.maxErrors,
      slowestEventLimit: options.slowestEventLimit,
    );
    final inFlight = <int, Future<_CompletedBatch>>{};
    final currentBatch = <SourceLine>[];
    var nextBatchId = 0;
    var maxObservedInFlight = 0;

    void emitProgress() {
      progress.add(
        AnalysisProgress(
          linesRead: accumulator.linesRead,
          validRecords: accumulator.validRecords,
          invalidRecords: accumulator.invalidRecords,
          inFlightBatches: inFlight.length,
          maxObservedInFlightBatches: maxObservedInFlight,
        ),
      );
    }

    Future<void> collectOne() async {
      if (inFlight.isEmpty) return;
      final completed = await Future.any<_CompletedBatch>(inFlight.values);
      final removed = inFlight.remove(completed.batchId);
      if (removed == null) {
        throw StateError('Completed batch was not in flight.');
      }
      accumulator.merge(completed.batch);
      emitProgress();
    }

    Future<void> submitCurrentBatch() async {
      if (currentBatch.isEmpty) return;
      while (inFlight.length >= options.maxInFlightBatches) {
        await collectOne();
      }

      final batchId = nextBatchId;
      nextBatchId += 1;
      final lines = List<SourceLine>.unmodifiable(currentBatch);
      currentBatch.clear();
      final completion = dispatcher!
          .submit(
            batchId: batchId,
            lines: lines,
            maxErrors: options.maxErrors,
            slowestEventLimit: options.slowestEventLimit,
          )
          .then<_CompletedBatch>(
            (ParsedBatch batch) => (batchId: batchId, batch: batch),
          );
      inFlight[batchId] = completion;
      if (inFlight.length > maxObservedInFlight) {
        maxObservedInFlight = inFlight.length;
      }
      emitProgress();
    }

    Future<void> processLine(DecodedLine line) async {
      accumulator.observeLine();
      switch (line) {
        case InvalidLine(:final error):
          accumulator.addInputError(error);
        case ContentLine(:final lineNumber, :final content):
          if (content.trim().isEmpty) {
            accumulator.addBlankLine();
          } else {
            currentBatch.add(
              SourceLine(lineNumber: lineNumber, content: content),
            );
            if (currentBatch.length == options.batchSize) {
              await submitCurrentBatch();
            }
          }
      }
    }

    final framer = Utf8LineFramer(maxLineBytes: options.maxLineBytes);
    iterator = StreamIterator<List<int>>(input);
    iteratorFinished = Completer<void>();
    cancellationWatcher = _cancelIteratorWhenRequested(
      iterator: iterator,
      cancellation: cancellation.token,
      iteratorFinished: iteratorFinished.future,
    );

    while (!cancellation.isCancelled && await iterator.moveNext()) {
      for (final line in framer.addChunk(iterator.current)) {
        await processLine(line);
      }
    }
    final finalLine = framer.finish();
    if (finalLine != null) await processLine(finalLine);

    await submitCurrentBatch();
    while (inFlight.isNotEmpty) {
      await collectOne();
    }
    emitProgress();

    final status = switch (cancellation.reason) {
      null => AnalysisStatus.complete,
      CancellationReason.requested => AnalysisStatus.cancelled,
      CancellationReason.timedOut => AnalysisStatus.timedOut,
    };
    return accumulator.buildReport(
      status: status,
      workerRestarts: dispatcher.workerRestarts,
      maxObservedInFlightBatches: maxObservedInFlight,
    );
  } finally {
    deadline?.cancel();
    if (iteratorFinished != null && !iteratorFinished.isCompleted) {
      iteratorFinished.complete();
    }
    await cancellationWatcher;
    await iterator?.cancel();
    await dispatcher?.close();
    await progress.close();
  }
}

Future<void> _cancelIteratorWhenRequested({
  required StreamIterator<List<int>> iterator,
  required CancellationToken cancellation,
  required Future<void> iteratorFinished,
}) async {
  final shouldCancel = await Future.any<bool>(<Future<bool>>[
    cancellation.whenCancelled.then((CancellationReason _) => true),
    iteratorFinished.then((_) => false),
  ]);
  if (shouldCancel) await iterator.cancel();
}

void _validateOptions(AnalysisOptions options) {
  if (options.workerCount < 1 ||
      options.batchSize < 1 ||
      options.maxInFlightBatches < 1 ||
      options.maxErrors < 0 ||
      options.maxLineBytes < 1 ||
      options.slowestEventLimit < 0) {
    throw ArgumentError('Analysis options contain an invalid limit.');
  }
  final timeout = options.timeout;
  if (timeout != null && timeout <= Duration.zero) {
    throw ArgumentError.value(timeout, 'options.timeout', 'must be positive');
  }
}

typedef _CompletedBatch = ({int batchId, ParsedBatch batch});
