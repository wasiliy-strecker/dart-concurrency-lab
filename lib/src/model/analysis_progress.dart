/// A bounded, best-effort progress snapshot from an active analysis.
final class AnalysisProgress {
  /// Creates a progress snapshot.
  const AnalysisProgress({
    required this.linesRead,
    required this.validRecords,
    required this.invalidRecords,
    required this.inFlightBatches,
    required this.maxObservedInFlightBatches,
  });

  /// Physical lines consumed from the input.
  final int linesRead;

  /// Valid records aggregated so far.
  final int validRecords;

  /// Invalid records aggregated so far.
  final int invalidRecords;

  /// Batches currently assigned to workers.
  final int inFlightBatches;

  /// Highest observed number of in-flight batches.
  final int maxObservedInFlightBatches;
}
