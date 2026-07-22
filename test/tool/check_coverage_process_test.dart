import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'dart_concurrency_lab_coverage_',
    );
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  test('accepts library coverage at the configured floor', () async {
    final result = await _runGuard(temporaryDirectory, minimum: '75');

    expect(result.exitCode, 0);
    expect(result.stdout, contains('Coverage: 75.00% (3/4 lines)'));
    expect(result.stderr, isEmpty);
  });

  test('rejects library coverage below the configured floor', () async {
    final result = await _runGuard(temporaryDirectory, minimum: '80');

    expect(result.exitCode, 1);
    expect(result.stdout, contains('Coverage: 75.00% (3/4 lines)'));
    expect(result.stderr, contains('below the required 80.00%'));
  });
}

Future<ProcessResult> _runGuard(
  Directory temporaryDirectory, {
  required String minimum,
}) {
  final coverageFile = File('${temporaryDirectory.path}/lcov.info')
    ..writeAsStringSync('''
TN:
SF:lib/example.dart
DA:1,1
DA:2,1
DA:3,1
DA:4,0
LF:4
LH:3
end_of_record
''');
  return Process.run(Platform.resolvedExecutable, <String>[
    'run',
    'tool/check_coverage.dart',
    coverageFile.path,
    minimum,
  ], workingDirectory: Directory.current.path);
}
