import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_concurrency_lab/src/cli/cli_runner.dart';
import 'package:test/test.dart';

void main() {
  test('writes deterministic JSON to stdout and no runtime fields', () async {
    final output = StringBuffer();
    final errors = StringBuffer();
    final code = await runNdjsonAnalyzerCli(
      <String>[
        'analyze',
        '-',
        '--format',
        'json',
        '--sequential',
        '--batch-size',
        '1',
      ],
      environment: _environment(
        input: Stream<List<int>>.value(
          utf8.encode('{"type":"ready","duration_ms":4}\n'),
        ),
        output: output,
        errors: errors,
      ),
    );

    final json = jsonDecode(output.toString()) as Map<String, dynamic>;
    expect(code, 0);
    expect(json['status'], 'complete');
    expect(json['records_by_type'], <String, dynamic>{'ready': 1});
    expect(json, isNot(contains('runtime')));
    expect(errors.toString(), isEmpty);
  });

  test('strict mode returns 1 after still writing the report', () async {
    final output = StringBuffer();
    final errors = StringBuffer();
    final code = await runNdjsonAnalyzerCli(
      <String>['analyze', '-', '--strict', '--sequential'],
      environment: _environment(
        input: Stream<List<int>>.value(utf8.encode('{broken\n')),
        output: output,
        errors: errors,
      ),
    );

    expect(code, 1);
    expect(output.toString(), contains('invalid 1'));
    expect(output.toString(), contains('[invalid_json]'));
  });

  test('usage errors and help use their documented channels', () async {
    final missingOutput = StringBuffer();
    final missingErrors = StringBuffer();
    final missingCode = await runNdjsonAnalyzerCli(
      const <String>[],
      environment: _environment(output: missingOutput, errors: missingErrors),
    );
    expect(missingCode, 64);
    expect(missingOutput.toString(), isEmpty);
    expect(missingErrors.toString(), contains('Missing command'));

    final helpOutput = StringBuffer();
    final helpErrors = StringBuffer();
    final helpCode = await runNdjsonAnalyzerCli(<String>[
      'analyze',
      '--help',
    ], environment: _environment(output: helpOutput, errors: helpErrors));
    expect(helpCode, 0);
    expect(helpOutput.toString(), contains('--max-in-flight'));
    expect(helpErrors.toString(), isEmpty);
  });

  test('maps a missing input file to exit code 66', () async {
    final output = StringBuffer();
    final errors = StringBuffer();
    final code = await runNdjsonAnalyzerCli(
      <String>['analyze', 'missing.ndjson'],
      environment: _environment(
        output: output,
        errors: errors,
        openInput: (String path) =>
            throw FileSystemException('Not found', path),
      ),
    );

    expect(code, 66);
    expect(output.toString(), isEmpty);
    expect(errors.toString(), contains('missing.ndjson'));
  });

  test('timeout emits a partial JSON report and exit code 124', () async {
    final input = StreamController<List<int>>();
    addTearDown(input.close);
    final output = StringBuffer();
    final errors = StringBuffer();

    final code = await runNdjsonAnalyzerCli(
      <String>[
        'analyze',
        '-',
        '--format',
        'json',
        '--sequential',
        '--timeout',
        '10ms',
      ],
      environment: _environment(
        input: input.stream,
        output: output,
        errors: errors,
      ),
    );

    expect(code, 124);
    expect(
      (jsonDecode(output.toString()) as Map<String, dynamic>)['status'],
      'timed_out',
    );
  });

  test('first interrupt requests graceful cancellation', () async {
    final input = StreamController<List<int>>();
    final interrupts = StreamController<void>.broadcast();
    addTearDown(input.close);
    addTearDown(interrupts.close);
    final output = StringBuffer();
    final errors = StringBuffer();

    final result = runNdjsonAnalyzerCli(
      <String>['analyze', '-', '--format', 'json', '--sequential'],
      environment: _environment(
        input: input.stream,
        output: output,
        errors: errors,
        interrupts: interrupts.stream,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    interrupts.add(null);

    expect(await result, 130);
    expect(errors.toString(), contains('finishing submitted batches'));
    expect(
      (jsonDecode(output.toString()) as Map<String, dynamic>)['status'],
      'cancelled',
    );
  });
}

CliEnvironment _environment({
  Stream<List<int>> input = const Stream<List<int>>.empty(),
  required StringBuffer output,
  required StringBuffer errors,
  CliInputOpener? openInput,
  Stream<void> interrupts = const Stream<void>.empty(),
}) => CliEnvironment(
  standardInput: input,
  standardOutput: output,
  standardError: errors,
  processorCount: 4,
  openInput: openInput ?? (String path) => File(path).openRead(),
  interrupts: interrupts,
);
