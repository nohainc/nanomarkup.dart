import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

Future<String> _streamText(Stream<List<int>> stream) =>
    utf8.decoder.bind(stream).join();

void main() {
  test('CLI reports version and file validation status', () async {
    final ProcessResult version = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/nanomarkup.dart', '--version'],
    );
    expect(version.exitCode, 0);
    expect(version.stdout, 'nanomarkup 1.0.0 (Nano Markup 1.0.0)\n');

    final ProcessResult result =
        await Process.run(Platform.resolvedExecutable, <String>[
          'run',
          'bin/nanomarkup.dart',
          'spec/tests/valid/root_mapping.nano',
          'spec/tests/invalid/partial_indent.nano',
        ]);
    expect(result.exitCode, 1);
    expect(result.stdout, contains('root_mapping.nano: valid'));
    expect(result.stderr, contains('partial_indent.nano:'));
    expect(result.stderr, contains('E_INDENT'));
  });

  test('CLI accepts stdin and rejects duplicate stdin', () async {
    final Process process = await Process.start(
      Platform.resolvedExecutable,
      <String>['run', 'bin/nanomarkup.dart', '-'],
    );
    final Future<String> output = _streamText(process.stdout);
    final Future<String> errors = _streamText(process.stderr);
    process.stdin.write('plain');
    await process.stdin.close();
    expect(await process.exitCode, 0);
    expect(await output, '-: valid\n');
    expect(await errors, isEmpty);

    final ProcessResult duplicate = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/nanomarkup.dart', '-', '-'],
    );
    expect(duplicate.exitCode, 2);
  });

  test('CLI distinguishes file-system failures', () async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/nanomarkup.dart', 'does-not-exist.nano'],
    );
    expect(result.exitCode, 2);
    expect(result.stderr, contains('does-not-exist.nano'));
  });
}
