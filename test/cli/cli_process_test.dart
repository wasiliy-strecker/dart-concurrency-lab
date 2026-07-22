import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('packaged executable analyzes the committed fixture', () async {
    final result = await Process.run(Platform.resolvedExecutable, <String>[
      'run',
      'bin/ndjson_analyzer.dart',
      'analyze',
      'test/fixtures/events.ndjson',
      '--format',
      'json',
      '--workers',
      '2',
      '--batch-size',
      '2',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 0, reason: result.stderr as String);
    expect(result.stderr as String, isEmpty);
    final report = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(report['valid_records'], 4);
    expect(report['invalid_records'], 0);
    expect(report['records_by_type'], <String, dynamic>{
      'request.completed': 2,
      'sync.completed': 1,
      'sync.started': 1,
    });
  });
}
