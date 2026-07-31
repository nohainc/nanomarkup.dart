/// Nano Markup 1.0.0 decoding and encoding for Dart.
library;

export 'src/decoder.dart' show decode, decodeBytes;
export 'src/encoder.dart' show Newline, encode;
export 'src/errors.dart'
    show DecodeError, EncodeError, ErrorCode, NanoMarkupError;
export 'src/version.dart' show specVersion, version;
