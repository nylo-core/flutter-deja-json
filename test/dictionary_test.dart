@TestOn('vm')
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dejajson/dejajson.dart';
import 'package:test/test.dart';

void main() {
  test('the id is a 16-hex sha256 prefix, matching the Laravel package', () {
    final bytes = utf8.encode('shared bytes');
    final dictionary = DejaJsonDictionary.fromBytes(bytes);

    expect(dictionary.id, sha256.convert(bytes).toString().substring(0, 16));
    expect(dictionary.id.length, DejaJsonDictionary.idLength);
  });

  test('empty dictionaries are rejected', () {
    expect(() => DejaJsonDictionary.fromBytes(const []),
        throwsA(isA<DejaJsonFormatException>()));
  });

  test('the bytes are defensively copied', () {
    final source = utf8.encode('mutable source').toList();
    final dictionary = DejaJsonDictionary.fromBytes(source);
    source[0] = 0;

    expect(dictionary.bytes[0], isNot(0));
  });

  test('zlibCheck matches the DICTID zlib writes into streams', () {
    final dictionary =
        DejaJsonDictionary.fromBytes(utf8.encode('{"id":1,"name":"User 1"}'));
    final envelope = const DejaJsonCodec().encode({'id': 2, 'name': 'User 2'},
        modes: 'd', dictionary: dictionary);

    // Envelope layout: DJ, version, mode, CMF, FLG, DICTID (4 bytes).
    expect(dictionary.zlibCheck(), hasLength(4));
    expect(envelope.sublist(6, 10), dictionary.zlibCheck());
  });
}
