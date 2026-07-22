import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import '../analyzer.dart';
import '../model/analysis_options.dart';
import '../model/analysis_progress.dart';
import '../model/analysis_report.dart';
import '../pipeline/batch_dispatcher.dart';

/// Opens one path as a byte stream.
typedef CliInputOpener = Stream<List<int>> Function(String path);

/// Process and I/O boundary for the testable command runner.
final class CliEnvironment {
  /// Creates an explicit CLI environment.
  const CliEnvironment({
    required this.standardInput,
    required this.standardOutput,
    required this.standardError,
    required this.processorCount,
    required this.openInput,
    this.interrupts = const Stream<void>.empty(),
    this.forceExit,
  });

  /// Bytes used when the input path is `-`.
  final Stream<List<int>> standardInput;

  /// Report destination.
  final StringSink standardOutput;

  /// Progress and diagnostic destination.
  final StringSink standardError;

  /// Available processors used to size default worker counts.
  final int processorCount;

  /// File-system boundary for named input paths.
  final CliInputOpener openInput;

  /// Interrupt notifications, normally SIGINT.
  final Stream<void> interrupts;

  /// Immediate process termination hook used after a second interrupt.
  final void Function(int exitCode)? forceExit;
}

/// Runs the `ndjson_analyzer` command and returns a documented exit code.
Future<int> runNdjsonAnalyzerCli(
  List<String> arguments, {
  required CliEnvironment environment,
}) async {
  final parsers = _createParsers();
  ArgResults root;
  try {
    root = parsers.root.parse(arguments);
  } on FormatException catch (error) {
    environment.standardError.writeln('Argument error: ${error.message}');
    environment.standardError.writeln(_rootUsage(parsers));
    return _ExitCode.usage;
  }

  if (root.flag('version')) {
    environment.standardOutput.writeln('ndjson_analyzer 0.1.0');
    return _ExitCode.success;
  }
  if (root.flag('help')) {
    environment.standardOutput.writeln(_rootUsage(parsers));
    return _ExitCode.success;
  }

  final command = root.command;
  if (command == null || command.name != 'analyze') {
    environment.standardError.writeln('Missing command: analyze');
    environment.standardError.writeln(_rootUsage(parsers));
    return _ExitCode.usage;
  }
  if (command.flag('help')) {
    environment.standardOutput.writeln(_analyzeUsage(parsers));
    return _ExitCode.success;
  }
  if (command.rest.length != 1) {
    environment.standardError.writeln(
      'The analyze command requires exactly one input path or - for stdin.',
    );
    environment.standardError.writeln(_analyzeUsage(parsers));
    return _ExitCode.usage;
  }

  late final AnalysisOptions options;
  try {
    options = _optionsFrom(command, environment.processorCount);
  } on FormatException catch (error) {
    environment.standardError.writeln('Argument error: ${error.message}');
    return _ExitCode.usage;
  }

  final inputPath = command.rest.single;
  late final Stream<List<int>> input;
  try {
    input = inputPath == '-'
        ? environment.standardInput
        : environment.openInput(inputPath);
  } on FileSystemException catch (error) {
    environment.standardError.writeln(_safeFileError(error));
    return _ExitCode.input;
  }

  final stopwatch = Stopwatch()..start();
  final run = const NdjsonAnalyzer().start(input, options: options);
  var interruptCount = 0;
  var lastProgressLine = 0;
  final interruptSubscription = environment.interrupts.listen((_) {
    interruptCount += 1;
    if (interruptCount == 1) {
      environment.standardError.writeln(
        'Interrupt received; finishing submitted batches...',
      );
      run.cancel();
    } else {
      environment.standardError.writeln(
        'Second interrupt; exiting immediately.',
      );
      environment.forceExit?.call(_ExitCode.interrupted);
    }
  });
  final progressSubscription = run.progress.listen((AnalysisProgress progress) {
    if (progress.linesRead - lastProgressLine >= 10000) {
      lastProgressLine = progress.linesRead;
      environment.standardError.writeln(
        'Processed ${progress.linesRead} lines '
        '(${progress.inFlightBatches} batches in flight)...',
      );
    }
  });

  try {
    final report = await run.done;
    stopwatch.stop();
    final format = command.option('format')!;
    if (format == 'json') {
      environment.standardOutput.writeln(
        const JsonEncoder.withIndent('  ').convert(report.toJson()),
      );
    } else {
      _writeTextReport(
        report,
        elapsed: stopwatch.elapsed,
        output: environment.standardOutput,
      );
    }

    return switch (report.status) {
      AnalysisStatus.complete
          when options.strict && report.invalidRecords > 0 =>
        _ExitCode.strictValidation,
      AnalysisStatus.complete => _ExitCode.success,
      AnalysisStatus.cancelled => _ExitCode.interrupted,
      AnalysisStatus.timedOut => _ExitCode.timeout,
    };
  } on FileSystemException catch (error) {
    environment.standardError.writeln(_safeFileError(error));
    return _ExitCode.input;
  } on WorkerBatchException catch (error) {
    environment.standardError.writeln('Worker failure: $error');
    return _ExitCode.internal;
  } on FormatException catch (error) {
    environment.standardError.writeln('Input failure: ${error.message}');
    return _ExitCode.input;
  } on Object catch (error) {
    environment.standardError.writeln(
      'Internal failure: ${error.runtimeType}: $error',
    );
    return _ExitCode.internal;
  } finally {
    stopwatch.stop();
    await interruptSubscription.cancel();
    await progressSubscription.cancel();
  }
}

