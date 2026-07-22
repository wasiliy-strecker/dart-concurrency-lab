import 'dart:async';

Future<void> main() async {
  var produced = 0;
  var consumed = 0;
  var largestLead = 0;

  Stream<int> source() async* {
    for (var value = 0; value < 20; value += 1) {
      produced += 1;
      yield value;
    }
  }

  await for (final value in source()) {
    largestLead = produced - consumed > largestLead
        ? produced - consumed
        : largestLead;
    await Future<void>.delayed(const Duration(milliseconds: 1));
    consumed += 1;
    if (value != consumed - 1) {
      throw StateError('The single-subscription stream changed order.');
    }
  }

  if (produced != 20 || consumed != 20 || largestLead != 1) {
    throw StateError(
      'Expected demand-driven production; produced=$produced '
      'consumed=$consumed lead=$largestLead',
    );
  }

  print('LAB_OK stream_backpressure max_producer_lead=$largestLead');
}
