@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dejajson/dejajson.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Serves canned responses and records what the interceptor actually sent.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  RequestOptions? lastRequest;

  /// Captured at fetch time: the interceptor restores the caller's original
  /// responseType on the shared options object after decoding, so asserting
  /// on [lastRequest] later would see the restored value.
  ResponseType? sentResponseType;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    lastRequest = options;
    sentResponseType = options.responseType;
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _body(List<int> bytes, String contentType, {int status = 200}) =>
    ResponseBody.fromBytes(Uint8List.fromList(bytes), status, headers: {
      Headers.contentTypeHeader: [contentType],
    });

void main() {
  const codec = DejaJsonCodec();
  final dictionary =
      DejaJsonDictionary.fromBytes(utf8.encode(jsonEncode(users(15))));

  (Dio, _FakeAdapter) harness(ResponseBody Function(RequestOptions) handler,
      {DejaJsonInterceptor? interceptor}) {
    final adapter = _FakeAdapter(handler);
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
      ..httpClientAdapter = adapter
      ..interceptors
          .add(interceptor ?? DejaJsonInterceptor(dictionary: dictionary));
    return (dio, adapter);
  }

  test('advertises modes and dictionary id, and asks for bytes', () async {
    final (Dio dio, _FakeAdapter adapter) = harness(
        (options) => _body(utf8.encode('{"ok":true}'), 'application/json'));

    final Response<Object?> response = await dio.get<Object?>('/ping');

    expect(adapter.lastRequest!.headers['X-Deja-Json'],
        'dz; dict=${dictionary.id}');
    expect(adapter.sentResponseType, ResponseType.bytes);
    // The caller's original intent is restored after the fact.
    expect(response.requestOptions.responseType, ResponseType.json);
  });

  test('advertises only "z" without a dictionary', () async {
    final (Dio dio, _FakeAdapter adapter) = harness(
        (options) => _body(utf8.encode('{"ok":true}'), 'application/json'),
        interceptor: DejaJsonInterceptor());

    await dio.get<Object?>('/ping');

    expect(adapter.lastRequest!.headers['X-Deja-Json'], 'z');
  });

  test('decodes mode "d" responses and rewrites the content type', () async {
    final Map<String, List<Map<String, Object?>>> data = {'data': users(10)};
    final (Dio dio, _) = harness((options) => _body(
        codec.encode(data, modes: 'd', dictionary: dictionary),
        DejaJsonCodec.contentType));

    final Response<Object?> response = await dio.get<Object?>('/users');

    expect(deepEquals(response.data, data), isTrue);
    expect(response.headers.value(Headers.contentTypeHeader),
        startsWith('application/json'));
  });

  test('decodes mode "z" responses', () async {
    final Map<String, List<Map<String, Object?>>> data = {'data': users(10)};
    final (Dio dio, _) = harness((options) =>
        _body(codec.encode(data, modes: 'z'), DejaJsonCodec.contentType));

    final Response<Object?> response = await dio.get<Object?>('/users');

    expect(deepEquals(response.data, data), isTrue);
  });

  test('decodes envelopes even when a proxy rewrote the content type',
      () async {
    final Map<String, List<Map<String, Object?>>> data = {'data': users(5)};
    final (Dio dio, _) = harness((options) => _body(
        codec.encode(data, modes: 'd', dictionary: dictionary),
        'application/octet-stream'));

    final Response<Object?> response = await dio.get<Object?>('/users');

    expect(deepEquals(response.data, data), isTrue);
  });

  test('plain JSON responses come out exactly as Dio would produce them',
      () async {
    final (Dio dio, _) = harness((options) =>
        _body(utf8.encode('{"ok":true,"n":1.5}'), 'application/json'));

    final Response<Object?> response = await dio.get<Object?>('/plain');

    expect(response.data, {'ok': true, 'n': 1.5});
    expect(
        response.headers.value(Headers.contentTypeHeader), 'application/json');
  });

  test('plain text responses become strings', () async {
    final (Dio dio, _) =
        harness((options) => _body(utf8.encode('hello'), 'text/plain'));

    final Response<Object?> response = await dio.get<Object?>('/text');

    expect(response.data, 'hello');
  });

  test('empty bodies become null', () async {
    final (Dio dio, _) =
        harness((options) => _body(const [], 'application/json'));

    final Response<Object?> response = await dio.get<Object?>('/empty');

    expect(response.data, isNull);
  });

  test('non-UTF-8 binary passes through as bytes', () async {
    final png = [0x89, 0x50, 0x4E, 0x47, 0xFF, 0xFE];
    final (Dio dio, _) = harness((options) => _body(png, 'image/png'));

    final Response<Object?> response = await dio.get<Object?>('/image');

    expect(response.data, png);
  });

  test('a corrupt envelope surfaces as a DioException', () async {
    final (Dio dio, _) = harness((options) =>
        _body([0x44, 0x4A, 1, 0x7A, 9, 9, 9, 9, 9], DejaJsonCodec.contentType));

    await expectLater(
      dio.get<Object?>('/broken'),
      throwsA(isA<DioException>()
          .having((e) => e.type, 'type', DioExceptionType.badResponse)
          .having((e) => e.error, 'error', isA<DejaJsonFormatException>())),
    );
  });

  test('an envelope for a different dictionary names the problem', () async {
    final other = DejaJsonDictionary.fromBytes(utf8.encode('another dict'));
    final (Dio dio, _) = harness((options) => _body(
        codec.encode(users(5), modes: 'd', dictionary: other),
        DejaJsonCodec.contentType));

    await expectLater(
      dio.get<Object?>('/stale'),
      throwsA(isA<DioException>().having(
          (e) => '${e.error}', 'error', contains('different dictionary'))),
    );
  });

  test('encoded error responses are decoded too', () async {
    final Map<String, Object> errors = {
      'message': 'Invalid.',
      'errors': {
        'name': ['The name field is required.'],
      },
    };
    final (Dio dio, _) = harness((options) => _body(
        codec.encode(errors, modes: 'd', dictionary: dictionary),
        DejaJsonCodec.contentType,
        status: 422));

    try {
      await dio.post<Object?>('/form');
      fail('expected a DioException');
    } on DioException catch (e) {
      expect(deepEquals(e.response!.data, errors), isTrue);
    }
  });

  test('plain JSON error responses are decoded like Dio would', () async {
    final (Dio dio, _) = harness((options) => _body(
        utf8.encode('{"message":"Not found."}'), 'application/json',
        status: 404));

    try {
      await dio.get<Object?>('/missing');
      fail('expected a DioException');
    } on DioException catch (e) {
      expect(e.response!.data, {'message': 'Not found.'});
    }
  });

  test('requests for raw bytes are never advertised or touched', () async {
    final Uint8List envelope = codec.encode(users(5), modes: 'z');
    final (Dio dio, _FakeAdapter adapter) =
        harness((options) => _body(envelope, 'application/octet-stream'));

    final Response<Object?> response = await dio.get<Object?>('/raw',
        options: Options(responseType: ResponseType.bytes));

    expect(adapter.lastRequest!.headers.containsKey('X-Deja-Json'), isFalse);
    expect(response.data, envelope);
  });

  test('advertise=false leaves requests and responses alone', () async {
    final (Dio dio, _FakeAdapter adapter) = harness(
        (options) => _body(utf8.encode('{"ok":true}'), 'application/json'),
        interceptor:
            DejaJsonInterceptor(dictionary: dictionary, advertise: false));

    final Response<Object?> response = await dio.get<Object?>('/ping');

    expect(adapter.lastRequest!.headers.containsKey('X-Deja-Json'), isFalse);
    expect(adapter.sentResponseType, ResponseType.json);
    expect(response.data, {'ok': true});
  });

  test('a custom request header is honoured', () async {
    final (Dio dio, _FakeAdapter adapter) = harness(
        (options) => _body(utf8.encode('{}'), 'application/json'),
        interceptor: DejaJsonInterceptor(
            dictionary: dictionary, requestHeader: 'X-Custom-Deja'));

    await dio.get<Object?>('/ping');

    expect(adapter.lastRequest!.headers['X-Custom-Deja'],
        'dz; dict=${dictionary.id}');
    expect(adapter.lastRequest!.headers.containsKey('X-Deja-Json'), isFalse);
  });

  test('an existing header is not overwritten', () async {
    final (Dio dio, _FakeAdapter adapter) = harness(
        (options) => _body(utf8.encode('{"ok":true}'), 'application/json'));

    await dio.get<Object?>('/ping',
        options: Options(headers: {'x-deja-json': 'z'}));

    expect(adapter.lastRequest!.headers['x-deja-json'], 'z');
  });
}