AnalysisOptions _optionsFrom(ArgResults command, int processorCount) {
  if (processorCount < 1) {
    throw const FormatException('processor count must be positive');
  }
  final defaults = AnalysisOptions.forProcessors(processorCount);
  final workers = _integerOption(
    command,
    'workers',
    fallback: defaults.workerCount,
    minimum: 1,
  );
  final maxInFlight = _integerOption(
    command,
    'max-in-flight',
    fallback: workers * 2,
    minimum: 1,
  );
  final timeoutText = command.option('timeout');
  return AnalysisOptions(
    workerCount: workers,
    batchSize: _integerOption(command, 'batch-size', fallback: 256, minimum: 1),
    maxInFlightBatches: maxInFlight,
    maxErrors: _integerOption(command, 'max-errors', fallback: 20, minimum: 0),
    maxLineBytes: _integerOption(
      command,
      'max-line-bytes',
      fallback: 1024 * 1024,
      minimum: 1,
    ),
    strict: command.flag('strict'),
    sequential: command.flag('sequential'),
    timeout: timeoutText == null ? null : _parseDuration(timeoutText),
  );
}

int _integerOption(
  ArgResults command,
  String name, {
  required int fallback,
  required int minimum,
}) {
  final text = command.option(name);
  if (text == null) return fallback;
  final value = int.tryParse(text);
  if (value == null || value < minimum) {
    throw FormatException('--$name must be an integer >= $minimum');
  }
  return value;
}

Duration _parseDuration(String value) {
  final match = RegExp(r'^(\d+)(ms|s|m|h)$').firstMatch(value);
  if (match == null) {
    throw const FormatException(
      '--timeout must use an integer followed by ms, s, m, or h',
    );
  }
  final amount = int.parse(match.group(1)!);
  if (amount < 1) {
    throw const FormatException('--timeout must be positive');
  }
  return switch (match.group(2)) {
    'ms' => Duration(milliseconds: amount),
    's' => Duration(seconds: amount),
    'm' => Duration(minutes: amount),
    'h' => Duration(hours: amount),
    _ => throw StateError('Validated duration unit was lost.'),
  };
}

