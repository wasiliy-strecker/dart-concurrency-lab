import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:dart_concurrency_lab/dart_concurrency_lab.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('events', defaultsTo: '100000')
    ..addOption('runs', defaultsTo: '3')
    ..addOption('workers', defaultsTo: '4')
    ..addFlag('help', abbr: 'h', negatable: false);
  final results = parser.parse(arguments);
  if (results.flag('help')) {
    stdout.writeln('''
Usage: dart run benchmark/pipeline_benchmark.dart [options]

${parser.usage}
''');
    return;
  }

  final eventCount = _positiveInteger(results.option('events')!, '--events');
  final runCount = _positiveInteger(results.option('runs')!, '--runs');
  final workerCount = _positiveInteger(results.option('workers')!, '--workers');
  final bytes = _generateFixture(eventCount);
  final options = AnalysisOptions(
    workerCount: workerCount,
    maxInFlightBatches: workerCount * 2,
    maxErrors: 0,
    slowestEventLimit: 0,
  );

  final warmupBytes = Uint8List.sublistView(bytes, 0, min(bytes.length, 65536));
  await _measure(warmupBytes, options.copyWith(sequential: true));
  await _measure(warmupBytes, options);

  final sequentialTimes = <Duration>[];
  final isolateTimes = <Duration>[];
  AnalysisReport? reference;
  for (var run = 0; run < runCount; run += 1) {
    final sequential = await _measure(
      bytes,
      options.copyWith(sequential: true),
    );
    sequentialTimes.add(sequential.elapsed);
    reference ??= sequential.report;
    _requireEquivalent(reference, sequential.report);

    final isolated = await _measure(bytes, options);
    isolateTimes.add(isolated.elapsed);
    _requireEquivalent(reference, isolated.report);
  }

  final sequentialMedian = _median(sequentialTimes);
  final isolateMedian = _median(isolateTimes);
  stdout
    ..writeln('Dart concurrency pipeline benchmark')
    ..writeln('Dart: ${Platform.version.split(' ').first}')
    ..writeln(
      'OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    )
    ..writeln('Processors: ${Platform.numberOfProcessors}')
    ..writeln('Events: $eventCount')
    ..writeln('Input bytes: ${bytes.length}')
    ..writeln('Runs per engine: $runCount')
    ..writeln(
      'Sequential median: ${sequentialMedian.inMilliseconds} ms '
      '(${_throughput(eventCount, sequentialMedian)} events/s)',
    )
    ..writeln(
      'Isolate pool median ($workerCount workers): '
      '${isolateMedian.inMilliseconds} ms '
      '(${_throughput(eventCount, isolateMedian)} events/s)',
    )
    ..writeln('Reports: equivalent');
}

Future<({Duration elapsed, AnalysisReport report})> _measure(
  Uint8List bytes,
  AnalysisOptions options,
) async {
  final stopwatch = Stopwatch()..start();
  final report = await const NdjsonAnalyzer()
      .start(_chunked(bytes), options: options)
      .done;
  stopwatch.stop();
  return (elapsed: stopwatch.elapsed, report: report);
}

Stream<List<int>> _chunked(Uint8List bytes) async* {
  const chunkSize = 64 * 1024;
  for (var offset = 0; offset < bytes.length; offset += chunkSize) {
    final end = min(offset + chunkSize, bytes.length);
    yield Uint8List.sublistView(bytes, offset, end);
  }
}

Uint8List _generateFixture(int eventCount) {
  const types = <String>['request', 'sync', 'cache', 'render'];
  final timestamp = DateTime.utc(2026);
  final buffer = StringBuffer();
  for (var index = 0; index < eventCount; index += 1) {
    buffer
      ..write('{"timestamp":"')
      ..write(timestamp.add(Duration(milliseconds: index)).toIso8601String())
      ..write('","type":"')
      ..write(types[index % types.length])
      ..write('","duration_ms":')
      ..write((index * 37) % 500)
      ..writeln('}');
  }
  return Uint8List.fromList(utf8.encode(buffer.toString()));
}

void _requireEquivalent(AnalysisReport expected, AnalysisReport actual) {
  final expectedJson = Map<String, Object?>.of(expected.toJson())
    ..remove('max_observed_in_flight_batches');
  final actualJson = Map<String, Object?>.of(actual.toJson())
    ..remove('max_observed_in_flight_batches');
  if (jsonEncode(expectedJson) != jsonEncode(actualJson)) {
    throw StateError('Benchmark engines produced different reports.');
  }
}

Duration _median(List<Duration> values) {
  final sorted = List<Duration>.of(values)
    ..sort((Duration left, Duration right) => left.compareTo(right));
  return sorted[sorted.length ~/ 2];
}

String _throughput(int eventCount, Duration elapsed) {
  if (elapsed.inMicroseconds == 0) return 'unbounded';
  final perSecond =
      eventCount * Duration.microsecondsPerSecond / elapsed.inMicroseconds;
  return perSecond.toStringAsFixed(0);
}

int _positiveInteger(String value, String option) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < 1) {
    throw FormatException('$option must be a positive integer.');
  }
  return parsed;
}
