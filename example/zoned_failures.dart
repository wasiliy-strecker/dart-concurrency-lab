import 'dart:async';

Future<void> main() async {
  final captured = Completer<Object>();

  runZonedGuarded(
    () {
      unawaited(
        Future<void>.microtask(
          () => throw StateError('unawaited failure from the lab'),
        ),
      );
    },
    (Object error, StackTrace stackTrace) {
      if (!captured.isCompleted) captured.complete(error);
    },
  );

  final error = await captured.future.timeout(const Duration(seconds: 1));
  if (error is! StateError) {
    throw StateError('Expected StateError, got ${error.runtimeType}');
  }

  print('LAB_OK zoned_failures captured=${error.runtimeType}');
}
