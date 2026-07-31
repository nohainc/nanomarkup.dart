@TestOn('browser')
library;

import 'package:nanomarkup/nanomarkup.dart';
import 'package:test/test.dart';

void main() {
  test('core codec works without dart:io', () {
    final Object value = decode('..\n    runtime browser\n    language Dart');
    expect(decode(encode(value)), value);
  });
}
