# Contributing

Bug reports and focused pull requests are welcome. For behavior changes, first
check whether the requested behavior is allowed by Nano Markup 1.0.0. Language
changes belong in the specification repository.

Run the complete checks before opening a pull request:

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

Add tests for every behavior change. Keep public API compatibility unless a
breaking change is explicitly approved for a major release. Repository changes
are submitted through pull requests and require owner review.
