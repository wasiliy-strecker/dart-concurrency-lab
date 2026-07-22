import 'batch_models.dart';
import 'record_parser.dart';

/// Dispatches independently retryable parser batches.
abstract interface class BatchDispatcher {
  /// Number of worker processes restarted during this dispatcher's lifetime.
  int get workerRestarts;

  /// Submits one uniquely identified batch.
  Future<ParsedBatch> submit({
    required int batchId,
    required List<SourceLine> lines,
    required int maxErrors,
    required int slowestEventLimit,
  });

  /// Releases all worker resources.
  Future<void> close();
}

/// Executes parser batches on the calling isolate for comparison and debugging.
final class SequentialBatchDispatcher implements BatchDispatcher {
  /// Creates a sequential dispatcher.
  const SequentialBatchDispatcher();

  @override
  int get workerRestarts => 0;

  @override
  Future<ParsedBatch> submit({
    required int batchId,
    required List<SourceLine> lines,
    required int maxErrors,
    required int slowestEventLimit,
  }) async => parseRecordBatch(
    batchId: batchId,
    lines: lines,
    maxErrors: maxErrors,
    slowestEventLimit: slowestEventLimit,
  );

  @override
  Future<void> close() async {}
}

/// Terminal failure after a worker could not process a batch twice.
final class WorkerBatchException implements Exception {
  /// Creates a worker failure without exposing source records.
  const WorkerBatchException({required this.batchId, required this.message});

  /// Batch that exhausted its retry.
  final int batchId;

  /// Safe failure description.
  final String message;

  @override
  String toString() => 'WorkerBatchException(batch=$batchId, $message)';
}
