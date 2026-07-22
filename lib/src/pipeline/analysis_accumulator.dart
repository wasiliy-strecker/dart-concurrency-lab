import '../model/analysis_report.dart';
import '../model/invalid_record.dart';
import 'batch_models.dart';

/// Idempotent, memory-bounded merger for decoded lines and parsed batches.
final class AnalysisAccumulator {
  /// Creates an empty accumulator with output limits.
  AnalysisAccumulator({
    required this.maxErrors,
    required this.slowestEventLimit,
  });

  /// Detailed errors retained in the final report.
  final int maxErrors;

  /// Slow events retained in the final report.
  final int slowestEventLimit;

  var _linesRead = 0;
  var _blankLines = 0;
  var _validRecords = 0;
  var _invalidRecords = 0;
  final _recordsByType = <String, int>{};
  int? _firstTimestampMicros;
  int? _lastTimestampMicros;
  var _durationCount = 0;
  int? _minimumDuration;
  int? _maximumDuration;
  var _totalDuration = 0;
  final _slowestEvents = <ParsedSlowEvent>[];
  final _errors = <InvalidRecord>[];
  final _completedBatchIds = <int>{};

  /// Physical lines observed so far.
  int get linesRead => _linesRead;

  /// Valid records merged so far.
  int get validRecords => _validRecords;

  /// Invalid records merged so far.
  int get invalidRecords => _invalidRecords;

  /// Records one physical source line.
  void observeLine() {
    _linesRead += 1;
  }

  /// Records one ignored blank line.
  void addBlankLine() {
    _blankLines += 1;
  }

  /// Records a framing or UTF-8 failure.
  void addInputError(InvalidRecord error) {
    _invalidRecords += 1;
    _retainError(error);
  }

  /// Merges a batch once and returns `false` for a duplicate batch ID.
  bool merge(ParsedBatch batch) {
    if (!_completedBatchIds.add(batch.batchId)) return false;

    _validRecords += batch.validRecords;
    _invalidRecords += batch.invalidRecords;
    for (final MapEntry<String, int>(:key, :value)
        in batch.recordsByType.entries) {
      _recordsByType.update(
        key,
        (int count) => count + value,
        ifAbsent: () => value,
      );
    }
    final firstMicros = batch.firstTimestampMicros;
    if (firstMicros != null &&
        (_firstTimestampMicros == null ||
            firstMicros < _firstTimestampMicros!)) {
      _firstTimestampMicros = firstMicros;
    }
    final lastMicros = batch.lastTimestampMicros;
    if (lastMicros != null &&
        (_lastTimestampMicros == null || lastMicros > _lastTimestampMicros!)) {
      _lastTimestampMicros = lastMicros;
    }
    _durationCount += batch.durationCount;
    _totalDuration += batch.totalDurationMilliseconds;
    final batchMinimum = batch.minimumDurationMilliseconds;
    if (batchMinimum != null &&
        (_minimumDuration == null || batchMinimum < _minimumDuration!)) {
      _minimumDuration = batchMinimum;
    }
    final batchMaximum = batch.maximumDurationMilliseconds;
    if (batchMaximum != null &&
        (_maximumDuration == null || batchMaximum > _maximumDuration!)) {
      _maximumDuration = batchMaximum;
    }
    _slowestEvents.addAll(batch.slowestEvents);
    _slowestEvents.sort(_compareSlowEvents);
    if (_slowestEvents.length > slowestEventLimit) {
      _slowestEvents.removeRange(slowestEventLimit, _slowestEvents.length);
    }
    for (final error in batch.errors) {
      _retainError(error);
    }
    return true;
  }

  /// Builds an immutable report with runtime evidence attached.
  AnalysisReport buildReport({
    required AnalysisStatus status,
    required int workerRestarts,
    required int maxObservedInFlightBatches,
  }) {
    _errors.sort(
      (InvalidRecord left, InvalidRecord right) =>
          left.lineNumber.compareTo(right.lineNumber),
    );
    final slowEvents = _slowestEvents
        .map(
          (ParsedSlowEvent event) => SlowEvent(
            lineNumber: event.lineNumber,
            type: event.type,
            durationMilliseconds: event.durationMilliseconds,
          ),
        )
        .toList(growable: false);
    return AnalysisReport(
      status: status,
      linesRead: _linesRead,
      blankLines: _blankLines,
      validRecords: _validRecords,
      invalidRecords: _invalidRecords,
      recordsByType: _recordsByType,
      firstTimestamp: _firstTimestampMicros == null
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(
              _firstTimestampMicros!,
              isUtc: true,
            ),
      lastTimestamp: _lastTimestampMicros == null
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(
              _lastTimestampMicros!,
              isUtc: true,
            ),
      durationStatistics: DurationStatistics(
        count: _durationCount,
        minimumMilliseconds: _minimumDuration,
        maximumMilliseconds: _maximumDuration,
        totalMilliseconds: _totalDuration,
      ),
      slowestEvents: slowEvents,
      errors: _errors,
      suppressedErrors: (_invalidRecords - _errors.length).clamp(
        0,
        _invalidRecords,
      ),
      workerRestarts: workerRestarts,
      maxObservedInFlightBatches: maxObservedInFlightBatches,
    );
  }

  void _retainError(InvalidRecord error) {
    if (_errors.length < maxErrors) _errors.add(error);
  }
}

int _compareSlowEvents(ParsedSlowEvent left, ParsedSlowEvent right) {
  final durationOrder = right.durationMilliseconds.compareTo(
    left.durationMilliseconds,
  );
  return durationOrder != 0
      ? durationOrder
      : left.lineNumber.compareTo(right.lineNumber);
}