void _writeTextReport(
  AnalysisReport report, {
  required Duration elapsed,
  required StringSink output,
}) {
  final elapsedSeconds =
      elapsed.inMicroseconds / Duration.microsecondsPerSecond;
  final throughput = elapsedSeconds == 0
      ? 0
      : report.linesRead / elapsedSeconds;
  output
    ..writeln('NDJSON analysis: ${report.toJson()['status']}')
    ..writeln(
      'Lines: ${report.linesRead} '
      '(valid ${report.validRecords}, invalid ${report.invalidRecords}, '
      'blank ${report.blankLines})',
    )
    ..writeln('Types:');
  if (report.recordsByType.isEmpty) {
    output.writeln('  (none)');
  } else {
    for (final MapEntry<String, int>(:key, :value)
        in report.recordsByType.entries) {
      output.writeln('  $key: $value');
    }
  }

  final durations = report.durationStatistics;
  if (durations.count == 0) {
    output.writeln('Durations: (none)');
  } else {
    output.writeln(
      'Durations: count ${durations.count}, min ${durations.minimumMilliseconds} ms, '
      'max ${durations.maximumMilliseconds} ms, '
      'mean ${durations.meanMilliseconds!.toStringAsFixed(2)} ms',
    );
  }
  if (report.slowestEvents.isNotEmpty) {
    output.writeln('Slowest events:');
    for (final event in report.slowestEvents) {
      output.writeln(
        '  line ${event.lineNumber}: ${event.type} '
        '${event.durationMilliseconds} ms',
      );
    }
  }
  if (report.errors.isNotEmpty) {
    output.writeln('Errors:');
    for (final error in report.errors) {
      output.writeln(
        '  line ${error.lineNumber} [${error.toJson()['code']}]: '
        '${error.message}',
      );
    }
    if (report.suppressedErrors > 0) {
      output.writeln('  ... ${report.suppressedErrors} more');
    }
  }
  output
    ..writeln(
      'Workers: ${report.workerRestarts} restarts, '
      'peak ${report.maxObservedInFlightBatches} submitted batches',
    )
    ..writeln(
      'Runtime: ${elapsed.inMilliseconds} ms, '
      '${throughput.toStringAsFixed(1)} lines/s',
    );
}

String _safeFileError(FileSystemException error) {
  final path = error.path;
  return path == null
      ? 'Input failure: ${error.message}'
      : 'Input failure for "$path": ${error.message}';
}

_CliParsers _createParsers() {
  final analyze = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.')
    ..addOption(
      'format',
      allowed: const <String>['text', 'json'],
      defaultsTo: 'text',
      help: 'Report format written to stdout.',
    )
    ..addOption(
      'workers',
      help: 'Long-lived parser isolates (default: CPU based).',
    )
    ..addOption('batch-size', help: 'Lines per worker message (default: 256).')
    ..addOption(
      'max-in-flight',
      help: 'Submitted batch limit (default: workers x 2).',
    )
    ..addOption(
      'max-errors',
      help: 'Detailed validation errors retained (default: 20).',
    )
    ..addOption(
      'max-line-bytes',
      help: 'Maximum bytes accepted per line (default: 1048576).',
    )
    ..addFlag(
      'strict',
      negatable: false,
      help: 'Exit with code 1 when any input record is invalid.',
    )
    ..addFlag(
      'sequential',
      negatable: false,
      help: 'Parse on the calling isolate for comparison and debugging.',
    )
    ..addOption('timeout', help: 'Deadline such as 250ms, 30s, 2m, or 1h.');
  final root = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.')
    ..addFlag('version', negatable: false, help: 'Show the CLI version.')
    ..addCommand('analyze', analyze);
  return _CliParsers(root: root, analyze: analyze);
}

String _rootUsage(_CliParsers parsers) =>
    '''
Usage: ndjson_analyzer <command> [options]

Commands:
  analyze <path|->  Analyze an NDJSON file or stdin.

Global options:
${parsers.root.usage}
''';

String _analyzeUsage(_CliParsers parsers) =>
    '''
Usage: ndjson_analyzer analyze <path|-> [options]

${parsers.analyze.usage}
''';

final class _CliParsers {
  const _CliParsers({required this.root, required this.analyze});

  final ArgParser root;
  final ArgParser analyze;
}

abstract final class _ExitCode {
  static const success = 0;
  static const strictValidation = 1;
  static const usage = 64;
  static const input = 66;
  static const internal = 70;
  static const timeout = 124;
  static const interrupted = 130;
}
