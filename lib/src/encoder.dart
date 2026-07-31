import 'dart:collection';
import 'dart:convert';

import 'errors.dart';

final RegExp _keyPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_-]*$');

/// Physical line endings supported by the Nano Markup writer.
enum Newline {
  /// Line feed (`\n`).
  lf('\n'),

  /// Carriage return followed by line feed (`\r\n`).
  crlf('\r\n');

  const Newline(this.value);

  /// The physical character sequence used between output lines.
  final String value;
}

enum _Context { root, mapping, sequence }

String _pathKey(String path, String key) => '$path[${jsonEncode(key)}]';

void _validateString(String value, String path) {
  var scalarIndex = 0;
  for (var index = 0; index < value.length; index += 1) {
    final int unit = value.codeUnitAt(index);
    late final int codePoint;
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (index + 1 >= value.length) {
        throw EncodeError(
          '$path contains a character outside the Nano Markup data model '
          'at index $scalarIndex',
        );
      }
      final int next = value.codeUnitAt(index + 1);
      if (next < 0xdc00 || next > 0xdfff) {
        throw EncodeError(
          '$path contains a character outside the Nano Markup data model '
          'at index $scalarIndex',
        );
      }
      codePoint = 0x10000 + ((unit - 0xd800) << 10) + (next - 0xdc00);
      index += 1;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw EncodeError(
        '$path contains a character outside the Nano Markup data model '
        'at index $scalarIndex',
      );
    } else {
      codePoint = unit;
    }
    if (codePoint <= 0x08 ||
        (codePoint >= 0x0b && codePoint <= 0x0c) ||
        (codePoint >= 0x0e && codePoint <= 0x1f) ||
        (codePoint >= 0x7f && codePoint <= 0x9f)) {
      throw EncodeError(
        '$path contains a character outside the Nano Markup data model '
        'at index $scalarIndex',
      );
    }
    scalarIndex += 1;
  }
}

List<(String, Object?)> _mappingEntries(
  Map<Object?, Object?> value,
  String path,
) {
  final List<(String, Object?)> result = <(String, Object?)>[];
  for (final MapEntry<Object?, Object?> entry in value.entries) {
    final Object? key = entry.key;
    if (key is! String) {
      throw EncodeError(
        '$path contains a non-string mapping key ${jsonEncode(key.toString())}',
      );
    }
    result.add((key, entry.value));
  }
  return result;
}

final class _ValidationTask {
  const _ValidationTask(this.value, this.path, this.leaving);

  final Object? value;
  final String path;
  final bool leaving;
}

void _validateTree(Object value) {
  final HashSet<Object> active = HashSet<Object>.identity();
  final List<_ValidationTask> stack = <_ValidationTask>[
    _ValidationTask(value, r'$', false),
  ];
  while (stack.isNotEmpty) {
    final _ValidationTask task = stack.removeLast();
    final Object? current = task.value;
    if (task.leaving) {
      active.remove(current);
      continue;
    }
    if (current is String) {
      _validateString(current, task.path);
      continue;
    }
    if (current is! List<Object?> && current is! Map<Object?, Object?>) {
      final String type = current == null
          ? 'null'
          : current.runtimeType.toString();
      throw EncodeError(
        '${task.path} has unsupported type $type; expected String, Map, or List',
      );
    }
    if (active.contains(current)) {
      throw EncodeError('${task.path} contains a cyclic mapping or sequence');
    }
    active.add(current as Object);
    stack.add(_ValidationTask(current, task.path, true));
    if (current is List<Object?>) {
      for (var index = current.length - 1; index >= 0; index -= 1) {
        stack.add(
          _ValidationTask(current[index], '${task.path}[$index]', false),
        );
      }
    } else {
      final List<(String, Object?)> entries = _mappingEntries(
        current as Map<Object?, Object?>,
        task.path,
      );
      for (var index = entries.length - 1; index >= 0; index -= 1) {
        final (String key, Object? child) = entries[index];
        if (!_keyPattern.hasMatch(key)) {
          throw EncodeError(
            '${_pathKey(task.path, key)} uses an invalid Nano Markup key',
          );
        }
        stack.add(_ValidationTask(child, _pathKey(task.path, key), false));
      }
    }
  }
}

