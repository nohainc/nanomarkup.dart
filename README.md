# Nano Markup for Dart

[![CI](https://github.com/nohainc/nanomarkup.dart/actions/workflows/ci.yml/badge.svg)](https://github.com/nohainc/nanomarkup.dart/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

`nanomarkup` is a zero-runtime-dependency Dart decoder and encoder for
[Nano Markup](https://github.com/nohainc/nanomarkup.spec), a minimal,
human-readable structured data format. The pure-Dart core works in command-line
and server applications, Dart web applications, and Flutter without depending
on Flutter.

Version 1.0.0 implements the stable **Nano Markup 1.0.0** decoder and writer
profiles. The first pub.dev release is prepared but has not yet been published.

## Installation

After the first release is published:

```console
dart pub add nanomarkup
```

Dart 3.12 or later is required.

## API

Nano Markup values map directly to Dart values:

| Nano Markup | Dart                  |
| ----------- | --------------------- |
| String      | `String`              |
| Mapping     | `Map<String, Object>` |
| Sequence    | `List<Object>`        |

All scalars remain strings. The decoder never infers numbers, booleans, null,
dates, or application-specific types.

```dart
import 'package:nanomarkup/nanomarkup.dart';

void main() {
  const source = '''..
    name Ariana
    age 12
    interests:
        cycling
        music''';

  final Object value = decode(source);
  final String encoded = encode(value);
  assert(decode(encoded).toString() == value.toString());
}
```

Use `decodeBytes` for file, network, or other byte-oriented input so malformed
UTF-8 is diagnosed by Nano Markup instead of being replaced during an earlier
text conversion:

```dart
import 'dart:io';
import 'package:nanomarkup/nanomarkup.dart';

final value = decodeBytes(await File('input.nano').readAsBytes());
await File('output.nano').writeAsString(encode(value));
```

Writer output defaults to LF. Select CRLF explicitly when required:

```dart
final source = encode(value, newline: Newline.crlf);
```

Mapping iteration order is retained for readable output, although mapping
order is not part of the Nano Markup data model. `Map` and `List` containers
are accepted; invalid keys, forbidden string characters, unsupported values,
and cycles raise `EncodeError`. Shared acyclic containers are permitted.

### Errors

Invalid source raises `DecodeError`, which carries the stable specification
category and location:

```dart
try {
  decode('..\n   bad indentation');
} on DecodeError catch (error) {
  print(error.code == ErrorCode.indent);
  print(error.byteOffset); // zero-based UTF-8 byte offset
  print(error.line);       // one-based line
  print(error.column);     // one-based Unicode column
}
```

The library exports `version` and `specVersion`, both initially `1.0.0`.

### Web and Flutter

The public library imports only browser-safe Dart libraries. Use it directly
from Dart web or Flutter code with the same API. File-system access belongs in
the calling application and is intentionally not part of the core codec.

## Validator

After activating the package, validate one or more files with:

```console
nanomarkup settings.nano other.nano
nanomarkup - < settings.nano
nanomarkup --version
```

Each valid input is reported on standard output. Diagnostics use
`path:line:column: CODE: message` on standard error. Exit status is `0` when
all inputs are valid, `1` when a document is invalid, and `2` for usage or I/O
errors.

## Conformance and development

The `spec` Git submodule pins the official conformance suite at commit
`bba11e49ca3a904cef07b067f6fc0597b0facba2` (tag `v1.0.0`).

```console
git clone --recurse-submodules https://github.com/nohainc/nanomarkup.dart.git
cd nanomarkup.dart
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze
dart test --exclude-tags browser
python3 spec/tests/run_conformance.py 'dart run tool/conformance.dart'
dart test --platform chrome test/browser_smoke_test.dart
dart doc
dart pub publish --dry-run
```

See [CHANGELOG.md](CHANGELOG.md), [CONTRIBUTING.md](CONTRIBUTING.md), and
[SECURITY.md](SECURITY.md) for project policies.

The implementation provides data decoding and writing only. Comments,
whitespace, quote choice, source line endings, and mapping source order are not
preserved. There is no source-preserving document API, schema system, implicit
type conversion, or executable syntax.

No explicit parser resource caps are imposed. Applications accepting untrusted
documents should bound input size according to their environment.

## Publishing

Stable releases are prepared from reviewed `vX.Y.Z` tags using pub.dev's
GitHub OIDC publishing. The one-time package bootstrap and complete release
checks are documented in [RELEASING.md](RELEASING.md).

## License

The Dart implementation is licensed under the [MIT License](LICENSE).

The specification submodule and conformance materials are separate works
licensed under the [Creative Commons Attribution 4.0 International License](https://github.com/nohainc/nanomarkup.spec/blob/bba11e49ca3a904cef07b067f6fc0597b0facba2/LICENSE).
See [NOTICE.md](NOTICE.md) for attribution and the pinned source revision.
