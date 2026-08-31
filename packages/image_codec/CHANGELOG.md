## 0.1.0

Initial release. Extracts NovelGlide's `ImageProcessor` into a shared package,
as **two** types rather than one: `ImageCodec` reads facts out of bytes
(`readImageSize`, `isPixelDataComplete`, `decodeImageSizes`) and `WebpEncoder`
turns bytes into other bytes (`encodeWebp`). Plus the `ImageSize` value object.

The split is not cosmetic. The two halves have different dependencies
(`dart:ui` versus `package:image` + a native plugin), different failure modes,
and different testability: every read is exercised by the unit suite, while
nothing in the encoder runs under `flutter test` at all — no platform
compressor is registered there. As one file, mutation testing scored 41%,
which reads as "under-tested" and actually meant "one well-tested half
averaged with one unreachable half". As two: 100% and 32%, both true.

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

**`encodeWebp` resizes**, and the parameters are a FLOOR on the result rather
than a ceiling: the image shrinks by the smallest factor that brings one axis
to its limit, so 4032x3024 at the defaults comes back 1920x1440 — height 360px
*above* the 1080 limit. `flutter_image_compress`'s `minWidth`/`minHeight` names
are therefore correct, and are passed through unchanged rather than renamed;
the defaults are stated explicitly at the call site so the transform is visible.

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

Known limitations are in the README: `webp_encoder.dart` being structurally
unmeasurable by the unit suite, the passthrough's inability to detect a
wrong-but-plausible native decode, `ImageDecodeException` currently having no
thrower, and one engine handle — `ui.ImmutableBuffer` — whose release cannot
be asserted at all, because `base class` forbids a test implementing it.

The standing rules a future editor must not break — the one-file `dart:ui`
surface, prevent-don't-catch, keeping the two types separate, and why the
factory seam is not test cruft — are in this package's `CLAUDE.md`.
