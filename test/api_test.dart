import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:nanomarkup/nanomarkup.dart';
import 'package:test/test.dart';

void main() {
  test('exports stable version information and error codes', () {
    expect(version, '1.0.0');
    expect(specVersion, '1.0.0');
    expect(ErrorCode.values.map((ErrorCode value) => value.value), <String>[
      'E_ENCODING',
      'E_TAB',
      'E_INDENT',
      'E_SYNTAX',
      'E_KEY',
      'E_DUPLICATE_KEY',
      'E_ESCAPE',
      'E_STRING',
    ]);
  });

  test('decodes strings and byte-oriented input', () {
    const String source = '..\n    city Bratislava';
    final Map<String, Object> expected = <String, Object>{'city': 'Bratislava'};
    expect(decode(source), expected);
    expect(decodeBytes(Uint8List.fromList(source.codeUnits)), expected);
    expect(() => decodeBytes(<int>[256]), throwsA(isA<ArgumentError>()));
  });

  test('reports stable diagnostics and precedence', () {
    expect(
      () => decode('..\n    value '),
      throwsA(
        isA<DecodeError>()
            .having((DecodeError error) => error.code, 'code', ErrorCode.string)
            .having((DecodeError error) => error.line, 'line', 2)
            .having((DecodeError error) => error.column, 'column', 11)
            .having((DecodeError error) => error.byteOffset, 'byteOffset', 13),
      ),
    );
    expect(
      () => decode('..\n    value "bad\\q"\n      # later indentation error\n'),
      throwsA(
        isA<DecodeError>().having(
          (DecodeError error) => error.code,
          'code',
          ErrorCode.indent,
        ),
      ),
    );
    expect(
      () => decode('..\n    first "bad\\q"\n    second "also\\z"\n'),
      throwsA(
        isA<DecodeError>()
            .having((DecodeError error) => error.code, 'code', ErrorCode.escape)
            .having((DecodeError error) => error.line, 'line', 2),
      ),
    );
  });

  test('rejects invalid bytes and unpaired surrogates', () {
    expect(
      () => decodeBytes(<int>[0xff]),
      throwsA(
        isA<DecodeError>().having(
          (DecodeError error) => error.code,
          'code',
          ErrorCode.encoding,
        ),
      ),
    );
    final String invalid = 'ok${String.fromCharCode(0xd800)}';
    expect(
      () => decode(invalid),
      throwsA(
        isA<DecodeError>().having(
          (DecodeError error) => error.byteOffset,
          'byteOffset',
          2,
        ),
      ),
    );
    for (var byte = 0; byte < 256; byte += 1) {
      try {
        decodeBytes(<int>[byte]);
      } on Object catch (error) {
        expect(error, isA<DecodeError>());
      }
    }
  });

  test('round trips representative values and line endings', () {
    final List<Object> values = <Object>[
      '',
      'ordinary text',
      '..',
      '# heading',
      'first\n\nlast',
      'terminal newline\n',
      'tab\treturn\r',
      <String, Object>{
        'empty': '',
        'nested': <String, Object>{'age': '20'},
        'items': <Object>['one', 'one', <String, Object>{}],
      },
      <Object>[
        '',
        '..',
        ':',
        '|',
        '# value',
        <Object>['inner'],
      ],
    ];
    for (final Object value in values) {
      expect(decode(encode(value)), value);
    }
    final Map<String, Object> value = <String, Object>{
      'description': 'first\nsecond',
      'status': 'done',
    };
    final String crlf = encode(value, newline: Newline.crlf);
    expect(crlf, contains('\r\n'));
    expect(crlf.replaceAll('\r\n', ''), isNot(contains('\n')));
    expect(crlf.endsWith('\n'), isFalse);
    expect(decode(crlf), value);
  });

  test('rejects values outside the data model', () {
    for (final Object value in <Object>[
      true,
      1,
      1.5,
      DateTime(2026),
      <String>{'set'},
    ]) {
      expect(() => encode(value), throwsA(isA<EncodeError>()));
    }
    expect(
      () => encode(<String, Object>{'bad key': 'value'}),
      throwsA(isA<EncodeError>()),
    );
    expect(() => encode('bad\u0000'), throwsA(isA<EncodeError>()));
    expect(
      () => encode(String.fromCharCode(0xd800)),
      throwsA(isA<EncodeError>()),
    );
    expect(
      () => encode(<Object, Object>{1: 'value'}),
      throwsA(isA<EncodeError>()),
    );
  });

  test('accepts normally inferred Dart collection types and special keys', () {
    final Map<String, String> strings = <String, String>{
      '__proto__': 'safe',
      'constructor': 'value',
    };
    expect(decode(encode(strings)), strings);
    expect(decode(encode(<String>['Dart', 'Flutter'])), <String>[
      'Dart',
      'Flutter',
    ]);
  });

  test('rejects cycles and permits shared containers', () {
    final List<Object> cycle = <Object>[];
    cycle.add(cycle);
    expect(() => encode(cycle), throwsA(isA<EncodeError>()));
    final List<Object> shared = <Object>['value'];
    final List<Object> value = <Object>[shared, shared];
    expect(decode(encode(value)), value);
  });

  test('round trips deterministic generated trees', () {
    final Random random = Random(0x20260723);
    final List<String> strings = <String>[
      '',
      'plain',
      ' spaced ',
      '..',
      ':',
      '|',
      '# comment-like',
      'Žilina 🚲',
      'first\nsecond',
      'tab\tcarriage\r',
    ];

    Object generate(int depth) {
      if (depth == 0 || random.nextDouble() < 0.45) {
        return strings[random.nextInt(strings.length)];
      }
      if (random.nextBool()) {
        return List<Object>.generate(
          random.nextInt(5),
          (int _) => generate(depth - 1),
        );
      }
      return <String, Object>{
        for (var index = 0; index < random.nextInt(5); index += 1)
          'key-$index': generate(depth - 1),
      };
    }

    for (var index = 0; index < 200; index += 1) {
      final Object value = generate(4);
      expect(decode(encode(value)), value);
    }
  });

  test('handles deep nesting iteratively', () {
    const int depth = 1200;
    Object value = 'leaf';
    for (var index = 0; index < depth; index += 1) {
      value = <Object>[value];
    }
    Object decoded = decode(encode(value));
    for (var index = 0; index < depth; index += 1) {
      expect(decoded, isA<List<Object>>());
      decoded = (decoded as List<Object>).single;
    }
    expect(decoded, 'leaf');
  });

  test('documents safe file reading and writing', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'nanomarkup-dart-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final File input = File('${directory.path}/input.nano');
    final File output = File('${directory.path}/output.nano');
    await input.writeAsString('..\n    name Ariana');
    final Object value = decodeBytes(await input.readAsBytes());
    await output.writeAsString(encode(value));
    expect(decodeBytes(await output.readAsBytes()), value);
  });
}
