import 'dart:convert';

import '../model/invalid_record.dart';

/// One physical input line after bounded byte framing.
sealed class DecodedLine {
  /// Creates a decoded line outcome.
  const DecodedLine(this.lineNumber);

  /// One-based physical line number.
  final int lineNumber;
}

/// A valid UTF-8 line, without its line terminator.
final class ContentLine extends DecodedLine {
  /// Creates decoded content.
  const ContentLine({required int lineNumber, required this.content})
    : super(lineNumber);

  /// Decoded content. A trailing carriage return from CRLF is removed.
  final String content;
}

/// A framing or UTF-8 failure that prevented JSON parsing.
final class InvalidLine extends DecodedLine {
  /// Creates an invalid line result.
  const InvalidLine({required int lineNumber, required this.error})
    : super(lineNumber);

  /// Safe diagnostic without input contents.
  final InvalidRecord error;
}

/// Splits arbitrary byte chunks into memory-bounded UTF-8 lines.
Stream<DecodedLine> decodeUtf8Lines(
  Stream<List<int>> input, {
  required int maxLineBytes,
}) async* {
  final framer = Utf8LineFramer(maxLineBytes: maxLineBytes);
  await for (final chunk in input) {
    for (final line in framer.addChunk(chunk)) {
      yield line;
    }
  }
  final finalLine = framer.finish();
  if (finalLine != null) yield finalLine;
}

/// Stateful byte framer used when callers need direct stream cancellation.
final class Utf8LineFramer {
  /// Creates a framer with a strict per-line byte bound.
  Utf8LineFramer({required this.maxLineBytes}) {
    if (maxLineBytes < 1) {
      throw ArgumentError.value(
        maxLineBytes,
        'maxLineBytes',
        'must be positive',
      );
    }
  }

  /// Maximum accepted bytes before a line terminator.
  final int maxLineBytes;

  var _lineNumber = 1;
  var _overflowed = false;
  var _finished = false;
  final _buffer = <int>[];

  /// Adds an arbitrary byte chunk and returns every completed physical line.
  List<DecodedLine> addChunk(List<int> chunk) {
    if (_finished) throw StateError('Cannot add bytes after finish().');
    final lines = <DecodedLine>[];
    for (final byte in chunk) {
      if (byte < 0 || byte > 255) {
        throw const FormatException(
          'Input chunks must contain bytes from 0 to 255.',
        );
      }
      if (byte == 0x0a) {
        lines.add(_finishLine());
        _buffer.clear();
        _overflowed = false;
        _lineNumber += 1;
        continue;
      }
      if (_overflowed) continue;
      if (_buffer.length == maxLineBytes) {
        _buffer.clear();
        _overflowed = true;
      } else {
        _buffer.add(byte);
      }
    }
    return lines;
  }

  /// Finishes a non-terminated final line, if present.
  DecodedLine? finish() {
    if (_finished) return null;
    _finished = true;
    if (_buffer.isEmpty && !_overflowed) return null;
    return _finishLine();
  }

  DecodedLine _finishLine() {
    if (_overflowed) {
      return InvalidLine(
        lineNumber: _lineNumber,
        error: InvalidRecord(
          lineNumber: _lineNumber,
          code: RecordErrorCode.lineTooLong,
          message: 'Line exceeds the configured byte limit.',
        ),
      );
    }

    if (_buffer.isNotEmpty && _buffer.last == 0x0d) {
      _buffer.removeLast();
    }
    try {
      var content = utf8.decode(_buffer, allowMalformed: false);
      if (_lineNumber == 1 && content.startsWith('\uFEFF')) {
        content = content.substring(1);
      }
      return ContentLine(lineNumber: _lineNumber, content: content);
    } on FormatException {
      return InvalidLine(
        lineNumber: _lineNumber,
        error: InvalidRecord(
          lineNumber: _lineNumber,
          code: RecordErrorCode.invalidUtf8,
          message: 'Line is not valid UTF-8.',
        ),
      );
    }
  }
}
