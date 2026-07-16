@TestOn('browser')
library;

import 'package:dejajson/dejajson.dart';
import 'package:test/test.dart';

/// Web builds have no dart:io zlib: the codec must refuse politely and the
/// interceptor must advertise nothing (so servers send plain JSON).
void main() {
  test('no modes are supported on the web', () {
    expect(DejaJsonCodec.supportedModes, isEmpty);
  });

  test('encoding throws the unsupported-platform error', () {
    expect(() => const DejaJsonCodec().encode({'a': 1}, modes: 'z'),
        throwsA(isA<DejaJsonUnsupportedException>()));
  });

  test('decoding throws the unsupported-platform error', () {
    expect(() => const DejaJsonCodec().decode([0x44, 0x4A, 1, 0x7A, 0, 0]),
        throwsA(isA<DejaJsonUnsupportedException>()));
  });

  test('the interceptor advertises nothing here', () {
    expect(DejaJsonInterceptor().modes, isEmpty);
  });
}
