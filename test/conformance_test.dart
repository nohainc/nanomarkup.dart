import 'dart:convert';
import 'dart:io';

import 'package:nanomarkup/nanomarkup.dart';
import 'package:test/test.dart';

Map<String, Object?> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

void main() {
  final Map<String, Object?> manifest = _readJson('spec/tests/manifest.json');
  final List<Object?> valid = manifest['valid']! as List<Object?>;
  final List<Object?> invalid = manifest['invalid']! as List<Object?>;

  group('official decoder fixtures', () {
    for (final Object? item in valid) {
      final Map<String, Object?> fixture = item! as Map<String, Object?>;
      final String source = fixture['source']! as String;
      final String expected = fixture['expected']! as String;
      test(source, () {
        expect(
          decodeBytes(File('spec/tests/$source').readAsBytesSync()),
          jsonDecode(File('spec/tests/$expected').readAsStringSync()),
        );
      });
    }

    for (final Object? item in invalid) {
      final Map<String, Object?> fixture = item! as Map<String, Object?>;
      final String source = fixture['source']! as String;
      final String error = fixture['error']! as String;
      test(source, () {
        expect(
          () => decodeBytes(File('spec/tests/$source').readAsBytesSync()),
          throwsA(
            isA<DecodeError>().having(
              (DecodeError value) => value.code.value,
              'code',
              error,
            ),
          ),
        );
      });
    }
  });

  test('passes every official writer value with LF and CRLF', () {
    final Map<String, Object?> writer = _readJson(
      'spec/tests/writer/manifest.json',
    );
    final List<Object?> roundTrip = writer['round_trip']! as List<Object?>;
    for (final Object? item in roundTrip) {
      final Map<String, Object?> fixture = item! as Map<String, Object?>;
      final String path = fixture['value']! as String;
      final Object value =
          jsonDecode(File('spec/tests/writer/$path').readAsStringSync())
              as Object;
      for (final Newline newline in Newline.values) {
        expect(decode(encode(value, newline: newline)), value);
      }
    }
  });
}
