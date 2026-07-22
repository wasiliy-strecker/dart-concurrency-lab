import 'dart:convert';

import 'package:dart_concurrency_lab/src/input/line_decoder.dart';
import 'package:dart_concurrency_lab/src/model/invalid_record.dart';
import 'package:test/test.dart';

void main() {
  test('frames CRLF and a split UTF-8 BOM across arbitrary chunks', () async {
    final bytes = <int>[
      ...utf8.encode('\uFEFF{"type":"one"}\r\n'),
      ...utf8.encode('{"type":"two"}'),
    ];
    final chunks = <List<int>>[
      bytes.sublist(0, 1),
      bytes.sublist(1, 5),
      bytes.sublist(5, 17),
      bytes.sublist(17),
    ];

    final lines = await decodeUtf8Lines(
      Stream<List<int>>.fromIterable(chunks),
      maxLineBytes: 1024,
    ).toList();

    expect(lines, hasLength(2));
    expect((lines[0] as ContentLine).content, '{"type":"one"}');
    expect((lines[1] as ContentLine).content, '{"type":"two"}');
    expect(lines.map((DecodedLine line) => line.lineNumber), <int>[1, 2]);
  });

  test('reports malformed UTF-8 without retaining source bytes', () async {
    final lines = await decodeUtf8Lines(
      Stream<List<int>>.value(<int>[0xff, 0x0a]),
      maxLineBytes: 10,
    ).toList();

    final invalid = lines.single as InvalidLine;
    expect(invalid.error.code, RecordErrorCode.invalidUtf8);
    expect(invalid.error.message, isNot(contains('255')));
  });

  test('discards an overflowing line and resumes at the next one', () async {
    final lines = await decodeUtf8Lines(
      Stream<List<int>>.value(utf8.encode('1234\nok\n')),
      maxLineBytes: 3,
    ).toList();

    expect((lines[0] as InvalidLine).error.code, RecordErrorCode.lineTooLong);
    expect((lines[1] as ContentLine).content, 'ok');
  });
}
