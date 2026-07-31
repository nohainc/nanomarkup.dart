import 'dart:convert';
import 'dart:io';

import 'package:nanomarkup/nanomarkup.dart';

void _output(Map<String, Object> value) {
  stdout.writeln(jsonEncode(value));
}

bool _isNanoValue(Object? value) {
  final List<Object?> stack = <Object?>[value];
  while (stack.isNotEmpty) {
    final Object? current = stack.removeLast();
    if (current is String) continue;
    if (current is List<Object?>) {
      stack.addAll(current);
      continue;
    }
    if (current is Map<Object?, Object?>) {
      for (final MapEntry<Object?, Object?> entry in current.entries) {
        if (entry.key is! String) return false;
        stack.add(entry.value);
      }
      continue;
    }
    return false;
  }
  return true;
}

Future<int> _main(List<String> arguments) async {
  if (arguments.length < 2 ||
      (arguments.first != 'parse' && arguments.first != 'write')) {
    return 2;
  }
  final String operation = arguments[0];
  final String path = arguments[1];
  late final List<int> data;
  try {
    data = await File(path).readAsBytes();
  } on Object catch (error) {
    stderr.writeln(error);
    return 2;
  }
  if (operation == 'parse') {
    try {
      _output(<String, Object>{'ok': true, 'value': decodeBytes(data)});
    } on DecodeError catch (error) {
      _output(<String, Object>{'ok': false, 'error': error.code.value});
    }
    return 0;
  }
  if (arguments.length != 3 ||
      (arguments[2] != 'LF' && arguments[2] != 'CRLF')) {
    return 2;
  }
  try {
    final Object? value = jsonDecode(utf8.decode(data, allowMalformed: false));
    if (!_isNanoValue(value)) {
      throw const EncodeError('not a Nano Markup value');
    }
    _output(<String, Object>{
      'ok': true,
      'source': encode(
        value as Object,
        newline: arguments[2] == 'LF' ? Newline.lf : Newline.crlf,
      ),
    });
  } on Object {
    _output(<String, Object>{'ok': false, 'error': 'E_VALUE'});
  }
  return 0;
}

Future<void> main(List<String> arguments) async {
  exitCode = await _main(arguments);
}
