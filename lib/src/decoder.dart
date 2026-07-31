import 'dart:convert';

import 'errors.dart';

final RegExp _keyPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_-]*$');

const Map<ErrorCode, int> _errorPriority = <ErrorCode, int>{
  ErrorCode.encoding: 0,
  ErrorCode.tab: 1,
  ErrorCode.indent: 2,
  ErrorCode.syntax: 3,
  ErrorCode.key: 4,
  ErrorCode.duplicateKey: 5,
  ErrorCode.escape: 6,
  ErrorCode.string: 7,
};

final class _SourceLine {
  const _SourceLine(this.text, this.number, this.byteStart);

  final String text;
  final int number;
  final int byteStart;
}

final class _Diagnostic {
  const _Diagnostic(
    this.code,
    this.message,
    this.byteOffset,
    this.line,
    this.column,
  );

  final ErrorCode code;
  final String message;
  final int byteOffset;
  final int line;
  final int column;
}

enum _ContainerKind { mapping, sequence }

final class _Frame {
  const _Frame(this.kind, this.level, this.value);

  final _ContainerKind kind;
  final int level;
  final Object value;
}

int _codePointLength(String value) => value.runes.length;

(int, int) _sourcePosition(List<int> data, int offset) {
  final int safeOffset = offset.clamp(0, data.length);
  var line = 1;
  var lineStart = 0;
  for (var index = 0; index < safeOffset; index += 1) {
    if (data[index] == 0x0a) {
      line += 1;
      lineStart = index + 1;
    }
  }
  var end = safeOffset;
  if (end > lineStart && data[end - 1] == 0x0d) end -= 1;
  final String prefix = utf8.decode(data.sublist(lineStart, end));
  return (line, _codePointLength(prefix) + 1);
}

int _firstUnpairedSurrogate(String source) {
  for (var index = 0; index < source.length; index += 1) {
    final int unit = source.codeUnitAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (index + 1 >= source.length) return index;
      final int next = source.codeUnitAt(index + 1);
      if (next < 0xdc00 || next > 0xdfff) return index;
      index += 1;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return index;
    }
  }
  return -1;
}

int _firstInvalidUtf8(List<int> data) {
  bool continuation(int index) =>
      index < data.length && data[index] >= 0x80 && data[index] <= 0xbf;

  for (var index = 0; index < data.length;) {
    final int byte = data[index];
    if (byte <= 0x7f) {
      index += 1;
      continue;
    }
    var length = 0;
    var secondMin = 0x80;
    var secondMax = 0xbf;
    if (byte >= 0xc2 && byte <= 0xdf) {
      length = 2;
    } else if (byte >= 0xe0 && byte <= 0xef) {
      length = 3;
      if (byte == 0xe0) secondMin = 0xa0;
      if (byte == 0xed) secondMax = 0x9f;
    } else if (byte >= 0xf0 && byte <= 0xf4) {
      length = 4;
      if (byte == 0xf0) secondMin = 0x90;
      if (byte == 0xf4) secondMax = 0x8f;
    } else {
      return index;
    }
    if (index + length > data.length) return index;
    final int second = data[index + 1];
    if (second < secondMin || second > secondMax) return index;
    for (var extra = 2; extra < length; extra += 1) {
      if (!continuation(index + extra)) return index;
    }
    index += length;
  }
  return -1;
}

Never _preparationError(List<int> data, int offset, String message) {
  final (int line, int column) = _sourcePosition(data, offset);
  throw DecodeError(
    ErrorCode.encoding,
    message,
    byteOffset: offset,
    line: line,
    column: column,
  );
}

List<int> _sourceBytes(String source) {
  final int invalid = _firstUnpairedSurrogate(source);
  if (invalid >= 0) {
    final String prefix = source.substring(0, invalid);
    final int lineStart = prefix.lastIndexOf('\n') + 1;
    throw DecodeError(
      ErrorCode.encoding,
      'source contains a value that is not a Unicode scalar',
      byteOffset: utf8.encode(prefix).length,
      line: '\n'.allMatches(prefix).length + 1,
      column: _codePointLength(prefix.substring(lineStart)) + 1,
    );
  }
  return utf8.encode(source);
}

List<int> _copyBytes(List<int> source) {
  final List<int> result = List<int>.filled(source.length, 0);
  for (var index = 0; index < source.length; index += 1) {
    final int byte = source[index];
    if (byte < 0 || byte > 255) {
      throw ArgumentError.value(
        byte,
        'source[$index]',
        'byte values must be between 0 and 255',
      );
    }
    result[index] = byte;
  }
  return result;
}

