import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:meta/meta.dart';

import 'image_size.dart';

/// The only file in this package that touches `dart:ui`, and the only one
/// exempted from `avoid_catching_base_exception`.
///
/// **Keep it that way.** The exemption is declared in `dart_lints.yaml` as an
/// area whose path glob names this single file, so the exemption is exactly as
/// wide as this file is. Moving an engine call into a second file widens a
/// lint exemption rather than merely reorganising code — the glob would have to
/// grow to match, and `on Exception` would become legal somewhere it is not
/// today.
///
/// The exemption is unavoidable, not a convenience. Every `dart:ui` native
/// call routes failure through one generic bridge — `_futurize` in the engine's
/// `painting.dart`, which hardcodes `throw Exception('operation failed')` — so
/// there is no narrower type in existence to catch. There is also no predicate
/// to ask beforehand ("are these bytes decodable?"), so the condition cannot be
/// detected without attempting it. A magic-number pre-filter does not remove
/// the need: it can reject "not an image at all", but not "valid signature,
/// corrupt body", which is the case [isPixelDataComplete] exists for.
///
/// Nothing here throws. Unreadable bytes are an ordinary, expected answer for
/// a cover a user picked or an image extracted from an EPUB, so failure is
/// reported as `null`/`false` rather than as an exception the caller would
/// have to catch on every read.
abstract final class EngineImageBoundary {
  /// How an [ui.ImageDescriptor] is obtained. Overridable **only** so a test
  /// can hand back a fake and assert it was disposed.
  ///
  /// This seam exists for exactly one reason, and it is worth stating plainly
  /// rather than dressing up: releasing an engine handle is a correctness
  /// property with no observable effect. Leaking one costs native memory the
  /// Dart heap cannot see, so nothing in a test run gets slower, louder or
  /// redder when a `dispose()` goes missing — mutation testing deleted each of
  /// these calls in turn and every other test still passed. A code review
  /// catches it once, on the day someone reads it; a fake that records
  /// `dispose()` catches it every time, including the edit six months from now
  /// that nobody reviews as carefully.
  ///
  /// `ui.ImageDescriptor.encoded` is a static factory and
  /// `ui.instantiateImageCodec` a top-level function, so neither can be
  /// substituted without a seam like this. `dart:ui` reaches for the same
  /// device itself — `ui.Image.onCreate` / `onDispose` are static, mutable and
  /// exist so a leak tracker can observe lifecycle it otherwise could not.
  ///
  /// Restore it in `addTearDown`. It is process-global.
  @visibleForTesting
  static Future<ui.ImageDescriptor> Function(ui.ImmutableBuffer)
  descriptorFactory = ui.ImageDescriptor.encoded;

  /// How a [ui.Codec] is obtained. Overridable only for the reason given on
  /// [descriptorFactory].
  @visibleForTesting
  static Future<ui.Codec> Function(
    Uint8List, {
    int? targetHeight,
    int? targetWidth,
  })
  codecFactory = ui.instantiateImageCodec;

  /// Puts both factories back to the real engine. Call from `addTearDown`.
  @visibleForTesting
  static void resetFactories() {
    descriptorFactory = ui.ImageDescriptor.encoded;
    codecFactory = ui.instantiateImageCodec;
  }

  /// The dimensions declared in [bytes]' header, without decoding pixels.
  ///
  /// `null` when the engine cannot read them at all.
  ///
  /// A header read does **not** prove the pixel stream is complete — a
  /// truncated file reports its declared dimensions perfectly happily, because
  /// nothing ever walks past the header. [isPixelDataComplete] is the check
  /// for that, and it is a genuinely different operation rather than a
  /// stricter flavour of this one.
  static Future<ImageSize?> readSize(Uint8List bytes) async {
    try {
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
        bytes,
      );
      try {
        final ui.ImageDescriptor descriptor = await descriptorFactory(
          buffer,
        );
        try {
          return ImageSize(
            width: descriptor.width,
            height: descriptor.height,
          );
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
    } on Exception {
      // The engine's only failure signal — see the class doc. Nothing narrower
      // exists to catch, and the caller's contract is `null`, not a throw.
      return null;
    }
  }

  /// Whether [bytes] carries a complete, decodable pixel stream.
  ///
  /// Decodes to a 1x1 target: that walks far enough into the stream to fail on
  /// a truncated or corrupt body, at the cost of materialising one pixel
  /// instead of the whole bitmap. Reading the header cannot answer this — the
  /// header is intact in exactly the case this catches.
  static Future<bool> isPixelDataComplete(Uint8List bytes) async {
    try {
      final ui.Codec codec = await codecFactory(
        bytes,
        targetWidth: 1,
        targetHeight: 1,
      );
      try {
        final ui.FrameInfo frame = await codec.getNextFrame();
        frame.image.dispose();
        return true;
      } finally {
        codec.dispose();
      }
    } on Exception {
      return false;
    }
  }
}
