@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:dejajson/dejajson.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Cross-implementation vectors shared with the nylo/dejajson Laravel
/// package. If one of these fails, the wire format broke — bump the version
/// instead of changing the encoding silently.
void main() {
  final fixture =
      jsonDecode(File('test/fixtures/vectors.json').readAsStringSync())
          as Map<String, dynamic>;
  const codec = DejaJsonCodec();

  final dictionaryMeta = fixture['dictionary'] as Map<String, dynamic>;
  final dictionary = DejaJsonDictionary.fromBytes(
      base64.decode(dictionaryMeta['base64'] as String));

  test('the fixture dictionary id matches its bytes', () {
    expect(dictionary.id, dictionaryMeta['id']);
  });

  for (final vector
      in (fixture['vectors'] as List).cast<Map<String, dynamic>>()) {
    final name = vector['name'] as String;
    final Object? data = vector['data'];

    test('$name: PHP mode "z" envelope decodes to the original data', () {
      final decoded = codec.decode(base64.decode(vector['z'] as String));
      expect(deepEquals(decoded, data), isTrue,
          reason: 'expected $data, got $decoded');
    });

    test('$name: PHP mode "d" envelope decodes to the original data', () {
      final decoded = codec.decode(base64.decode(vector['d'] as String),
          dictionary: dictionary);
      expect(deepEquals(decoded, data), isTrue,
          reason: 'expected $data, got $decoded');
    });

    test('$name: both modes re-encode losslessly', () {
      final z = codec.encode(data, modes: 'z');
      final d = codec.encode(data, modes: 'd', dictionary: dictionary);

      expect(deepEquals(codec.decode(z), data), isTrue);
      expect(deepEquals(codec.decode(d, dictionary: dictionary), data), isTrue);
    });
  }
}