List<int> _validateAndDecode(List<int> data) {
  final List<(int, String)> errors = <(int, String)>[];
  if (data.length >= 3 &&
      data[0] == 0xef &&
      data[1] == 0xbb &&
      data[2] == 0xbf) {
    errors.add((0, 'UTF-8 byte-order marks are not permitted'));
  }
  for (var index = 0; index < data.length; index += 1) {
    final int byte = data[index];
    if (byte <= 0x08 ||
        (byte >= 0x0b && byte <= 0x0c) ||
        (byte >= 0x0e && byte <= 0x1f) ||
        byte == 0x7f) {
      errors.add((index, 'source contains a forbidden control character'));
    } else if (byte == 0x0d &&
        (index + 1 >= data.length || data[index + 1] != 0x0a)) {
      errors.add((index, 'a carriage return must be followed by a line feed'));
    }
  }
  final int invalidUtf8 = _firstInvalidUtf8(data);
  if (invalidUtf8 >= 0) {
    errors.add((invalidUtf8, 'source is not valid UTF-8'));
  } else {
    final String text = utf8.decode(data);
    var byteOffset = 0;
    for (final int codePoint in text.runes) {
      if (codePoint >= 0x80 && codePoint <= 0x9f) {
        errors.add((
          byteOffset,
          'source contains a forbidden control character',
        ));
      }
      byteOffset += utf8.encode(String.fromCharCode(codePoint)).length;
    }
  }
  if (errors.isNotEmpty) {
    errors.sort(
      ((int, String) left, (int, String) right) => left.$1.compareTo(right.$1),
    );
    _preparationError(data, errors.first.$1, errors.first.$2);
  }
  final int tabOffset = data.indexOf(0x09);
  if (tabOffset >= 0) {
    final (int line, int column) = _sourcePosition(data, tabOffset);
    throw DecodeError(
      ErrorCode.tab,
      r'literal tabs are not permitted; use spaces or the quoted \t escape',
      byteOffset: tabOffset,
      line: line,
      column: column,
    );
  }
  return data;
}

List<_SourceLine> _physicalLines(List<int> data) {
  final List<_SourceLine> lines = <_SourceLine>[];
  var start = 0;
  var number = 1;
  while (start < data.length) {
    var end = data.indexOf(0x0a, start);
    final int nextStart = end < 0 ? data.length : end + 1;
    if (end < 0) end = data.length;
    var contentEnd = end;
    if (contentEnd > start && data[contentEnd - 1] == 0x0d) contentEnd -= 1;
    lines.add(
      _SourceLine(utf8.decode(data.sublist(start, contentEnd)), number, start),
    );
    number += 1;
    start = nextStart;
  }
  return lines;
}

int _leadingSpaces(_SourceLine line) {
  var count = 0;
  while (count < line.text.length && line.text.codeUnitAt(count) == 0x20) {
    count += 1;
  }
  return count;
}

bool _isBlank(_SourceLine line) {
  if (line.text.isEmpty) return true;
  for (final int unit in line.text.codeUnits) {
    if (unit != 0x20) return false;
  }
  return true;
}

final class _Parser {
  _Parser(this.data, this.lines);

  final List<int> data;
  final List<_SourceLine> lines;
  final List<_Diagnostic> diagnostics = <_Diagnostic>[];
  int index = 0;

  void addError(
    ErrorCode code,
    String message, [
    _SourceLine? line,
    int characterOffset = 0,
  ]) {
    if (line == null) {
      final int byteOffset = data.length;
      final (int sourceLine, int column) = _sourcePosition(data, byteOffset);
      diagnostics.add(
        _Diagnostic(code, message, byteOffset, sourceLine, column),
      );
      return;
    }
    final String prefix = line.text.substring(0, characterOffset);
    diagnostics.add(
      _Diagnostic(
        code,
        message,
        line.byteStart + utf8.encode(prefix).length,
        line.number,
        _codePointLength(prefix) + 1,
      ),
    );
  }

  void skipIgnored() {
    while (index < lines.length) {
      final _SourceLine line = lines[index];
      if (_isBlank(line)) {
        index += 1;
        continue;
      }
      final int spaces = _leadingSpaces(line);
      if (line.text.substring(spaces).startsWith('#')) {
        if (spaces % 4 != 0) {
          addError(
            ErrorCode.indent,
            'comment indentation must use complete four-space levels',
            line,
            spaces,
          );
        }
        index += 1;
        continue;
      }
      break;
    }
  }

  (int, String)? lineParts(_SourceLine line) {
    final int spaces = _leadingSpaces(line);
    if (spaces % 4 != 0) {
      addError(
        ErrorCode.indent,
        'indentation must use exactly four spaces per level',
        line,
        spaces,
      );
      return null;
    }
    return (spaces ~/ 4, line.text.substring(spaces));
  }

