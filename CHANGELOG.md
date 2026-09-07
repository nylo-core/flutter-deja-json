# Changelog

## 0.1.1 — 2026-09-07

### Changed

- Bumped `dio` constraint to `^5.11.1`.
- Bumped `test` dev dependency constraint to `^1.32.0`.

## 0.1.0 — 2026-08-06

Initial release.

- DejaJson wire format v1: a 4-byte binary envelope over a zlib (RFC 1950)
  stream, in dictionary (`d`) and plain (`z`) modes.
- `DejaJsonInterceptor` for Dio: advertises `X-Deja-Json` (with the
  dictionary id when one is loaded), fetches bytes transparently, and
  restores plain JSON responses — including error responses — exactly as Dio
  would have produced them.
- `DejaJsonDictionary` for loading the dictionary trained by
  `php artisan dejajson:train` (shipped as an app asset).
- `DejaJsonCodec` for manual encode/decode (websockets, cached blobs,
  isolates).
- Web builds advertise nothing (zlib needs `dart:io`) and pass plain JSON
  through untouched.
- Cross-implementation test vectors shared with the `nylo/dejajson` Laravel
  package.
