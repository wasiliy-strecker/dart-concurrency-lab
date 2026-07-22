import '../model/invalid_record.dart';

/// One decoded, non-blank line submitted for JSON parsing.
final class SourceLine {
  /// Creates source text with its physical location.
  const SourceLine({required this.lineNumber, required this.content});

  /// One-based physical line number.
  final int lineNumber;

  /// UTF-8 decoded JSON text.
  final String content;
}

/// One valid event retained for the bounded slow-event ranking.
final class ParsedSlowEvent {
  /// Creates a parsed slow-event candidate.
  const ParsedSlowEvent({
    required this.lineNumber,
    required this.type,
    required this.durationMilliseconds,
  });

  /// One-based physical line number.
  final int lineNumber;

  /// Normalized event type.
  final String type;

  /// Non-negative reported duration.
  final int durationMilliseconds;
}

/// Mergeable result produced for one unique batch.
final class ParsedBatch {
  /// Creates a complete parsed batch.
  const ParsedBatch({
    required this.batchId,
    required this.validRecords,
    required this.invalidRecords,
    required this.recordsByType,
    required this.firstTimestampMicros,
    required this.lastTimestampMicros,
    required this.durationCount,
    required this.minimumDurationMilliseconds,
    required this.maximumDurationMilliseconds,
    required this.totalDurationMilliseconds,
    required this.slowestEvents,
    required this.errors,
  });

  /// Unique coordinator-assigned identifier.
  final int batchId;

  /// Successfully parsed records.
  final int validRecords;

  /// Rejected JSON or schema records.
  final int invalidRecords;

  /// Counts by normalized event type.
  final Map<String, int> recordsByType;

  /// Earliest UTC microsecond timestamp.
  final int? firstTimestampMicros;

  /// Latest UTC microsecond timestamp.
  final int? lastTimestampMicros;

  /// Records with a valid duration.
  final int durationCount;

  /// Minimum valid duration.
  final int? minimumDurationMilliseconds;

  /// Maximum valid duration.
  final int? maximumDurationMilliseconds;

  /// Sum of valid durations.
  final int totalDurationMilliseconds;

  /// Batch-local bounded slow-event ranking.
  final List<ParsedSlowEvent> slowestEvents;

  /// Batch-local bounded validation details.
  final List<InvalidRecord> errors;
}
