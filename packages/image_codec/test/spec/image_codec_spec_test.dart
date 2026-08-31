// Spec-derived tests for `package:image_codec`.
//
// This package has no Notion product/design plan (a shared Dart/Flutter
// package inside a pub workspace, not a feature in the app) — the spec these
// tests pin to is the package's own documented contract: the doc comments on
// `ImageCodec` / `EngineImageBoundary` / `ImageCodecException`. Ownership
// boundary: `test/image_codec_test.dart` (contract-derived, not owned here)
// already pins the basic shape of every method — a valid image, an
// unreadable-bytes null, a truncated-file boundary, the exception type
// hierarchy. This file does not re-pin any of that; it goes deeper on the two
// properties the spec singles out as load-bearing:
//
//   1. readImageSize / isPixelDataComplete NEVER throw — a much wider
//      error-guessing sweep than the three cases the contract file covers.
//   2. decodeImageSizes OMITS unreadable entries rather than degrading them
//      — the batch "vanish, don't degrade" consequence, demonstrated as the
//      scenario the doc comment actually describes.
//
// It also carries one spec-conformance test for the unified-exception
// contract on `encodeWebp` that is currently RED against the shipped code —
// see the `skip:` reason on it, and the BUG note in the hand-back.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image_codec/image_codec.dart';

/// Encodes a real PNG through the engine at test time.
///
/// Copied from `test/image_codec_test.dart` per this file's brief.
/// Deliberately not a hand-written byte array — see that file's doc comment
/// for why a hand-built header is not a valid stand-in for a real decoder's
/// input.
Future<Uint8List> _encodePng(int width, int height) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF336699),
  );
  final ui.Image image = await recorder.endRecording().toImage(width, height);
  final ByteData bytes = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

/// Encodes a real, pixel-noisy PNG through the engine at test time.
///
/// A flat-color rect (as `_encodePng` draws) compresses so well that its
/// IDAT payload can be only tens of bytes — too small to safely carve a
/// corruption window out of without risking the IHDR/IEND chunks either
/// side of it. This draws a checkerboard of distinct colors instead, so the
/// compressed pixel stream is comfortably larger than the fixed-size chunks
/// around it. Still a real `dart:ui` encode, not a hand-assembled byte array
/// — only the pattern painted onto the canvas differs from `_encodePng`.
Future<Uint8List> _encodeNoisyPng(int width, int height) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  final math.Random random = math.Random(7);
  const int cell = 4;
  for (int y = 0; y < height; y += cell) {
    for (int x = 0; x < width; x += cell) {
      canvas.drawRect(
        ui.Rect.fromLTWH(
          x.toDouble(),
          y.toDouble(),
          cell.toDouble(),
          cell.toDouble(),
        ),
        ui.Paint()
          ..color = ui.Color.fromARGB(
            255,
            random.nextInt(256),
            random.nextInt(256),
            random.nextInt(256),
          ),
      );
    }
  }
  final ui.Image image = await recorder.endRecording().toImage(width, height);
  final ByteData bytes = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

