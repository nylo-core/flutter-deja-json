@TestOn('vm')
library;

import 'dart:convert';

import 'package:dejajson/dejajson.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const codec = DejaJsonCodec();
  final dictionary =
      DejaJsonDictionary.fromBytes(utf8.encode(jsonEncode(users(15))));

  test('this platform supports both modes', () {
    expect(DejaJsonCodec.supportedModes, 'dz');
  });

  test('mode z round trips', () {
    final data = users();
    final envelope = codec.encode(data, modes: 'z');

    expect(envelope[3], 'z'.codeUnitAt(0));
    expect(deepEquals(codec.decode(envelope), data), isTrue);
    expect(envelope.length, lessThan(jsonEncode(data).length));
  });

  test('mode d round trips and beats mode z', () {
    final data = users();
    final withDict = codec.encode(data, modes: 'd', dictionary: dictionary);
    final without = codec.encode(data, modes: 'z');

    expect(withDict[3], 'd'.codeUnitAt(0));
    expect(deepEquals(codec.decode(withDict, dictionary: dictionary), data),
        isTrue);
    expect(withDict.length, lessThan(without.length));
  });

  test('encode picks the smaller mode', () {
    // A dictionary that shares nothing with the payload only adds the 4-byte
    // DICTID, so plain zlib must win.
    final useless =
        DejaJsonDictionary.fromBytes(utf8.encode('qwertyuiop' * 50));
    final unrelated =
        codec.encode({'unrelated': 'payload'}, dictionary: useless);
    expect(unrelated[3], 'z'.codeUnitAt(0));

    // A dictionary the payload leans on wins by a wide margin.
    final related = codec.encode(users(), dictionary: dictionary);
    expect(related[3], 'd'.codeUnitAt(0));
  });

  test('mode d without a dictionary cannot encode', () {
    expect(() => codec.encode({'a': 1}, modes: 'd'),
        throwsA(isA<DejaJsonEncodeException>()));
  });

  test('unknown modes cannot encode', () {
    expect(() => codec.encode({'a': 1}, modes: 'x'),
        throwsA(isA<DejaJsonEncodeException>()));
  });

  test('unencodable values throw', () {
    expect(() => codec.encode(Object(), modes: 'z'),
        throwsA(isA<DejaJsonEncodeException>()));
  });

  test('scalar documents round trip', () {
    for (final Object? value in [
      null,
      true,
      42,
      9.75,
      'text',
      <Object?>[],
      <String, Object?>{}
    ]) {
      expect(deepEquals(codec.decode(codec.encode(value, modes: 'z')), value),
          isTrue,
          reason: 'for $value');
    }
  });

  test('unicode and slashes survive', () {
    final data = {
      'name': 'Zoë 👩‍💻',
      'url': 'https://example.com/path?a=1',
      'money': '£9.99 · €10,49',
    };

    expect(
        deepEquals(
            codec.decode(codec.encode(data, dictionary: dictionary),
                dictionary: dictionary),
            data),
        isTrue);
  });

  test('plain JSON bytes fail loudly', () {
    expect(() => codec.decode(utf8.encode('{"plain":"json"}')),
        throwsA(isA<DejaJsonFormatException>()));
  });

  test('truncated envelopes fail loudly', () {
    expect(() => codec.decode([0x44, 0x4A, 1, 0x7A]),
        throwsA(isA<DejaJsonFormatException>()));
  });

  test('unknown versions fail loudly', () {
    expect(
        () => codec.decode([0x44, 0x4A, 2, 0x7A, 0, 0, 0, 0]),
        throwsA(isA<DejaJsonFormatException>()
            .having((e) => e.message, 'message', contains('v1'))));
  });

  test('unknown modes fail loudly', () {
    expect(() => codec.decode([0x44, 0x4A, 1, 0x78, 0, 0, 0, 0]),
        throwsA(isA<DejaJsonFormatException>()));
  });

  test('corrupt streams fail loudly', () {
    final envelope = codec.encode(users(), modes: 'z');
    final corrupt = [...envelope];
    corrupt.setRange(10, 14, [126, 126, 126, 126]);

    expect(
        () => codec.decode(corrupt), throwsA(isA<DejaJsonFormatException>()));
  });

  test('mode d without the dictionary names the problem', () {
    final envelope = codec.encode(users(), modes: 'd', dictionary: dictionary);

    expect(
        () => codec.decode(envelope),
        throwsA(isA<DejaJsonFormatException>().having((e) => e.message,
            'message', contains('needs the shared dictionary'))));
  });

  test('mode d with the wrong dictionary names the problem', () {
    final envelope = codec.encode(users(), modes: 'd', dictionary: dictionary);
    final other = DejaJsonDictionary.fromBytes(
        utf8.encode('a completely different dictionary'));

    expect(
        () => codec.decode(envelope, dictionary: other),
        throwsA(isA<DejaJsonFormatException>().having(
            (e) => e.message, 'message', contains('different dictionary'))));
  });

  test('looksLikeEnvelope sniffs correctly', () {
    expect(DejaJsonCodec.looksLikeEnvelope(codec.encode(users(), modes: 'z')),
        isTrue);
    expect(
        DejaJsonCodec.looksLikeEnvelope(
            codec.encode(users(), modes: 'd', dictionary: dictionary)),
        isTrue);
    expect(DejaJsonCodec.looksLikeEnvelope(utf8.encode('{"a":1}')), isFalse);
    expect(DejaJsonCodec.looksLikeEnvelope([0x44, 0x4A]), isFalse);
    expect(
        DejaJsonCodec.looksLikeEnvelope([0x44, 0x4A, 1, 0x78, 0, 0]), isFalse);
    expect(DejaJsonCodec.looksLikeEnvelope('not bytes'), isFalse);
    expect(DejaJsonCodec.looksLikeEnvelope(null), isFalse);
  });

  test('compression level is honoured', () {
    final data = users(200);
    final fast = const DejaJsonCodec(level: 1).encode(data, modes: 'z');
    final best = const DejaJsonCodec(level: 9).encode(data, modes: 'z');

    expect(best.length, lessThanOrEqualTo(fast.length));
    expect(deepEquals(codec.decode(best), data), isTrue);
  });
}
