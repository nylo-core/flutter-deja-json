import 'dart:io';

/// Whether zlib is available on this platform.
const bool zlibSupported = true;

/// Compress to a zlib (RFC 1950) stream — framed, not raw: the framing
/// carries the dictionary and content checksums, and `ZLibCodec` only
/// honours preset dictionaries on framed streams.
List<int> zlibDeflate(List<int> bytes, int level, List<int>? dictionary) =>
    ZLibEncoder(level: level, dictionary: dictionary).convert(bytes);

/// Decompress a zlib (RFC 1950) stream.
List<int> zlibInflate(List<int> bytes, List<int>? dictionary) =>
    ZLibDecoder(dictionary: dictionary).convert(bytes);
