import 'package:nanomarkup/nanomarkup.dart';

void main() {
  const String source = '''..
    name Ariana
    interests:
        cycling
        music''';

  final Object value = decode(source);
  final String encoded = encode(value);
  assert(decode(encoded).toString() == value.toString());
  print(encoded);
}
