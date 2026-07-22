/// Stable categories for malformed NDJSON input.
enum RecordErrorCode {
  /// The input contains malformed UTF-8.
  invalidUtf8,

  /// A line exceeds the configured byte limit.
  lineTooLong,

  /// The line is not valid JSON.
  invalidJson,

  /// The JSON value is not an object.
  notObject,

  /// The required `type` property is absent or empty.
  missingType,

  /// The optional timestamp is not a valid ISO-8601 string.
  invalidTimestamp,

  /// The optional duration is not a non-negative integer.
  invalidDuration,
}

/// One retained validation failure.
final class InvalidRecord {
  /// Creates a validation failure.
  const InvalidRecord({
    required this.lineNumber,
    required this.code,
    required this.message,
  });

  /// One-based physical line number.
  final int lineNumber;

  /// Machine-readable failure category.
  final RecordErrorCode code;

  /// Short human-readable explanation without source contents.
  final String message;

  /// Converts the failure to deterministic JSON data.
  Map<String, Object> toJson() => <String, Object>{
    'line': lineNumber,
    'code': _codeName(code),
    'message': message,
  };
}

String _codeName(RecordErrorCode code) => switch (code) {
  RecordErrorCode.invalidUtf8 => 'invalid_utf8',
  RecordErrorCode.lineTooLong => 'line_too_long',
  RecordErrorCode.invalidJson => 'invalid_json',
  RecordErrorCode.notObject => 'not_object',
  RecordErrorCode.missingType => 'missing_type',
  RecordErrorCode.invalidTimestamp => 'invalid_timestamp',
  RecordErrorCode.invalidDuration => 'invalid_duration',
};
