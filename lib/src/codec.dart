import 'dart:convert';
import 'dart:typed_data';

import 'dictionary.dart';
import 'exceptions.dart';
import 'zlib/zlib.dart' as zlib;

/// Encodes and decodes DejaJson v1 envelopes.
///
/// The envelope is binary:
///
///     byte 0-1  magic "DJ"
///     byte 2    format version (0x01)
///     byte 3    mode — "d" (zlib + shared dictionary) or "z" (zlib)
///     byte 4+   zlib stream (RFC 1950) of the minified UTF-8 JSON document
///
/// zlib needs `dart:io`, so the codec is unavailable in web builds —
/// [supportedModes] reflects that, and the interceptor advertises nothing
/// there (servers then send plain JSON).
class DejaJsonCodec {
  const DejaJsonCodec({this.level = 6});

  /// Wire format version.
  static const int version = 1;

  /// Content type marking DejaJson response bodies.
  static const String contentType = 'application/vnd.dejajson';

  /// Default request header advertising decode support to the server.
  static const String requestHeader = 'X-Deja-Json';

  /// zlib with the shared dictionary — the aggressive mode.
  static const String modeDict = 'd';

  /// Plain zlib — the fallback when the ids don't match (or no dictionary
  /// is trained yet).
  static const String modeZlib = 'z';

  /// The modes this platform can decode: `dz` with `dart:io`, none on the web.
  static String get supportedModes => zlib.zlibSupported ? 'dz' : '';

  static const int _headerBytes = 4;
  static const List<int> _magic = [0x44, 0x4A]; // "DJ"

  /// zlib level (1–9) used by [encode].
  final int level;

  /// Whether raw bytes look like an envelope (cheap sniff; [decode] still
  /// validates strictly).
  static bool looksLikeEnvelope(Object? data) =>
      data is List<int> &&
      data.length >= _headerBytes + 2 &&
      data[0] == _magic[0] &&
      data[1] == _magic[1] &&
      data[2] == version &&
      (data[3] == modeDict.codeUnitAt(0) || data[3] == modeZlib.codeUnitAt(0));

  /// Decode an envelope back into plain maps, lists and scalars. Mode "d"
  /// envelopes require the same [dictionary] they were encoded with.
  Object? decode(List<int> envelope, {DejaJsonDictionary? dictionary}) {
    if (envelope.length < _headerBytes + 2 ||
        envelope[0] != _magic[0] ||
        envelope[1] != _magic[1]) {
      throw const DejaJsonFormatException(
          'Payload is not a DejaJson envelope.');
    }
    if (envelope[2] != version) {
      throw const DejaJsonFormatException(
          'Payload is not a DejaJson v$version envelope.');
    }

    final int mode = envelope[3];
    final stream = envelope is Uint8List
        ? Uint8List.sublistView(envelope, _headerBytes)
        : Uint8List.fromList(envelope.sublist(_headerBytes));

    final List<int> inflated;
    if (mode == modeDict.codeUnitAt(0)) {
      inflated = _inflate(stream, _requireDictionary(stream, dictionary));
    } else if (mode == modeZlib.codeUnitAt(0)) {
      inflated = _inflate(stream, null);
    } else {
      throw const DejaJsonFormatException('Unsupported DejaJson mode.');
    }

    final String json;
    try {
      json = utf8.decode(inflated);
    } on FormatException catch (e) {
      throw DejaJsonFormatException(
          'The envelope did not contain UTF-8 JSON: ${e.message}');
    }

    try {
      return jsonDecode(json);
    } on FormatException catch (e) {
      throw DejaJsonFormatException(
          'The envelope did not contain valid JSON: ${e.message}');
    }
  }

  /// Encode data (anything `jsonEncode` accepts) into an envelope, using the
  /// smallest of the given [modes]. Mode "d" needs a [dictionary].
  ///
  /// The Laravel package does this server side; encoding here is useful for
  /// tests, fixtures, storage, or sending DejaJson request bodies.
  Uint8List encode(Object? data,
      {String? modes, DejaJsonDictionary? dictionary}) {
    final String effectiveModes = modes ?? supportedModes;

    final String json;
    try {
      json = jsonEncode(data);
    } on Object catch (e) {
      throw DejaJsonEncodeException('Cannot serialise the value to JSON: $e');
    }
    final Uint8List document = utf8.encode(json);

    Uint8List? best;

    if (dictionary != null && effectiveModes.contains(modeDict)) {
      best = _envelope(
          modeDict, zlib.zlibDeflate(document, level, dictionary.bytes));
    }

    if (effectiveModes.contains(modeZlib)) {
      final Uint8List candidate =
          _envelope(modeZlib, zlib.zlibDeflate(document, level, null));
      if (best == null || candidate.length < best.length) {
        best = candidate;
      }
    }

    if (best == null) {
      throw DejaJsonEncodeException(
          'DejaJson has no usable mode: got "$effectiveModes"'
          '${effectiveModes.contains(modeDict) && dictionary == null ? ' and no dictionary' : ''}.');
    }

    return best;
  }

  Uint8List _envelope(String mode, List<int> stream) {
    final bytes = Uint8List(_headerBytes + stream.length);
    bytes[0] = _magic[0];
    bytes[1] = _magic[1];
    bytes[2] = version;
    bytes[3] = mode.codeUnitAt(0);
    bytes.setRange(_headerBytes, bytes.length, stream);
    return bytes;
  }

  List<int> _inflate(Uint8List stream, DejaJsonDictionary? dictionary) {
    try {
      return zlib.zlibInflate(stream, dictionary?.bytes);
    } on DejaJsonException {
      rethrow;
    } catch (e) {
      throw DejaJsonFormatException(
          'The compressed payload could not be inflated: $e');
    }
  }

  /// A mode "d" stream names the dictionary it was written with (the DICTID
  /// header); compare before inflating so mismatches read as what they are.
  DejaJsonDictionary _requireDictionary(
      Uint8List stream, DejaJsonDictionary? dictionary) {
    if (dictionary == null) {
      throw const DejaJsonFormatException(
          'This envelope needs the shared dictionary, and none was provided.');
    }

    final bool fdict = stream.length >= 6 && (stream[1] & 0x20) != 0;
    if (fdict) {
      final List<int> check = dictionary.zlibCheck();
      for (var i = 0; i < 4; i++) {
        if (stream[2 + i] != check[i]) {
          throw DejaJsonFormatException(
              'This envelope was encoded with a different dictionary than '
              '"${dictionary.id}".');
        }
      }
    }

    return dictionary;
  }
}
