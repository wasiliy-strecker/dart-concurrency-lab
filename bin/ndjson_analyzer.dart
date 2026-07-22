import 'dart:io';

import 'package:dart_concurrency_lab/src/cli/cli_runner.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runNdjsonAnalyzerCli(
    arguments,
    environment: CliEnvironment(
      standardInput: stdin,
      standardOutput: stdout,
      standardError: stderr,
      processorCount: Platform.numberOfProcessors,
      openInput: (String path) => File(path).openRead(),
      interrupts: ProcessSignal.sigint.watch().map<void>((_) {}),
      forceExit: exit,
    ),
  );
}
