# CLAUDE.md — image_codec

## The `dart:ui` surface stays in ONE file

`engine_image_boundary.dart` is the only file here that imports `dart:ui`, and
`dart_lints.yaml` exempts **exactly that path** from
`avoid_catching_base_exception` via an area declared before `production`.

Moving an engine call into a second file does not reorganise code — it widens
a lint exemption, because the glob has to grow to match and `on Exception`
becomes legal somewhere it is not today. If a third engine operation arrives
(a bounded decode, say), it goes in this file or it does not use the engine.

The exemption is unavoidable, not a convenience: every `dart:ui` native call
routes failure through one `_futurize` bridge that hardcodes
`throw Exception('operation failed')` (sky_engine `painting.dart:9211`). There
is no narrower type in existence and no predicate to ask beforehand.

**The glob cannot rot silently** — verified by pointing it at a nonexistent
path, which makes `dart_lints` refuse to run at all ("area matches no Dart
file"). Renaming the file breaks the build rather than quietly dropping the
exemption.

## Prevent the uncatchable; do not reach for a catch

Three failure sources sit under this package and two of them cannot be caught
in this repo:

| source | throws | catchable here? |
|---|---|---|
| `dart:ui` | bare `Exception` | yes, in the boundary file only |
| `package:image` | `ImageException implements Exception` | yes, by name |
| `flutter_image_compress` | `CompressError extends Error` | yes — not on the lint's list |
| same, wrong platform | `UnsupportedError` | **no** |
| same, no registration | `UnimplementedError` | **no** |
| `package:image`, truncated input | `TypeError` / `RangeError` | **no** |

The last three are on `avoid_catching_error`'s fixed `dart:core` list, so no
catch clause could ever be written for them. That is why `WebpEncoder` checks
`Platform.isAndroid`/`isIOS` **before** calling, and why `_reEncodeViaPng`
asks `isPixelDataComplete` **before** handing bytes to `package:image`.

**Do not "fix" a future failure of this kind by widening a catch.** Find the
condition and guard it. If a guard is genuinely impossible, that is a finding
for the founder, not grounds to loosen the lint.

## `ImageCodec` and `WebpEncoder` stay separate

They were one class and were split. Reading facts out of bytes and turning
bytes into other bytes have different dependencies (`dart:ui` versus
`package:image` + a native plugin), different failure modes, and — the reason
that settled it — different testability: every read is exercised by the unit
suite, while **nothing in `webp_encoder.dart` runs under `flutter test` at
all**, because no platform compressor is registered in that environment.

Combined, mutation testing scored the single file at 41%, which reads as
"under-tested" and actually meant "one well-tested half averaged with one
unreachable half". Separated: 100% and 32%, both true. Merging them back
re-hides that.

`webp_encoder.dart`'s 32% will not improve by writing more unit tests. Every
survivor sits after the platform guard. Only `integration_test/` on a real
device moves it.

## Test rules that are not style preferences

- **Fixtures are encoded through `dart:ui` at test time**, never hand-built
  byte arrays. The implementation this package replaced parsed headers itself,
  so a 24-byte hand-made "PNG" was a valid input for it — it is not one for a
  real decoder. Hand-built byte lists are legal **only** as negative fixtures
  asserted to `null`/`false`.
- **Plain `test()`, never `testWidgets`.** Measured: `testWidgets` rewrites a
  throw in its body into a generic framework failure, and awaiting real engine
  work inside its guarded zone deadlocks against `pumpWidget`'s async guard —
  surfacing as a ten-minute timeout rather than a failed assertion.

## The factory seam is load-bearing, not test cruft

`EngineImageBoundary.descriptorFactory` / `codecFactory` exist so tests can
assert engine handles are released. Releasing a handle has **no observable
effect** — a leak costs native memory the Dart heap cannot see — so mutation
testing deleted all four `dispose()` calls and every test still passed.

Three are now pinned (`ui.Image` via its static `onDispose` hook,
`ImageDescriptor` and `Codec` via fakes through the seam).
`ui.ImmutableBuffer` is a `base class`, so the language forbids faking it and
that one mutant survives permanently — it is named in the README.

Deleting the seam as "only tests use it" reopens two of those three. A code
review catches a missing `dispose()` once, on the day someone reads it; the
fake catches it every time.
