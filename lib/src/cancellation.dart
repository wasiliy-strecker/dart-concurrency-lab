import 'dart:async';

/// Why an analysis stopped before consuming its complete input.
enum CancellationReason {
  /// A caller explicitly requested cancellation.
  requested,

  /// The configured analysis deadline elapsed.
  timedOut,
}

/// Read-only cooperative cancellation state.
final class CancellationToken {
  CancellationToken._(this._source);

  final CancellationSource _source;

  /// Whether cancellation has been requested.
  bool get isCancelled => _source.isCancelled;

  /// The first cancellation reason.
  CancellationReason? get reason => _source.reason;

  /// Completes once with the first cancellation reason.
  Future<CancellationReason> get whenCancelled => _source.whenCancelled;

  /// Throws when cancellation has already been requested.
  void throwIfCancelled() {
    final currentReason = reason;
    if (currentReason != null) {
      throw AnalysisCancelledException(currentReason);
    }
  }
}

/// Mutable owner of a [CancellationToken].
final class CancellationSource {
  /// Creates an active cancellation source.
  CancellationSource() {
    token = CancellationToken._(this);
  }

  final Completer<CancellationReason> _completer =
      Completer<CancellationReason>();

  /// Read-only token shared with operations.
  late final CancellationToken token;

  /// Whether cancellation has been requested.
  bool get isCancelled => _completer.isCompleted;

  /// The first reason, or `null` while active.
  CancellationReason? get reason => _reason;
  CancellationReason? _reason;

  /// Completes once with the first reason.
  Future<CancellationReason> get whenCancelled => _completer.future;

  /// Requests cancellation and returns whether this call won the race.
  bool cancel([CancellationReason reason = CancellationReason.requested]) {
    if (_completer.isCompleted) return false;
    _reason = reason;
    _completer.complete(reason);
    return true;
  }
}

/// Exception used by explicitly cooperative operations.
final class AnalysisCancelledException implements Exception {
  /// Creates a cancellation exception.
  const AnalysisCancelledException(this.reason);

  /// Why cancellation was requested.
  final CancellationReason reason;

  @override
  String toString() => 'AnalysisCancelledException(${reason.name})';
}