  String parseQuoted(String text, _SourceLine line, int start) {
    final StringBuffer result = StringBuffer();
    const Map<int, String> escapes = <int, String>{
      0x22: '"',
      0x5c: r'\',
      0x6e: '\n',
      0x72: '\r',
      0x74: '\t',
    };
    var current = 1;
    while (current < text.length) {
      final int unit = text.codeUnitAt(current);
      if (unit == 0x22) {
        if (current != text.length - 1) {
          addError(
            ErrorCode.string,
            'a quoted string must occupy the complete scalar position',
            line,
            start + current + 1,
          );
        }
        return result.toString();
      }
      if (unit == 0x5c) {
        if (current + 1 >= text.length) {
          addError(
            ErrorCode.escape,
            'an escape must be followed by a supported escape character',
            line,
            start + current,
          );
          current += 1;
          continue;
        }
        final int escaped = text.codeUnitAt(current + 1);
        final String? replacement = escapes[escaped];
        if (replacement == null) {
          addError(
            ErrorCode.escape,
            'unsupported escape \\${String.fromCharCode(escaped)}',
            line,
            start + current,
          );
          current += 2;
          continue;
        }
        result.write(replacement);
        current += 2;
        continue;
      }
      if (unit >= 0xd800 && unit <= 0xdbff) {
        final int next = text.codeUnitAt(current + 1);
        final int codePoint =
            0x10000 + ((unit - 0xd800) << 10) + (next - 0xdc00);
        result.writeCharCode(codePoint);
        current += 2;
      } else {
        result.writeCharCode(unit);
        current += 1;
      }
    }
    addError(
      ErrorCode.string,
      'quoted string is missing its closing quotation mark',
      line,
      start + text.length,
    );
    return result.toString();
  }

  String parseScalar(String text, _SourceLine line, int start) {
    if (text.startsWith('"')) return parseQuoted(text, line, start);
    if (text.isEmpty) {
      addError(ErrorCode.string, 'a raw string cannot be empty', line, start);
      return '';
    }
    if (text.startsWith(' ')) {
      addError(
        ErrorCode.string,
        'an unquoted string cannot begin with an ASCII space',
        line,
        start,
      );
    }
    if (text.endsWith(' ')) {
      addError(
        ErrorCode.string,
        'an unquoted string cannot end with an ASCII space',
        line,
        start + text.length - 1,
      );
    }
    return text;
  }

  String collectMultiline(int headerLevel) {
    final String prefix = ' ' * (4 * (headerLevel + 1));
    final List<String> content = <String>[];
    var provisionalBlanks = 0;
    while (index < lines.length) {
      final _SourceLine line = lines[index];
      if (_isBlank(line)) {
        provisionalBlanks += 1;
        index += 1;
        continue;
      }
      if (!line.text.startsWith(prefix)) break;
      for (var blank = 0; blank < provisionalBlanks; blank += 1) {
        content.add('');
      }
      provisionalBlanks = 0;
      content.add(line.text.substring(prefix.length));
      index += 1;
    }
    return content.join('\n');
  }

  bool checkKey(String key, _SourceLine line, int start) {
    if (_keyPattern.hasMatch(key)) return true;
    addError(
      ErrorCode.key,
      'invalid mapping key ${jsonEncode(key)}',
      line,
      start,
    );
    return false;
  }

  void putMapping(
    Map<String, Object> mapping,
    String key,
    Object value,
    _SourceLine line,
    int start,
    bool valid,
  ) {
    if (!valid) return;
    if (mapping.containsKey(key)) {
      addError(
        ErrorCode.duplicateKey,
        'duplicate mapping key ${jsonEncode(key)}',
        line,
        start,
      );
      return;
    }
    mapping[key] = value;
  }

  _Frame? mappingEntry(_Frame frame, _SourceLine line, String text, int start) {
    final Map<String, Object> mapping = frame.value as Map<String, Object>;
    _ContainerKind? childKind;
    late final String key;
    late final Object value;
    if (text.endsWith('..') && !text.contains(' ')) {
      key = text.substring(0, text.length - 2);
      value = <String, Object>{};
      childKind = _ContainerKind.mapping;
    } else if (text.endsWith(':') && !text.contains(' ')) {
      key = text.substring(0, text.length - 1);
      value = <Object>[];
      childKind = _ContainerKind.sequence;
    } else if (text.endsWith('|') && !text.contains(' ')) {
      key = text.substring(0, text.length - 1);
      value = collectMultiline(frame.level);
    } else if (!text.contains(' ')) {
      key = text;
      value = '';
    } else {
      final int separator = text.indexOf(' ');
      key = text.substring(0, separator);
      value = parseScalar(
        text.substring(separator + 1),
        line,
        start + key.length + 1,
      );
    }
    final bool valid = checkKey(key, line, start);
    putMapping(mapping, key, value, line, start, valid);
    if (childKind == null) return null;
    return _Frame(childKind, frame.level + 1, value);
  }

