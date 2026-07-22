import 'package:dart_concurrency_lab/src/model/invalid_record.dart';
import 'package:dart_concurrency_lab/src/pipeline/batch_models.dart';
import 'package:dart_concurrency_lab/src/pipeline/record_parser.dart';
import 'package:test/test.dart';

void main() {
  test('parses a batch into mergeable, bounded aggregates', () {
    final batch = parseRecordBatch(
      batchId: 7,
      lines: const <SourceLine>[
        SourceLine(
          lineNumber: 1,
          content:
              '{"type":" request ","timestamp":"2026-07-22T10:00:00+02:00","duration_ms":12}',
        ),
        SourceLine(
          lineNumber: 2,
          content:
              '{"type":"request","timestamp":"2026-07-22T09:00:00Z","duration_ms":30}',
        ),
        SourceLine(lineNumber: 3, content: '{"type":""}'),
        SourceLine(lineNumber: 4, content: '[]'),
        SourceLine(lineNumber: 5, content: '{broken'),
      ],
      maxErrors: 2,
      slowestEventLimit: 1,
    );

    expect(batch.batchId, 7);
    expect(batch.validRecords, 2);
    expect(batch.invalidRecords, 3);
    expect(batch.recordsByType, <String, int>{'request': 2});
    expect(
      DateTime.fromMicrosecondsSinceEpoch(
        batch.firstTimestampMicros!,
        isUtc: true,
      ),
      DateTime.utc(2026, 7, 22, 8),
    );
    expect(batch.durationCount, 2);
    expect(batch.totalDurationMilliseconds, 42);
    expect(batch.minimumDurationMilliseconds, 12);
    expect(batch.maximumDurationMilliseconds, 30);
    expect(batch.slowestEvents.single.lineNumber, 2);
    expect(batch.errors, hasLength(2));
    expect(batch.errors.first.code, RecordErrorCode.missingType);
  });

  test('rejects invalid optional fields instead of inventing values', () {
    final batch = parseRecordBatch(
      batchId: 1,
      lines: const <SourceLine>[
        SourceLine(lineNumber: 1, content: '{"type":"x","timestamp":null}'),
        SourceLine(lineNumber: 2, content: '{"type":"x","duration_ms":1.5}'),
        SourceLine(lineNumber: 3, content: '{"type":"x","duration_ms":-1}'),
      ],
      maxErrors: 10,
      slowestEventLimit: 10,
    );

    expect(batch.validRecords, 0);
    expect(
      batch.errors.map((InvalidRecord error) => error.code),
      <RecordErrorCode>[
        RecordErrorCode.invalidTimestamp,
        RecordErrorCode.invalidDuration,
        RecordErrorCode.invalidDuration,
      ],
    );
  });
}
