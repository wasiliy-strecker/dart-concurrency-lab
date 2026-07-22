import 'dart:async';

Future<void> main() async {
  final cancellation = Completer<void>();
  var iterations = 0;
  var cleanedUp = false;

  Future<void> operation() async {
    try {
      while (!cancellation.isCompleted) {
        iterations += 1;
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    } finally {
      cleanedUp = true;
    }
  }

  final running = operation();
  await Future<void>.delayed(const Duration(milliseconds: 5));
  cancellation.complete();
  await running;

  if (iterations == 0 || !cleanedUp) {
    throw StateError('Cancellation did not run cleanup.');
  }

  print('LAB_OK cooperative_cancellation iterations=$iterations cleanup=true');
}
