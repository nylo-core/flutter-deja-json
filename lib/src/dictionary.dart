import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'exceptions.dart';
import 'zlib/zlib.dart' as zlib;

/// The shared compression dictionary: a bag of bytes both sides hold, plus
/// the short id the interceptor advertises so the server knows this client
/// holds the same one.
///
/// Train it server side with `php artisan dejajson:train`, ship the exact
/// file as an app asset, and load it once at startup:
///
/// ```dart
/// final bytes = await rootBundle.load('assets/dejajson/dictionary.bin');
/// final dictionary = DejaJsonDictionary.fromBytes(bytes.buffer.asUint8List());
/// ```
class DejaJsonDictionary {
  DejaJsonDictionary._(this.bytes, this.id);

  factory DejaJsonDictionary.fromBytes(List<int> bytes) {
    if (bytes.isEmpty) {
      throw const DejaJsonFormatException('A dictionary cannot be empty.');
    }
    final copy = Uint8List.fromList(bytes);
    return DejaJsonDictionary._(
        copy, sha256.convert(copy).toString().substring(0, idLength));
  }

  /// Hex characters of the SHA-256 hash used as the dictionary id — the same
  /// prefix the Laravel package computes.
  static const int idLength = 16;

  final Uint8List bytes;

  /// Advertised as `dict=<id>` in the request header; the server only uses
  /// dictionary mode when its own dictionary has the same id.
  final String id;

  List<int>? _zlibCheck;

  /// The 4-byte DICTID (RFC 1950) zlib stamps into streams compressed with
  /// this dictionary. Obtained from zlib itself, so decoding can tell
  /// "wrong dictionary" apart from "corrupt stream". Requires `dart:io`.
  List<int> zlibCheck() =>
      _zlibCheck ??= zlib.zlibDeflate(const [], 6, bytes).sublist(2, 6);
}
