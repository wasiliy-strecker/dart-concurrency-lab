import 'dart:io';

import 'package:test/test.dart';

void main() {
  const labs = <String>[
    'example/event_loop.dart',
    'example/bounded_futures.dart',
    'example/stream_backpressure.dart',
    'example/isolate_transfer.dart',
    'example/cooperative_cancellation.dart',
    'example/zoned_failures.dart',
  ];

  for (final lab in labs) {
    test(
      '$lab is executable and verifies its contract',
      () async {
        final result = await Process.run(Platform.resolvedExecutable, <String>[
          'run',
          lab,
        ], workingDirectory: Directory.current.path);

        expect(
          result.exitCode,
          0,
          reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
        );
        expect(result.stdout as String, contains('LAB_OK'));
        expect(result.stderr as String, isEmpty);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );
  }
}
