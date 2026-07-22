import 'package:dart_concurrency_lab/dart_concurrency_lab.dart';
import 'package:dart_concurrency_lab/src/pipeline/analysis_accumulator.dart';
import 'package:dart_concurrency_lab/src/pipeline/batch_models.dart';
import 'package:dart_concurrency_lab/src/pipeline/record_parser.dart';
import 'package:test/test.dart';

void main() {
  test('merges each batch ID once and globally bounds retained details', () {
    final accumulator = AnalysisAccumulator(maxErrors: 1, slowestEventLimit: 1)
      ..observeLine()
      ..observeLine()
      ..observeLine();
    final batch = parseRecordBatch(
      batchId: 3,
      lines: const <SourceLine>[
        SourceLine(lineNumber: 1, content: '{"type":"a","duration_ms":10}'),
        SourceLine(lineNumber: 2, content: '{"type":"b","duration_ms":50}'),
        SourceLine(lineNumber: 3, content: '{}'),
      ],
      maxErrors: 3,
      slowestEventLimit: 2,
    );

    expect(accumulator.merge(batch), isTrue);
    expect(accumulator.merge(batch), isFalse);
    final report = accumulator.buildReport(
      status: AnalysisStatus.complete,
      workerRestarts: 0,
      maxObservedInFlightBatches: 1,
    );

    expect(report.validRecords, 2);
    expect(report.invalidRecords, 1);
    expect(report.errors, hasLength(1));
    expect(report.slowestEvents.single.durationMilliseconds, 50);
  });
}