  _Frame? sequenceEntry(
    _Frame frame,
    _SourceLine line,
    String text,
    int start,
  ) {
    final List<Object> sequence = frame.value as List<Object>;
    if (text == '..') {
      final Map<String, Object> mapping = <String, Object>{};
      sequence.add(mapping);
      return _Frame(_ContainerKind.mapping, frame.level + 1, mapping);
    }
    if (text == ':') {
      final List<Object> child = <Object>[];
      sequence.add(child);
      return _Frame(_ContainerKind.sequence, frame.level + 1, child);
    }
    if (text == '|') {
      sequence.add(collectMultiline(frame.level));
    } else if (!text.startsWith('#')) {
      sequence.add(parseScalar(text, line, start));
    }
    return null;
  }

  void parseContainer(_Frame root) {
    final List<_Frame> stack = <_Frame>[root];
    while (stack.isNotEmpty && index < lines.length) {
      skipIgnored();
      if (index >= lines.length) break;
      final _SourceLine line = lines[index];
      final (int, String)? parts = lineParts(line);
      if (parts == null) {
        index += 1;
        continue;
      }
      final int level = parts.$1;
      final String text = parts.$2;
      final _Frame frame = stack.last;
      if (level < frame.level) {
        stack.removeLast();
        continue;
      }
      if (level > frame.level) {
        addError(
          ErrorCode.indent,
          'unexpected or skipped indentation level',
          line,
          _leadingSpaces(line),
        );
        index += 1;
        continue;
      }
      index += 1;
      final int start = _leadingSpaces(line);
      final _Frame? child = frame.kind == _ContainerKind.mapping
          ? mappingEntry(frame, line, text, start)
          : sequenceEntry(frame, line, text, start);
      if (child != null) stack.add(child);
    }
  }

  Object parseRoot() {
    skipIgnored();
    if (index >= lines.length) return <String, Object>{};
    final _SourceLine line = lines[index];
    final (int, String)? parts = lineParts(line);
    final int level = parts?.$1 ?? (_leadingSpaces(line) ~/ 4);
    final String text = parts?.$2 ?? line.text.substring(_leadingSpaces(line));
    if (level != 0) {
      addError(
        ErrorCode.indent,
        'the document root must begin at indentation level zero',
        line,
        _leadingSpaces(line),
      );
    }
    index += 1;
    if (text == '..') {
      final Map<String, Object> mapping = <String, Object>{};
      parseContainer(_Frame(_ContainerKind.mapping, 1, mapping));
      return mapping;
    }
    if (text == ':') {
      final List<Object> sequence = <Object>[];
      parseContainer(_Frame(_ContainerKind.sequence, 1, sequence));
      return sequence;
    }
    if (text == '|') return collectMultiline(level);
    return parseScalar(text, line, _leadingSpaces(line));
  }

  Object parse() {
    final Object value = parseRoot();
    while (index < lines.length) {
      skipIgnored();
      if (index >= lines.length) break;
      final _SourceLine line = lines[index];
      final (int, String)? parts = lineParts(line);
      if (parts == null) {
        index += 1;
        continue;
      }
      if (parts.$1 != 0) {
        addError(
          ErrorCode.indent,
          'unexpected indentation after the document root',
          line,
          _leadingSpaces(line),
        );
      } else {
        addError(
          ErrorCode.syntax,
          'a document must contain exactly one root value',
          line,
        );
      }
      index += 1;
    }
    if (diagnostics.isNotEmpty) {
      diagnostics.sort((_Diagnostic left, _Diagnostic right) {
        final int priority = _errorPriority[left.code]!.compareTo(
          _errorPriority[right.code]!,
        );
        return priority != 0
            ? priority
            : left.byteOffset.compareTo(right.byteOffset);
      });
      final _Diagnostic error = diagnostics.first;
      throw DecodeError(
        error.code,
        error.message,
        byteOffset: error.byteOffset,
        line: error.line,
        column: error.column,
      );
    }
    return value;
  }
}

/// Decodes one Nano Markup document from a Dart string.
///
/// Throws [DecodeError] when the source is not a conforming document. Use
/// [decodeBytes] for file or network input so invalid UTF-8 remains detectable.
Object decode(String source) => decodeBytes(_sourceBytes(source));

/// Decodes one Nano Markup document from raw UTF-8 bytes.
///
/// Throws [ArgumentError] if an element is outside the byte range 0 through
/// 255, and [DecodeError] for malformed source data.
Object decodeBytes(List<int> source) {
  final List<int> data = _validateAndDecode(_copyBytes(source));
  return _Parser(data, _physicalLines(data)).parse();
}
