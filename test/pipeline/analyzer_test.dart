import 'dart:async';
import 'dart:convert';

import 'package:dart_concurrency_lab/dart_concurrency_lab.dart';
import 'package:test/test.dart';

void main() {
  const input = '''
{"type":"request","timestamp":"2026-07-22T10:00:00Z","duration_ms":15}

{"type":"sync","timestamp":"2026-07-22T09:00:00+02:00","duration_ms":80}
{"type":"request","duration_ms":5}
{broken
{"type":"sync","duration_ms":-1}
''';

  test('sequential and isolate engines produce the same report', () async {
    const baseOptions = AnalysisOptions(
      workerCount: 2,
      batchSize: 2,
      maxErrors: 10,
      slowestEventLimit: 2,
    );
    final analyzer = const NdjsonAnalyzer();

    final sequential = await analyzer
        .start(
          _chunkedUtf8(input, 7),
          options: baseOptions.copyWith(sequential: true),
        )
        .done;
    final isolated = await analyzer
        .start(_chunkedUtf8(input, 5), options: baseOptions)
        .done;

    expect(isolated.toJson(), sequential.toJson());
    expect(isolated.status, AnalysisStatus.complete);
    expect(isolated.linesRead, 6);
    expect(isolated.blankLines, 1);
    expect(isolated.validRecords, 3);
    expect(isolated.invalidRecords, 2);
    expect(isolated.recordsByType, <String, int>{'request': 2, 'sync': 1});
    expect(isolated.firstTimestamp, DateTime.utc(2026, 7, 22, 7));
    expect(isolated.lastTimestamp, DateTime.utc(2026, 7, 22, 10));
    expect(isolated.durationStatistics.totalMilliseconds, 100);
    expect(isolated.slowestEvents.first.durationMilliseconds, 80);
    expect(isolated.errors, hasLength(2));
  });

  test('never exceeds configured submitted-batch pressure', () async {
    final lines = List<String>.generate(
      30,
      (int index) => '{"type":"event","duration_ms":$index}',
    ).join('\n');
    const options = AnalysisOptions(
      workerCount: 2,
      batchSize: 1,
      maxInFlightBatches: 3,
    );
    final run = const NdjsonAnalyzer().start(
      _chunkedUtf8(lines, 11),
      options: options,
    );
    final progressFuture = run.progress.toList();

    final report = await run.done;
    final progress = await progressFuture;

    expect(report.validRecords, 30);
    expect(report.maxObservedInFlightBatches, 3);
    expect(
      progress.map((AnalysisProgress value) => value.inFlightBatches),
      everyElement(lessThanOrEqualTo(3)),
    );
  });

  test(
    'cancellation stops source demand and returns a partial report',
    () async {
      final startProducing = Completer<void>();
      var sourceClosed = false;

      Stream<List<int>> slowInput() async* {
        try {
          await startProducing.future;
          for (var index = 0; index < 100; index += 1) {
            yield utf8.encode('{"type":"event","duration_ms":$index}\n');
            await Future<void>.delayed(const Duration(milliseconds: 2));
          }
        } finally {
          sourceClosed = true;
        }
      }

      final run = const NdjsonAnalyzer().start(
        slowInput(),
        options: const AnalysisOptions(batchSize: 1, maxInFlightBatches: 1),
      );
      final firstProgress = run.progress.first;
      startProducing.complete();
      await firstProgress;
      expect(run.cancel(), isTrue);

      final report = await run.done;

      expect(report.status, AnalysisStatus.cancelled);
      expect(report.linesRead, lessThan(100));
      expect(sourceClosed, isTrue);
      expect(run.cancel(), isFalse);
    },
  );

  test('timeout cancels a stalled input subscription', () async {
    var sourceCancelled = false;
    final inputController = StreamController<List<int>>(
      onCancel: () => sourceCancelled = true,
    );
    addTearDown(inputController.close);

    final report = await const NdjsonAnalyzer()
        .start(
          inputController.stream,
          options: const AnalysisOptions(
            sequential: true,
            timeout: Duration(milliseconds: 10),
          ),
        )
        .done;

    expect(report.status, AnalysisStatus.timedOut);
    expect(report.linesRead, 0);
    expect(sourceCancelled, isTrue);
  });

  test('validates non-constant option invariants at the public boundary', () {
    expect(
      () => const NdjsonAnalyzer().start(
        const Stream<List<int>>.empty(),
        options: const AnalysisOptions(timeout: Duration.zero),
      ),
      throwsArgumentError,
    );
  });
}

Stream<List<int>> _chunkedUtf8(String value, int chunkSize) async* {
  final bytes = utf8.encode(value);
  for (var offset = 0; offset < bytes.length; offset += chunkSize) {
    final end = (offset + chunkSize).clamp(0, bytes.length);
    yield bytes.sublist(offset, end);
  }
}
