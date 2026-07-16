import 'dart:convert';

import 'package:dejajson/dejajson.dart';
import 'package:dio/dio.dart';

Future<void> main() async {
  // Ship the server's trained dictionary as an asset and load it once at
  // startup. In Flutter:
  //
  //   final data = await rootBundle.load('assets/dejajson/dictionary.bin');
  //   final dictionary = DejaJsonDictionary.fromBytes(data.buffer.asUint8List());
  final dictionary =
      DejaJsonDictionary.fromBytes(utf8.encode('…dictionary bytes…'));

  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
    ..interceptors.add(DejaJsonInterceptor(dictionary: dictionary));

  // The interceptor adds `X-Deja-Json: dz; dict=<id>` to every JSON request.
  // When the server answers with application/vnd.dejajson, the binary body
  // is decoded in place — response.data is ordinary JSON data, exactly as if
  // the server had sent plain JSON.
  final response = await dio.get<Object?>('/users');
  print(response.data);

  // Manual decoding (websockets, cached blobs, …) works too:
  const codec = DejaJsonCodec();
  final envelope = codec.encode({'hello': 'world'}, dictionary: dictionary);
  print(codec.decode(envelope, dictionary: dictionary));
}
