## 0.1.0

Initial release. Extracts NovelGlide's `ImageProcessor` into a shared package:
`readImageSize` (header dimensions without decoding pixels),
`isPixelDataComplete` (1x1 decode proving the pixel stream is whole),
`decodeImageSizes` (the batch form), `encodeWebp` (re-encode), and the
`ImageSize` value object.

The product is the **unified exception interface**, not the individual
operations. Three libraries underneath fail in three shapes across two type
hierarchies — the engine throws a bare `Exception` with no subtype (every
`dart:ui` native call routes failure through one `_futurize` bridge that
hardcodes it), `package:image` throws `ImageException implements Exception`,
and `flutter_image_compress` throws `CompressError extends Error`. A consumer
now catches `ImageCodecException` and nothing else.

Two of those three could not be handled by catching, and the reason is worth
recording because it shaped the design:

- `dart:ui` offers no narrower type to catch and no predicate to ask first, so
  a single file — `engine_image_boundary.dart` — holds the entire engine
  surface and is the one file exempted from `avoid_catching_base_exception`.
  The exemption is a path glob naming exactly that file, declared before
  `production` in `dart_lints.yaml` so it wins the overlap. Moving an engine
  call into a second file would widen a lint exemption rather than reorganise
  code.
- `flutter_image_compress` throws `UnsupportedError` on any non-mobile platform
  and `UnimplementedError` when no platform implementation is registered. Both
  are on `avoid_catching_error`'s fixed list, so **no catch clause could have
  fixed this**. `encodeWebp` checks the platform *before* calling instead —
  prevention converts a class of uncatchable `Error` into this package's own
  exception without a catch anywhere. `package:image`'s `TypeError`/`RangeError`
  on truncated input is prevented the same way: `isPixelDataComplete` gates the
  fallback, so the decoder is never handed bytes that trigger them.

**`encodeWebp` resizes.** `flutter_image_compress`'s `minWidth`/`minHeight` are
named misleadingly — they bound the output from above — so the plugin's
defaults silently shrink a 4032x3024 photo to 1920x1440. They are now explicit
`maxWidth`/`maxHeight` parameters, documented as a transform the caller owns
rather than a default they never saw.

**Reads are root-isolate only**, and this is the one silent failure mode: from
a spawned isolate the engine's decoder registry is unreachable, the decode
fails, and that is reported as "not a readable image" — a good image returns
`null`. Consumers replacing a pure-Dart header parser must check every call
site for `Isolate.spawn`/`compute()` first; the code being replaced was
isolate-safe and this is not.

Tests are in two halves, both green (27 tests): contract-derived under `test/`,
spec-derived under `test/spec/`. Fixtures are encoded through `dart:ui` at test
time rather than hand-assembled, because a hand-built byte stub is a valid input
for a header parser and not for a real decoder. All use plain `test()` — a
`testWidgets` body rewrites throws into generic framework failures and deadlocks
against real engine work, surfacing as a ten-minute timeout instead of a failed
assertion.

Known limitations are in the README: no unit coverage of a *successful*
`encodeWebp` (the compressor cannot run under `flutter test` at all), the
passthrough's inability to detect a wrong-but-plausible native decode, and
`ImageDecodeException` currently having no thrower.
