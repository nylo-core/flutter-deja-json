# dejajson

Transparently decode DejaJson-encoded API responses with a drop-in
[Dio](https://pub.dev/packages/dio) interceptor.

Pairs with the [`nylo/dejajson`](https://github.com/nylo-core/laravel-deja-json)
Laravel package: the server compresses JSON responses against a **dictionary
trained on your own API** (zlib preset dictionaries — the compressor has
effectively *already seen* each response before it starts), and
`DejaJsonInterceptor` restores the original JSON before your app sees it.
Your models, decoders and error handling don't change at all.

Measured on realistic Laravel API payloads:

| Payload | plain JSON | transport gzip | **dejajson** |
|---|---|---|---|
| single resource | 693 B | 437 B (−37%) | **58 B (−92%)** |
| list of 25 | 17,469 B | 1,581 B (−91%) | **887 B (−95%)** |
| list of 200 | 137,919 B | 8,002 B (−94%) | **7,303 B (−95%)** |

- **Zero app-code changes** — `response.data` is plain JSON data, exactly as
  if the server had never encoded it. Error responses (422 validation errors
  and friends) are decoded too, and plain-JSON servers pass through exactly
  as Dio would have produced them.
- **Safe by negotiation** — the interceptor advertises support (and its
  dictionary id) with an `X-Deja-Json` request header; servers only encode
  for clients that ask, and only use the dictionary when both sides hold
  identical bytes. A stale dictionary degrades to plain zlib, never to
  garbage.
- **Native platforms** — zlib comes from `dart:io`. Web builds advertise
  nothing and receive plain JSON, so code stays portable.

## Getting started

```bash
dart pub add dejajson    # or: flutter pub add dejajson
```

Train a dictionary server side and ship it as an asset:

```bash
# on the Laravel side
php artisan dejajson:train storage/dejajson-samples
cp storage/app/dejajson/dictionary.bin <your_app>/assets/dejajson/dictionary.bin
```

```yaml
# pubspec.yaml
flutter:
  assets:
    - assets/dejajson/dictionary.bin
```

```dart
import 'package:dio/dio.dart';
import 'package:dejajson/dejajson.dart';
import 'package:flutter/services.dart' show rootBundle;

final bytes = await rootBundle.load('assets/dejajson/dictionary.bin');
final dictionary = DejaJsonDictionary.fromBytes(bytes.buffer.asUint8List());

final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
  ..interceptors.add(DejaJsonInterceptor(dictionary: dictionary));

final response = await dio.get('/users');
print(response.data); // plain JSON — decoded transparently
```

No dictionary yet? `DejaJsonInterceptor()` without one advertises mode `z`
and still gets you ~gzip-level compression with no setup.

After retraining on the server, ship the new file with your next app release.
In between, old clients keep working: the ids no longer match, so the server
simply falls back to mode `z` for them.

## Using with Nylo

Register the interceptor on your API service:

```dart
class ApiService extends NyApiService {
  ApiService({BuildContext? buildContext})
      : super(buildContext, decoders: modelDecoders);

  @override
  String get baseUrl => getEnv('API_BASE_URL');

  @override
  Map<Type, Interceptor> get interceptors => {
        ...super.interceptors,
        DejaJsonInterceptor: DejaJsonInterceptor(dictionary: dictionary),
      };
}
```

Everything else — `network<User>()`, decoders, caching — keeps working
unchanged, just with far smaller payloads on the wire.

## Options

```dart
DejaJsonInterceptor(
  dictionary: dictionary,        // the trained dictionary (null = mode "z" only)
  advertise: true,               // add the request header (default true)
  modes: 'dz',                   // advertised modes; defaults to the platform's best
  rewriteContentType: true,      // report application/json after decoding (default true)
  requestHeader: 'X-Deja-Json',  // must match the server's dejajson.request_header
  codec: DejaJsonCodec(),        // swap in a configured codec if needed
)
```

Notes:

- Envelopes are binary, so for JSON requests the interceptor fetches bytes
  and rebuilds the response itself — plain-JSON and DejaJson servers both
  come out as ordinary decoded JSON. Requests with `ResponseType.bytes`,
  `stream` or `plain` are never advertised for and never touched.
- A corrupt envelope (or one for a dictionary you don't hold) surfaces as a
  `DioException` (`badResponse`) whose `error` is a
  `DejaJsonFormatException`, rather than silently handing your app garbage.
- If you call the API from browsers as well, remember to whitelist
  `X-Deja-Json` in the server's CORS `allowed_headers`.

## Manual use

The codec works without Dio — websockets, cached blobs, isolates:

```dart
const codec = DejaJsonCodec();

final data = codec.decode(envelopeBytes, dictionary: dictionary);
final envelope = codec.encode(data, dictionary: dictionary); // symmetric
```

## Wire format (v1)

```
byte 0–1  magic "DJ"
byte 2    format version (0x01)
byte 3    mode — "d" (zlib + shared dictionary) or "z" (zlib)
byte 4+   zlib stream (RFC 1950) of the minified UTF-8 JSON document
```

Sent with content type `application/vnd.dejajson`. zlib framing is
deliberate: the stream embeds an Adler-32 of the dictionary (so a wrong
dictionary fails loudly) and of the content (so corruption does too).

One platform caveat inherited from JavaScript, not from DejaJson: on web
builds, JSON numbers like `1.0` decode as the integer `1` — identical to how
plain JSON behaves there.

## Testing

```bash
dart test                # VM suite
dart test -p vm,chrome   # additionally runs the web-platform tests in Chrome
```

## License

MIT © [Anthony Gordon](https://nylo.dev)