void main() {
  // Plain `test()` only — never `testWidgets`. Per this file's brief:
  // `testWidgets` rewrites a throw in its body into a generic framework
  // failure, and awaiting real engine work inside its guarded zone deadlocks
  // against `pumpWidget`'s async guard, surfacing as a ten-minute timeout
  // rather than a failed assertion.
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
    'spec: readImageSize and isPixelDataComplete NEVER throw, for any bytes',
    () {
      final List<({String name, Future<Uint8List> Function() build})>
      unreadableFixtures =
          <({String name, Future<Uint8List> Function() build})>[
            (name: 'all-zero bytes', build: () async => Uint8List(128)),
            (
              name: 'all-0xFF bytes',
              build: () async =>
                  Uint8List.fromList(List<int>.filled(128, 0xFF)),
            ),
            (
              name: 'a single byte',
              build: () async => Uint8List.fromList(<int>[0x00]),
            ),
            (
              name: 'a JPEG SOI marker with nothing after it',
              // JPEG's own two-byte start-of-image marker — a valid signature
              // for a DIFFERENT format, the JPEG analogue of the existing
              // contract file's "PNG signature, nothing after" case: enough to
              // look like an image to a signature sniffer, not enough for a
              // decoder to read a size from.
              build: () async => Uint8List.fromList(<int>[0xFF, 0xD8]),
            ),
            (
              name: 'a WebP RIFF/WEBP header with no VP8 chunk after it',
              build: () async => Uint8List.fromList(<int>[
                0x52, 0x49, 0x46, 0x46, // 'RIFF'
                0x00, 0x00, 0x00, 0x00, // chunk size — left unset
                0x57, 0x45, 0x42, 0x50, // 'WEBP'
              ]),
            ),
            (
              name: 'a large buffer of noise',
              build: () async {
                final math.Random random = math.Random(1234);
                return Uint8List.fromList(
                  List<int>.generate(20000, (_) => random.nextInt(256)),
                );
              },
            ),
            (
              name:
                  "a real PNG with its signature corrupted (so it isn't "
                  'recognized as a PNG, or anything else, at all)',
              build: () async {
                final Uint8List whole = await _encodePng(20, 20);
                final Uint8List corrupted = Uint8List.fromList(whole);
                corrupted[1] ^= 0xFF; // inside PNG's fixed 8-byte magic number
                return corrupted;
              },
            ),
          ];

      for (final ({String name, Future<Uint8List> Function() build}) fixture
          in unreadableFixtures) {
        test('[error guessing] ${fixture.name} is never readable, and '
            'reading it never throws', () async {
          final Uint8List bytes = await fixture.build();

          await expectLater(
            ImageCodec.readImageSize(bytes),
            completion(isNull),
          );
          await expectLater(
            ImageCodec.isPixelDataComplete(bytes),
            completion(isFalse),
          );
        });
      }

      test(
        '[boundary] a real PNG with its pixel data corrupted (not '
        'truncated) still reports its header dimensions, but is NOT '
        'pixel-complete — a different corruption shape than truncation, '
        'and both must be tolerated without throwing',
        () async {
          final Uint8List whole = await _encodeNoisyPng(120, 120);
          expect(
            whole.length,
            greaterThan(300),
            reason:
                'the corruption window below assumes the encoded IDAT is '
                'well past the ~33-byte signature+IHDR prefix and well '
                'before the trailing 12-byte IEND chunk; a suspiciously '
                'small encoding here means that assumption needs '
                're-checking, not that the corruption below is still '
                'landing inside IDAT',
          );
          final Uint8List corrupted = Uint8List.fromList(whole);
          const int windowStart = 80;
          final int windowEnd = math.min(
            corrupted.length - 20,
            windowStart + 24,
          );
          for (int i = windowStart; i < windowEnd; i++) {
            corrupted[i] ^= 0xFF;
          }

          await expectLater(
            ImageCodec.readImageSize(corrupted),
            completion(const ImageSize(width: 120, height: 120)),
          );
          await expectLater(
            ImageCodec.isPixelDataComplete(corrupted),
            completion(isFalse),
          );
        },
      );

      test(
        '[error guessing] a real PNG with garbage appended after its end '
        'is still read correctly — trailing bytes are not the pixel '
        'stream',
        () async {
          final Uint8List whole = await _encodePng(24, 36);
          final Uint8List withTrailer = Uint8List.fromList(<int>[
            ...whole,
            ...List<int>.filled(500, 0xAB),
          ]);

          await expectLater(
            ImageCodec.readImageSize(withTrailer),
            completion(const ImageSize(width: 24, height: 36)),
          );
          await expectLater(
            ImageCodec.isPixelDataComplete(withTrailer),
            completion(isTrue),
          );
        },
      );

      test(
        '[scenario] concurrent reads of different images do not '
        'cross-contaminate results — each call resolves independently of '
        'any other in flight',
        () async {
          final List<Uint8List> images = await Future.wait(
            <Future<Uint8List>>[
              _encodePng(11, 21),
              _encodePng(33, 43),
              _encodePng(55, 65),
              _encodePng(77, 87),
            ],
          );

          final List<ImageSize?> results = await Future.wait(
            images.map(ImageCodec.readImageSize),
          );

          expect(results, <ImageSize?>[
            const ImageSize(width: 11, height: 21),
            const ImageSize(width: 33, height: 43),
            const ImageSize(width: 55, height: 65),
            const ImageSize(width: 77, height: 87),
          ]);
        },
      );
    },
  );

  group(
    'spec: decodeImageSizes OMITS an unreadable entry rather than '
    'degrading it — the batch blast radius',
    () {
      test(
        '[decision table] omission does not depend on position — good and '
        'bad entries interleaved each resolve independently, including a '
        'non-ASCII key',
        () async {
          final Uint8List good1 = await _encodePng(10, 20);
          final Uint8List good2 = await _encodePng(30, 40);
          final Uint8List good3 = await _encodePng(50, 60);
          final Uint8List bad = Uint8List.fromList(
            List<int>.generate(40, (int i) => 200 - i),
          );

          final Map<String, ImageSize> result =
              await ImageCodec.decodeImageSizes(<String, Uint8List>{
                'first-bad': bad,
                'first-good': good1,
                'middle-bad': bad,
                '中間-good': good2,
                'last-good': good3,
                'last-bad': bad,
              });

          expect(result.keys.toSet(), <String>{
            'first-good',
            '中間-good',
            'last-good',
          });
          expect(result['first-good'], const ImageSize(width: 10, height: 20));
          expect(result['中間-good'], const ImageSize(width: 30, height: 40));
          expect(result['last-good'], const ImageSize(width: 50, height: 60));
        },
      );

      test(
        '[scenario] the documented consequence: a consumer that builds its '
        'output by walking the RESULT map loses the image silently, while '
        'a consumer that walks its own INPUT keys can detect the gap and '
        'degrade instead',
        () async {
          final Uint8List good1 = await _encodePng(15, 25);
          final Uint8List good2 = await _encodePng(35, 45);
          final Uint8List bad = Uint8List(0);
          final Map<String, Uint8List> input = <String, Uint8List>{
            'cover': good1,
            'corrupt-thumb': bad,
            'author-photo': good2,
          };

          final Map<String, ImageSize> result =
              await ImageCodec.decodeImageSizes(input);

          // Consumer A iterates the RESULT map to build its output — three
          // images went in, two come out, with nothing here to say
          // 'corrupt-thumb' ever existed. This IS the "vanish" the doc
          // comment warns about, not a hypothetical reading of it.
          expect(result.length, 2);
          expect(result.keys, isNot(contains('corrupt-thumb')));

          // Consumer B iterates its own INPUT keys and looks each one up in
          // the result — the only shape that can tell "dropped" apart from
          // "never asked for", per the doc comment's stated workaround.
          final List<String> missing = input.keys
              .where((String key) => !result.containsKey(key))
              .toList();
          expect(missing, <String>['corrupt-thumb']);
        },
      );

      test(
        '[boundary] every entry unreadable resolves to an empty map — not '
        'an error, and not a map of placeholder values',
        () async {
          final Map<String, Uint8List> allBad = <String, Uint8List>{
            'a': Uint8List(0),
            'b': Uint8List.fromList(<int>[0, 1, 2]),
            'c': Uint8List.fromList(List<int>.generate(20, (int i) => i)),
          };

          expect(await ImageCodec.decodeImageSizes(allBad), isEmpty);
        },
      );

      test(
        '[FMEA-lite] entries that share the identical byte buffer resolve '
        'independently per key — no state leaks between loop iterations',
        () async {
          final Uint8List shared = await _encodePng(12, 34);

          final Map<String, ImageSize> result =
              await ImageCodec.decodeImageSizes(<String, Uint8List>{
                'x': shared,
                'y': shared,
              });

          expect(result['x'], const ImageSize(width: 12, height: 34));
          expect(result['y'], const ImageSize(width: 12, height: 34));
        },
      );
    },
  );

  group(
    'spec: encodeWebp — the unified-exception contract must hold even when '
    'no platform compressor is registered',
    () {
      // Reach note (Iron Law 1): the OTHER half of encodeWebp's documented
      // behavior — "tries a direct native passthrough, verifies the output
      // by reading its dimensions back, falls back to decode->PNG->compress"
      // — is not reachable from this suite at all, on this host, by any
      // amount of platform-channel mocking. `FlutterImageCompressValidator
      // .checkSupportPlatform` hard-gates `CompressFormat.webp` on
      // `Platform.isAndroid || Platform.isIOS` (see
      // flutter_image_compress_platform_interface's validator.dart) BEFORE
      // any method channel is touched, and this suite runs on the Dart VM
      // host (neither). Exercising the passthrough/fallback split needs a
      // real iOS or Android target — `integration_test/`, not `test/`.
      test(
        '[FMEA-lite] a non-empty input still throws ImageCodecException, '
        "never the platform-interface's own UnimplementedError",
        () async {
          // This was written red and skipped: with no platform compressor
          // registered — the deterministic state of every plain `flutter
          // test` run of a package, and the real state on an unsupported
          // host — `FlutterImageCompressPlatform.instance` stays
          // `UnsupportedFlutterImageCompress`, whose `compressWithList`
          // throws `UnimplementedError`. That `Error` escaped `encodeWebp`
          // untouched: exactly the shape this package exists to keep a
          // caller from having to know about.
          //
          // It passes now because `encodeWebp` checks the platform BEFORE
          // calling rather than catching afterwards. `UnimplementedError`
          // and `UnsupportedError` are both on `avoid_catching_error`'s
          // fixed list, so no catch clause could have fixed this without
          // breaking the house lint — prevention was the only route, and
          // this test is what proves it holds.
          final Uint8List png = await _encodePng(8, 8);

          await expectLater(
            ImageCodec.encodeWebp(png),
            throwsA(isA<ImageCodecException>()),
          );
        },
      );
    },
  );
}
