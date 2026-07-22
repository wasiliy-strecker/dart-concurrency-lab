import 'dart:convert';
import 'dart:io';

const _usage = 'Usage: dart run tool/check_coverage.dart <lcov-file> <minimum>';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }

  final threshold = double.tryParse(arguments[1]);
  if (threshold == null || threshold < 0 || threshold > 100) {
    stderr.writeln('Minimum coverage must be between 0 and 100.');
    exitCode = 64;
    return;
  }

  final file = File(arguments.first);
  if (!await file.exists()) {
    stderr.writeln('Coverage file not found: ${file.path}');
    exitCode = 66;
    return;
  }

  var foundLines = 0;
  var hitLines = 0;
  try {
    await for (final line
        in file
            .openRead()
            .transform(systemEncoding.decoder)
            .transform(const LineSplitter())) {
      foundLines += _metric(line, 'LF:');
      hitLines += _metric(line, 'LH:');
    }
  } on FormatException catch (error) {
    stderr.writeln('Invalid LCOV input: ${error.message}');
    exitCode = 65;
    return;
  } on FileSystemException catch (error) {
    stderr.writeln('Cannot read coverage file: ${error.message}');
    exitCode = 66;
    return;
  }

  if (foundLines == 0) {
    stderr.writeln('Coverage file contains no executable lines.');
    exitCode = 65;
    return;
  }

  final percentage = hitLines * 100 / foundLines;
  stdout.writeln(
    'Coverage: ${percentage.toStringAsFixed(2)}% '
    '($hitLines/$foundLines lines)',
  );
  if (percentage < threshold) {
    stderr.writeln(
      'Coverage is below the required ${threshold.toStringAsFixed(2)}%.',
    );
    exitCode = 1;
  }
}

int _metric(String line, String prefix) {
  if (!line.startsWith(prefix)) return 0;
  final value = int.tryParse(line.substring(prefix.length));
  if (value == null || value < 0) {
    throw FormatException('Invalid $prefix value.');
  }
  return value;
}
