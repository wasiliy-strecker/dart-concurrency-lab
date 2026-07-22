/// Immutable limits for one NDJSON analysis run.
final class AnalysisOptions {
  /// Creates validated analysis limits.
  const AnalysisOptions({
    this.workerCount = 1,
    this.batchSize = 256,
    this.maxInFlightBatches = 2,
    this.maxErrors = 20,
    this.maxLineBytes = 1024 * 1024,
    this.slowestEventLimit = 10,
    this.strict = false,
    this.sequential = false,
    this.timeout,
  }) : assert(workerCount > 0, 'workerCount must be positive'),
       assert(batchSize > 0, 'batchSize must be positive'),
       assert(maxInFlightBatches > 0, 'maxInFlightBatches must be positive'),
       assert(maxErrors >= 0, 'maxErrors must not be negative'),
       assert(maxLineBytes > 0, 'maxLineBytes must be positive'),
       assert(slowestEventLimit >= 0, 'slowestEventLimit must not be negative');

  /// Creates defaults sized for [availableProcessors].
  factory AnalysisOptions.forProcessors(int availableProcessors) {
    if (availableProcessors < 1) {
      throw ArgumentError.value(
        availableProcessors,
        'availableProcessors',
        'must be positive',
      );
    }
    final workerCount = (availableProcessors - 1).clamp(1, 4);
    return AnalysisOptions(
      workerCount: workerCount,
      maxInFlightBatches: workerCount * 2,
    );
  }

  /// Number of long-lived parser isolates.
  final int workerCount;

  /// Maximum number of source lines sent in one worker message.
  final int batchSize;

  /// Maximum batches submitted without a corresponding result.
  final int maxInFlightBatches;

  /// Maximum detailed validation errors retained in the final report.
  final int maxErrors;

  /// Maximum UTF-8 bytes accepted for one logical line.
  final int maxLineBytes;

  /// Maximum slow events retained in the final report.
  final int slowestEventLimit;

  /// Whether invalid records make the CLI return a failing exit code.
  final bool strict;

  /// Whether work stays on the calling isolate.
  final bool sequential;

  /// Optional deadline for the complete run.
  final Duration? timeout;

  /// Returns a copy with selected values replaced.
  AnalysisOptions copyWith({
    int? workerCount,
    int? batchSize,
    int? maxInFlightBatches,
    int? maxErrors,
    int? maxLineBytes,
    int? slowestEventLimit,
    bool? strict,
    bool? sequential,
    Duration? timeout,
    bool clearTimeout = false,
  }) => AnalysisOptions(
    workerCount: workerCount ?? this.workerCount,
    batchSize: batchSize ?? this.batchSize,
    maxInFlightBatches: maxInFlightBatches ?? this.maxInFlightBatches,
    maxErrors: maxErrors ?? this.maxErrors,
    maxLineBytes: maxLineBytes ?? this.maxLineBytes,
    slowestEventLimit: slowestEventLimit ?? this.slowestEventLimit,
    strict: strict ?? this.strict,
    sequential: sequential ?? this.sequential,
    timeout: clearTimeout ? null : timeout ?? this.timeout,
  );
}
