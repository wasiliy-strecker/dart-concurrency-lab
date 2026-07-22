import 'package:dart_concurrency_lab/dart_concurrency_lab.dart';
import 'package:test/test.dart';

void main() {
  test('AnalysisReport sorts type keys and keeps JSON deterministic', () {
    final report = AnalysisReport(
      status: AnalysisStatus.complete,
      linesRead: 3,
      blankLines: 0,
      validRecords: 2,
      invalidRecords: 1,
      recordsByType: <String, int>{'zeta': 1, 'alpha': 1},
      firstTimestamp: DateTime.utc(2026, 7, 22, 10),
      lastTimestamp: DateTime.utc(2026, 7, 22, 11),
      durationStatistics: const DurationStatistics(
        count: 2,
        minimumMilliseconds: 10,
        maximumMilliseconds: 30,
        totalMilliseconds: 40,
      ),
      slowestEvents: const <SlowEvent>[
        SlowEvent(lineNumber: 2, type: 'zeta', durationMilliseconds: 30),
      ],
      errors: const <InvalidRecord>[
        InvalidRecord(
          lineNumber: 3,
          code: RecordErrorCode.invalidJson,
          message: 'Invalid JSON.',
        ),
      ],
      suppressedErrors: 0,
      workerRestarts: 0,
      maxObservedInFlightBatches: 2,
    );

    expect(report.recordsByType.keys, <String>['alpha', 'zeta']);
    expect(report.durationStatistics.meanMilliseconds, 20);
    expect(report.toJson()['status'], 'complete');
    expect(report.toJson()['records_by_type'], <String, int>{
      'alpha': 1,
      'zeta': 1,
    });
    expect(
      (report.toJson()['errors']! as List<Object?>).single,
      <String, Object>{
        'line': 3,
        'code': 'invalid_json',
        'message': 'Invalid JSON.',
      },
    );
  });
}