bool _rawIsSafe(String value, _Context context) {
  if (value.isEmpty ||
      value.startsWith(' ') ||
      value.startsWith('"') ||
      value.endsWith(' ')) {
    return false;
  }
  if (value.contains('\t') || value.contains('\r') || value.contains('\n')) {
    return false;
  }
  return context == _Context.mapping ||
      ((value != '..' && value != ':' && value != '|') &&
          !value.startsWith('#'));
}

String _quote(String value) {
  final StringBuffer result = StringBuffer('"');
  for (final int codePoint in value.runes) {
    switch (codePoint) {
      case 0x5c:
        result.write(r'\\');
      case 0x22:
        result.write(r'\"');
      case 0x0a:
        result.write(r'\n');
      case 0x0d:
        result.write(r'\r');
      case 0x09:
        result.write(r'\t');
      default:
        result.writeCharCode(codePoint);
    }
  }
  result.write('"');
  return result.toString();
}

String _scalar(String value, _Context context) =>
    _rawIsSafe(value, context) ? value : _quote(value);

bool _canUseMultiline(String value) =>
    value.contains('\n') &&
    !value.contains('\r') &&
    !value.contains('\t') &&
    !value.endsWith('\n') &&
    value
        .split('\n')
        .every((String line) => line.isEmpty || line.trim().isNotEmpty);

final class _WriteTask {
  const _WriteTask(this.value, this.level, this.context, [this.key]);

  final Object value;
  final int level;
  final _Context context;
  final String? key;
}

final class _Writer {
  final List<String> lines = <String>[];

  String indent(int level) => ' ' * (4 * level);

  void multiline(String header, String value, int contentLevel) {
    lines.add(header);
    final String prefix = indent(contentLevel);
    for (final String line in value.split('\n')) {
      lines.add(line.isNotEmpty ? '$prefix$line' : '');
    }
  }

  List<String> write(Object value) {
    final List<_WriteTask> tasks = <_WriteTask>[
      _WriteTask(value, 0, _Context.root),
    ];
    while (tasks.isNotEmpty) {
      final _WriteTask task = tasks.removeLast();
      final String prefix = indent(task.level);
      if (task.value is Map<Object?, Object?>) {
        if (task.context == _Context.root) {
          lines.add('..');
        } else if (task.context == _Context.mapping) {
          lines.add('$prefix${task.key}..');
        } else {
          lines.add('$prefix..');
        }
        final List<(String, Object?)> entries = _mappingEntries(
          task.value as Map<Object?, Object?>,
          r'$',
        );
        for (var index = entries.length - 1; index >= 0; index -= 1) {
          final (String key, Object? child) = entries[index];
          tasks.add(
            _WriteTask(child as Object, task.level + 1, _Context.mapping, key),
          );
        }
      } else if (task.value is List<Object?>) {
        if (task.context == _Context.root) {
          lines.add(':');
        } else if (task.context == _Context.mapping) {
          lines.add('$prefix${task.key}:');
        } else {
          lines.add('$prefix:');
        }
        final List<Object?> sequence = task.value as List<Object?>;
        for (var index = sequence.length - 1; index >= 0; index -= 1) {
          tasks.add(
            _WriteTask(
              sequence[index] as Object,
              task.level + 1,
              _Context.sequence,
            ),
          );
        }
      } else {
        final String stringValue = task.value as String;
        if (task.context == _Context.mapping) {
          if (stringValue.isEmpty) {
            lines.add('$prefix${task.key}');
          } else if (_canUseMultiline(stringValue)) {
            multiline('$prefix${task.key}|', stringValue, task.level + 1);
          } else {
            lines.add(
              '$prefix${task.key} ${_scalar(stringValue, _Context.mapping)}',
            );
          }
        } else if (_canUseMultiline(stringValue)) {
          multiline(
            task.context == _Context.root ? '|' : '$prefix|',
            stringValue,
            task.level + 1,
          );
        } else {
          lines.add(
            '$prefix${_scalar(stringValue, task.context == _Context.root ? _Context.root : _Context.sequence)}',
          );
        }
      }
    }
    return lines;
  }
}

/// Encodes a Dart Nano Markup value as one document string.
///
/// The value must recursively contain only [String], [Map] with string keys,
/// and [List]. Throws [EncodeError] for unsupported values, invalid keys,
/// forbidden characters, or cyclic containers. Shared acyclic containers are
/// accepted.
String encode(Object value, {Newline newline = Newline.lf}) {
  _validateTree(value);
  return _Writer().write(value).join(newline.value);
}
