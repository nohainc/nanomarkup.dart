import 'dart:io';

import 'package:nanomarkup/nanomarkup.dart';

void main() {
  final String? tag = Platform.environment['GITHUB_REF_NAME'];
  final String pubspec = File('pubspec.yaml').readAsStringSync();
  final RegExpMatch? match = RegExp(
    r'^version:\s*([^\s]+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec);
  final String? packageVersion = match?.group(1);
  if (tag != 'v$version' ||
      packageVersion != version ||
      specVersion != '1.0.0') {
    stderr.writeln(
      'release mismatch: tag=$tag package=$packageVersion '
      'library=$version specification=$specVersion',
    );
    exitCode = 1;
  }
}
