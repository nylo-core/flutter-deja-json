/// Transparently decode DejaJson-encoded API responses with Dio.
///
/// Pairs with the `nylo/dejajson` Laravel package: the server compresses
/// JSON responses against a dictionary trained on your own API (zlib preset
/// dictionaries — the compressor has effectively already seen each response
/// before it starts), and [DejaJsonInterceptor] restores the original JSON
/// before your app sees it.
library;

export 'src/codec.dart' show DejaJsonCodec;
export 'src/dictionary.dart' show DejaJsonDictionary;
export 'src/exceptions.dart';
export 'src/interceptor.dart' show DejaJsonInterceptor;
