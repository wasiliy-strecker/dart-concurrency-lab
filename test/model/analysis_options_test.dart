import 'package:dart_concurrency_lab/dart_concurrency_lab.dart';
import 'package:test/test.dart';

void main() {
  group('AnalysisOptions', () {
    test('sizes worker defaults from the processor count', () {
      expect(AnalysisOptions.forProcessors(1).workerCount, 1);
      expect(AnalysisOptions.forProcessors(2).workerCount, 1);
      expect(AnalysisOptions.forProcessors(4).workerCount, 3);
      expect(AnalysisOptions.forProcessors(64).workerCount, 4);
      expect(AnalysisOptions.forProcessors(64).maxInFlightBatches, 8);
    });

    test('rejects an impossible processor count', () {
      expect(() => AnalysisOptions.forProcessors(0), throwsArgumentError);
    });

    test('copyWith preserves or clears a timeout explicitly', () {
      const original = AnalysisOptions(timeout: Duration(seconds: 2));

      expect(original.copyWith(workerCount: 2).timeout, original.timeout);
      expect(original.copyWith(clearTimeout: true).timeout, isNull);
    });
  });
}
