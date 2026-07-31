/// Stable decoder error categories from Nano Markup 1.0.0.
enum ErrorCode {
  /// The input is not an allowed UTF-8/Unicode source document.
  encoding('E_ENCODING'),

  /// A literal tab occurs in the source.
  tab('E_TAB'),

  /// Indentation is malformed.
  indent('E_INDENT'),

  /// Document syntax is malformed.
  syntax('E_SYNTAX'),

  /// A mapping key is invalid.
  key('E_KEY'),

  /// A mapping repeats a key.
  duplicateKey('E_DUPLICATE_KEY'),

  /// A quoted-string escape is invalid.
  escape('E_ESCAPE'),

  /// A scalar string is malformed.
  string('E_STRING');

  const ErrorCode(this.value);

  /// The stable specification code transported by conformance adapters.
  final String value;

  @override
  String toString() => value;
}

/// Base class for Nano Markup codec errors.
sealed class NanoMarkupError implements Exception {
  /// Creates an error with a human-readable [message].
  const NanoMarkupError(this.message);

  /// Human-readable diagnostic text.
  final String message;
}

/// A source document could not be decoded.
final class DecodeError extends NanoMarkupError {
  /// Creates a decoder error with a stable category and source position.
  const DecodeError(
    this.code,
    super.message, {
    required this.byteOffset,
    required this.line,
    required this.column,
  });

  /// Stable Nano Markup error category.
  final ErrorCode code;

  /// Zero-based UTF-8 byte offset.
  final int byteOffset;

  /// One-based physical source line.
  final int line;

  /// One-based Unicode scalar column.
  final int column;

  @override
  String toString() => '$code at $line:$column: $message';
}

/// A Dart value cannot be represented by Nano Markup.
final class EncodeError extends NanoMarkupError {
  /// Creates a writer error.
  const EncodeError(super.message);

  @override
  String toString() => 'EncodeError: $message';
}
