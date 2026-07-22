import 'package:dart_concurrency_lab/src/pipeline/batch_models.dart';
import 'package:dart_concurrency_lab/src/pipeline/isolate_batch_dispatcher.dart';
import 'package:test/test.dart';

void main() {
  test('restarts a terminated worker and retries its batch once', () async {
    final dispatcher = await IsolateBatchDispatcher.start(
      workerCount: 1,
      workerDelayForTesting: const Duration(milliseconds: 80),
    );
    addTearDown(dispatcher.close);

    final resultFuture = dispatcher.submit(
      batchId: 42,
      lines: const <SourceLine>[
        SourceLine(
          lineNumber: 1,
          content: '{"type":"recovered","duration_ms":7}',
        ),
      ],
      maxErrors: 10,
      slowestEventLimit: 10,
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await dispatcher.terminateWorkerForTesting();

    final result = await resultFuture;

    expect(result.batchId, 42);
    expect(result.validRecords, 1);
    expect(result.recordsByType, <String, int>{'recovered': 1});
    expect(dispatcher.workerRestarts, 1);
  });
}
