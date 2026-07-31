import 'dart:io';

import 'package:nanomarkup/nanomarkup.dart';

Future<List<int>> _readStdin() => stdin.fold<List<int>>(
  <int>[],
  (List<int> bytes, List<int> chunk) => bytes..addAll(chunk),
);

/// Runs the Nano Markup validator and returns its process exit status.
Future<int> runValidator(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--version') {
    stdout.writeln('nanomarkup $version (Nano Markup $specVersion)');
    return 0;
  }
  if (arguments.isEmpty) {
    stderr.writeln('usage: nanomarkup FILE...');
    return 2;
  }
  if (arguments.where((String value) => value == '-').length > 1) {
    stderr.writeln('nanomarkup: standard input may be specified only once');
    return 2;
  }
  var status = 0;
  for (final String name in arguments) {
    late final List<int> source;
    try {
      source = name == '-'
          ? await _readStdin()
          : await File(name).readAsBytes();
    } on Object catch (error) {
      stderr.writeln('$name: $error');
      status = 2;
      continue;
    }
    try {
      decodeBytes(source);
      stdout.writeln('$name: valid');
    } on DecodeError catch (error) {
      stderr.writeln(
        '$name:${error.line}:${error.column}: ${error.code}: ${error.message}',
      );
      if (status != 2) status = 1;
    } on Object catch (error) {
      stderr.writeln('$name: $error');
      status = 2;
    }
  }
  return status;
}

Future<void> main(List<String> arguments) async {
  exitCode = await runValidator(arguments);
}
