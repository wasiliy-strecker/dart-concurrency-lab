import 'dart:convert';

import '../model/invalid_record.dart';
import 'batch_models.dart';

/// Parses and aggregates one independently retryable batch.
ParsedBatch parseRecordBatch({
  required int batchId,
  required List<SourceLine> lines,
  required int maxErrors,
  required int slowestEventLimit,
}) {
  var validRecords = 0;
  var invalidRecords = 0;
  final recordsByType = <String, int>{};
  int? firstTimestampMicros;
  int? lastTimestampMicros;
  var durationCount = 0;
  int? minimumDuration;
  int? maximumDuration;
  var totalDuration = 0;
  final slowestEvents = <ParsedSlowEvent>[];
  final errors = <InvalidRecord>[];

  void reject(SourceLine line, RecordErrorCode code, String message) {
    invalidRecords += 1;
    if (errors.length < maxErrors) {
      errors.add(
        InvalidRecord(
          lineNumber: line.lineNumber,
          code: code,
          message: message,
        ),
      );
    }
  }

  for (final line in lines) {
    Object? decoded;
    try {
      decoded = jsonDecode(line.content) as Object?;
    } on FormatException {
      reject(line, RecordErrorCode.invalidJson, 'Line is not valid JSON.');
      continue;
    }
    if (decoded is! Map<String, dynamic>) {
      reject(line, RecordErrorCode.notObject, 'JSON value must be an object.');
      continue;
    }

    final rawType = decoded['type'];
    if (rawType is! String || rawType.trim().isEmpty) {
      reject(
        line,
        RecordErrorCode.missingType,
        'Property "type" must be a non-empty string.',
      );
      continue;
    }
    final type = rawType.trim();

    DateTime? timestamp;
    if (decoded.containsKey('timestamp')) {
      final rawTimestamp = decoded['timestamp'];
      if (rawTimestamp is! String ||
          (timestamp = DateTime.tryParse(rawTimestamp)) == null) {
        reject(
          line,
          RecordErrorCode.invalidTimestamp,
          'Property "timestamp" must be an ISO-8601 string.',
        );
        continue;
      }
      timestamp = timestamp!.toUtc();
    }

    int? duration;
    if (decoded.containsKey('duration_ms')) {
      final rawDuration = decoded['duration_ms'];
      if (rawDuration is! int || rawDuration < 0) {
        reject(
          line,
          RecordErrorCode.invalidDuration,
          'Property "duration_ms" must be a non-negative integer.',
        );
        continue;
      }
      duration = rawDuration;
    }

    validRecords += 1;
    recordsByType.update(type, (int count) => count + 1, ifAbsent: () => 1);

    if (timestamp != null) {
      final micros = timestamp.microsecondsSinceEpoch;
      if (firstTimestampMicros == null || micros < firstTimestampMicros) {
        firstTimestampMicros = micros;
      }
      if (lastTimestampMicros == null || micros > lastTimestampMicros) {
        lastTimestampMicros = micros;
      }
    }

    if (duration != null) {
      durationCount += 1;
      totalDuration += duration;
      if (minimumDuration == null || duration < minimumDuration) {
        minimumDuration = duration;
      }
      if (maximumDuration == null || duration > maximumDuration) {
        maximumDuration = duration;
      }
      if (slowestEventLimit > 0) {
        slowestEvents.add(
          ParsedSlowEvent(
            lineNumber: line.lineNumber,
            type: type,
            durationMilliseconds: duration,
          ),
        );
        _sortSlowest(slowestEvents);
        if (slowestEvents.length > slowestEventLimit) {
          slowestEvents.removeLast();
        }
      }
    }
  }

  return ParsedBatch(
    batchId: batchId,
    validRecords: validRecords,
    invalidRecords: invalidRecords,
    recordsByType: recordsByType,
    firstTimestampMicros: firstTimestampMicros,
    lastTimestampMicros: lastTimestampMicros,
    durationCount: durationCount,
    minimumDurationMilliseconds: minimumDuration,
    maximumDurationMilliseconds: maximumDuration,
    totalDurationMilliseconds: totalDuration,
    slowestEvents: slowestEvents,
    errors: errors,
  );
}

void _sortSlowest(List<ParsedSlowEvent> events) {
  events.sort((ParsedSlowEvent left, ParsedSlowEvent right) {
    final durationOrder = right.durationMilliseconds.compareTo(
      left.durationMilliseconds,
    );
    return durationOrder != 0
        ? durationOrder
        : left.lineNumber.compareTo(right.lineNumber);
  });
}
