import 'dart:convert';

import 'package:dio/dio.dart';

import 'codec.dart';
import 'dictionary.dart';
import 'exceptions.dart';

/// A Dio interceptor that advertises DejaJson support to the server and
/// transparently restores the full JSON on DejaJson responses — including
/// error responses (422 validation errors and friends).
///
/// ```dart
/// final dictionary = DejaJsonDictionary.fromBytes(dictionaryBytes);
///
/// final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
///   ..interceptors.add(DejaJsonInterceptor(dictionary: dictionary));
///
/// final response = await dio.get('/users');
/// print(response.data); // plain JSON, as if the server never encoded it
/// ```
///
/// DejaJson envelopes are binary, so for JSON requests the interceptor asks
/// Dio for raw bytes and rebuilds the normal JSON response itself — whether
/// the server encoded it or not. Servers without the package are unaffected:
/// plain responses come out exactly as Dio would have produced them.
///
/// Requests that ask for `bytes`, `stream` or `plain` responses are never
/// advertised for and never touched — you asked for raw data, you get raw
/// data.
class DejaJsonInterceptor extends Interceptor {
  DejaJsonInterceptor({
    this.codec = const DejaJsonCodec(),
    this.dictionary,
    this.advertise = true,
    String? modes,
    this.rewriteContentType = true,
    this.requestHeader = DejaJsonCodec.requestHeader,
  }) : modes = _usableModes(modes ?? DejaJsonCodec.supportedModes, dictionary);

  /// Marks requests this interceptor flipped to bytes, and remembers why.
  static const String _extraKey = 'dejajson.flipped';

  /// Decodes envelopes; swap in a configured instance if needed.
  final DejaJsonCodec codec;

  /// The shared dictionary (train it with `php artisan dejajson:train` and
  /// ship the file as an asset). Without one the interceptor still
  /// advertises mode "z" — you get ~gzip; with one you get the déjà vu.
  final DejaJsonDictionary? dictionary;

  /// Whether to advertise (and therefore decode) at all. When false the
  /// interceptor is inert — useful for turning DejaJson off per Dio instance
  /// without unwiring it.
  final bool advertise;

  /// The modes advertised to the server: `dz` with a dictionary, `z`
  /// without, nothing on web builds (zlib needs `dart:io`).
  final String modes;

  /// Rewrite the response content type to `application/json` after decoding,
  /// so downstream code sees a completely ordinary JSON response.
  final bool rewriteContentType;

  /// Header used to advertise support. Must match the Laravel package's
  /// `dejajson.request_header` config (default `X-Deja-Json`).
  final String requestHeader;

  static String _usableModes(String modes, DejaJsonDictionary? dictionary) {
    // Never advertise "d" without holding the dictionary — the server would
    // answer with envelopes this client cannot decode.
    return dictionary == null
        ? modes.replaceAll(DejaJsonCodec.modeDict, '')
        : modes;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final wantsJson = options.responseType == ResponseType.json;

    if (!advertise || modes.isEmpty || !wantsJson) {
      handler.next(options);
      return;
    }

    if (!_hasRequestHeader(options)) {
      final dict = dictionary;
      options.headers[requestHeader] =
          dict != null && modes.contains(DejaJsonCodec.modeDict)
              ? '$modes; dict=${dict.id}'
              : modes;
    }

    // Envelopes are binary: ask for bytes, rebuild the JSON response in
    // onResponse (for plain-JSON servers too).
    options.responseType = ResponseType.bytes;
    options.extra = {...options.extra, _extraKey: true};

    handler.next(options);
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    if (!_flipped(response.requestOptions)) {
      handler.next(response);
      return;
    }

    _restoreRequestOptions(response.requestOptions);

    try {
      _rebuild(response);
    } on DejaJsonException catch (error, stackTrace) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          error: error,
          stackTrace: stackTrace,
          message: 'Failed to decode a DejaJson response: ${error.message}',
        ),
        true,
      );
      return;
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    if (response != null && _flipped(err.requestOptions)) {
      _restoreRequestOptions(err.requestOptions);
      try {
        _rebuild(response);
      } on DejaJsonException {
        // The request already failed; surface the original error untouched.
      }
    }
    handler.next(err);
  }

  bool _flipped(RequestOptions options) => options.extra[_extraKey] == true;

  void _restoreRequestOptions(RequestOptions options) {
    // Leave retry interceptors and downstream inspectors seeing the caller's
    // original intent, not our bytes flip.
    options.responseType = ResponseType.json;
    options.extra = {...options.extra}..remove(_extraKey);
  }

  bool _hasRequestHeader(RequestOptions options) {
    final needle = requestHeader.toLowerCase();
    return options.headers.keys
        .any((String key) => key.toLowerCase() == needle);
  }

  /// Turn the raw bytes back into what the app expects: decoded DejaJson
  /// when the server encoded, otherwise exactly what Dio's own transformer
  /// would have produced for a JSON request.
  void _rebuild(Response<dynamic> response) {
    final data = response.data;
    if (data is! List<int>) {
      return; // Nothing to rebuild (null body, or another interceptor got here first).
    }

    if (_isDejaJson(response)) {
      response.data = codec.decode(data, dictionary: dictionary);
      if (rewriteContentType) {
        response.headers
            .set(Headers.contentTypeHeader, 'application/json; charset=utf-8');
      }
      return;
    }

    if (data.isEmpty) {
      response.data = null;
      return;
    }

    final contentType = response.headers.value(Headers.contentTypeHeader) ?? '';
    final String text;
    try {
      text = utf8.decode(data);
    } on FormatException {
      return; // Genuinely binary (an image, say) — hand the bytes through.
    }

    if (Transformer.isJsonMimeType(contentType)) {
      try {
        response.data = jsonDecode(text);
      } on FormatException catch (e) {
        throw DejaJsonFormatException(
            'The response declared JSON but did not parse: ${e.message}');
      }
      return;
    }

    response.data = text;
  }

  bool _isDejaJson(Response<dynamic> response) {
    final contentType = response.headers.value(Headers.contentTypeHeader);
    if (contentType != null) {
      final mime = contentType.split(';').first.trim().toLowerCase();
      if (mime == DejaJsonCodec.contentType) {
        return true;
      }
    }
    // Belt and braces: negotiation proxies occasionally rewrite content
    // types, but the magic bytes don't lie.
    return DejaJsonCodec.looksLikeEnvelope(response.data);
  }
}
