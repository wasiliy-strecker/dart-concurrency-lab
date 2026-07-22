import 'dart:collection';

import 'invalid_record.dart';

/// Final state of an analysis run.
enum AnalysisStatus {
  /// The complete input was processed.
  complete,

  /// The caller requested cancellation.
  cancelled,

  /// The configured deadline elapsed.
  timedOut,
}

/// Streaming duration aggregates that do not retain every record.
final class DurationStatistics {
  /// Creates duration aggregates.
  const DurationStatistics({
    required this.count,
    required this.minimumMilliseconds,
    required this.maximumMilliseconds,
    required this.totalMilliseconds,
  });

  /// Empty duration aggregates.
  const DurationStatistics.empty()
    : count = 0,
      minimumMilliseconds = null,
      maximumMilliseconds = null,
      totalMilliseconds = 0;

  /// Number of records that contained a duration.
  final int count;

  /// Smallest observed duration.
  final int? minimumMilliseconds;

  /// Largest observed duration.
  final int? maximumMilliseconds;

  /// Sum used to calculate an exact arithmetic mean.
  final int totalMilliseconds;

  /// Arithmetic mean, or `null` when no duration was present.
  double? get meanMilliseconds => count == 0 ? null : totalMilliseconds / count;

  /// Converts the aggregates to deterministic JSON data.
  Map<String, Object?> toJson() => <String, Object?>{
    'count': count,
    'minimum_ms': minimumMilliseconds,
    'maximum_ms': maximumMilliseconds,
    'mean_ms': meanMilliseconds,
  };
}

/// A retained slow event without its potentially sensitive payload.
final class SlowEvent {
  /// Creates a slow-event summary.
  const SlowEvent({
    required this.lineNumber,
    required this.type,
    required this.durationMilliseconds,
  });

  /// One-based physical line number.
  final int lineNumber;

  /// Event type from the input.
  final String type;

  /// Reported duration.
  final int durationMilliseconds;

  /// Converts the event to deterministic JSON data.
  Map<String, Object> toJson() => <String, Object>{
    'line': lineNumber,
    'type': type,
    'duration_ms': durationMilliseconds,
  };
}

/// Deterministic aggregate for a complete or partial NDJSON analysis.
final class AnalysisReport {
  /// Creates an immutable report.
  AnalysisReport({
    required this.status,
    required this.linesRead,
    required this.blankLines,
    required this.validRecords,
    required this.invalidRecords,
    required Map<String, int> recordsByType,
    required this.firstTimestamp,
    required this.lastTimestamp,
    required this.durationStatistics,
    required List<SlowEvent> slowestEvents,
    required List<InvalidRecord> errors,
    required this.suppressedErrors,
    required this.workerRestarts,
    required this.maxObservedInFlightBatches,
  }) : recordsByType = UnmodifiableMapView<String, int>(
         SplayTreeMap<String, int>.of(recordsByType),
       ),
       slowestEvents = List<SlowEvent>.unmodifiable(slowestEvents),
       errors = List<InvalidRecord>.unmodifiable(errors);

  /// Completion state.
  final AnalysisStatus status;

  /// Physical lines read, including blank and invalid lines.
  final int linesRead;

  /// Empty or whitespace-only lines ignored by the parser.
  final int blankLines;

  /// Successfully validated event records.
  final int validRecords;

  /// Records rejected by decoding, JSON, or schema validation.
  final int invalidRecords;

  /// Valid record counts keyed by event type and sorted by key.
  final Map<String, int> recordsByType;

  /// Earliest normalized timestamp, when any was present.
  final DateTime? firstTimestamp;

  /// Latest normalized timestamp, when any was present.
  final DateTime? lastTimestamp;

  /// Memory-bounded duration aggregates.
  final DurationStatistics durationStatistics;

  /// Slowest events, descending by duration then ascending by line.
  final List<SlowEvent> slowestEvents;

  /// Retained errors, sorted by physical line number.
  final List<InvalidRecord> errors;

  /// Invalid record count omitted after the configured error limit.
  final int suppressedErrors;

  /// Workers restarted after unexpected exits.
  final int workerRestarts;

  /// Evidence that the configured backpressure limit was respected.
  final int maxObservedInFlightBatches;

  /// Whether the entire source was consumed.
  bool get isComplete => status == AnalysisStatus.complete;

  /// Converts this report to insertion-ordered, deterministic JSON data.
  Map<String, Object?> toJson() => <String, Object?>{
    'status': switch (status) {
      AnalysisStatus.complete => 'complete',
      AnalysisStatus.cancelled => 'cancelled',
      AnalysisStatus.timedOut => 'timed_out',
    },
    'lines_read': linesRead,
    'blank_lines': blankLines,
    'valid_records': validRecords,
    'invalid_records': invalidRecords,
    'records_by_type': recordsByType,
    'first_timestamp': firstTimestamp?.toIso8601String(),
    'last_timestamp': lastTimestamp?.toIso8601String(),
    'durations': durationStatistics.toJson(),
    'slowest_events': slowestEvents
        .map((SlowEvent event) => event.toJson())
        .toList(growable: false),
    'errors': errors
        .map((InvalidRecord error) => error.toJson())
        .toList(growable: false),
    'suppressed_errors': suppressedErrors,
    'worker_restarts': workerRestarts,
    'max_observed_in_flight_batches': maxObservedInFlightBatches,
  };
}
