import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

import 'image_codec.dart';
import 'image_codec_exception.dart';

/// Re-encodes image bytes as WebP.
///
/// Split from [ImageCodec] rather than sharing its class, because the two are
/// unrelated jobs that happen to take the same input. Reading facts out of
/// bytes and turning bytes into other bytes have different dependencies
/// (`dart:ui` versus `package:image` + a native plugin), different failure
/// modes, and — decisively — different testability: every read is exercised by
/// the unit suite, while nothing here runs under `flutter test` at all,
/// because no platform compressor is registered in that environment.
///
/// Keeping them in one file made that second fact invisible. Mutation testing
/// scored the combined file at 41%, which reads as "under-tested" when it
/// actually meant "one well-tested half averaged with one unreachable half".
/// Separated, each number says something true: the read half is measurable and
/// high, this file is honestly zero until an `integration_test/` runs on a real
/// device.
abstract final class WebpEncoder {
  /// Re-encodes [bytes] as WebP.
  ///
  /// **Android and iOS only.** `flutter_image_compress` hard-gates WebP to
  /// those two platforms and throws `UnsupportedError` everywhere else, and
  /// when no platform implementation is registered at all — which is the state
  /// of every plain `flutter test` run — its default stub throws
  /// `UnimplementedError`. Both are `Error` subtypes, so neither can be caught
  /// without violating this repo's own `avoid_catching_error`. This method
  /// therefore **checks the platform before calling** rather than catching
  /// afterwards: prevention converts a whole class of uncatchable `Error` into
  /// this package's own [ImageEncodeException] without a catch clause anywhere.
  ///
  /// **Silently resizes when the source is large.** The compressor's
  /// `minWidth`/`minHeight` are misleadingly named: they are an upper bound, so
  /// a 4032x3024 photo comes back 1920x1440 at the plugin's defaults. Those
  /// bounds are passed explicitly here from [maxWidth]/[maxHeight] so the
  /// transform is the caller's decision rather than a default they never saw.
  /// `readImageSize` before and after will differ whenever the source exceeds
  /// them — that is the contract, not a bug.
  ///
  /// The passthrough hands the source bytes straight to the native compressor,
  /// skipping a decode and a PNG re-encode when the platform already reads that
  /// format. Its result is verified by reading the dimensions back, because the
  /// Dart layer cannot tell us whether a *native* decoder accepted odd input
  /// and produced a wrong image. That check catches "not an image at all"; it
  /// cannot catch correct-sized-but-wrong-pixels, which would need a real
  /// device to establish.
  ///
  /// Throws [ImageEncodeException] on an unsupported platform, on empty or
  /// undecodable bytes, and when neither encode path produces output.
  static Future<Uint8List> encodeWebp(
    Uint8List bytes, {
    int quality = 85,
    int maxWidth = 1920,
    int maxHeight = 1080,
  }) async {
    if (bytes.isEmpty) {
      throw const ImageEncodeException('cannot encode empty bytes');
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw ImageEncodeException(
        'WebP encoding is available on Android and iOS only; this is '
        '${Platform.operatingSystem}',
      );
    }
    final Uint8List? direct = await _compressOrNull(
      bytes,
      quality,
      maxWidth,
      maxHeight,
    );
    if (direct != null && await ImageCodec.readImageSize(direct) != null) {
      return direct;
    }
    return _reEncodeViaPng(bytes, quality, maxWidth, maxHeight);
  }

  /// Compresses [bytes] to WebP, or `null` when the compressor rejects them.
  ///
  /// `CompressError` is caught by name. It extends `Error`, not `Exception` —
  /// the package labelling a runtime condition ("the image is empty", "compress
  /// returned no data") as a programming mistake — so letting it propagate
  /// would hand callers an `Error` for an input they cannot control. Catching
  /// it by its own name is narrow enough that it stays legal: the lint that
  /// forbids catching errors matches a fixed list of `dart:core` error types,
  /// and this is not one of them.
  static Future<Uint8List?> _compressOrNull(
    Uint8List bytes,
    int quality,
    int maxWidth,
    int maxHeight,
  ) async {
    try {
      return await FlutterImageCompress.compressWithList(
        bytes,
        format: CompressFormat.webp,
        quality: quality,
        // Named `min*` by the plugin, but they bound the output from ABOVE —
        // its own FAQ is titled "why is minWidth/minHeight named that if it
        // acts like a max". Passed explicitly rather than defaulted so the
        // resize is a decision this package made on the caller's behalf and
        // documented, not one the plugin made silently.
        minWidth: maxWidth,
        minHeight: maxHeight,
      );
    } on CompressError {
      // Caught by name, and legal: `CompressError` extends `Error` but is not
      // in `avoid_catching_error`'s fixed list of `dart:core` error types. The
      // two Error shapes that ARE on that list — `UnsupportedError` and
      // `UnimplementedError` — are prevented by the platform guard in
      // [encodeWebp] rather than caught here.
      //
      // Discarded deliberately on THIS path only: a passthrough rejection is
      // the expected way to learn the format needs decoding first, and the
      // fallback is about to run. The evidence is preserved where it matters —
      // [_compressOrThrow], the call that actually gives up.
      return null;
    }
  }

  /// Compresses [bytes], converting a failure into [ImageEncodeException]
  /// **with the original attached**.
  ///
  /// Separate from [_compressOrNull] because the two calls want opposite
  /// things from a failure. The passthrough wants to shrug and try the other
  /// path; this one is the end of the line, so `CompressError.code` — stable
  /// native values like `unsupported_format` / `decode_failed` / `io_failed` —
  /// has to survive into `cause`. Collapsing three failure shapes into one
  /// type must not also destroy the evidence of which one it was.
  static Future<Uint8List> _compressOrThrow(
    Uint8List bytes,
    int quality,
    int maxWidth,
    int maxHeight,
    String failureMessage,
  ) async {
    try {
      return await FlutterImageCompress.compressWithList(
        bytes,
        format: CompressFormat.webp,
        quality: quality,
        minWidth: maxWidth,
        minHeight: maxHeight,
      );
    } on CompressError catch (e) {
      throw ImageEncodeException(failureMessage, cause: e);
    }
  }

  /// The fallback: decode with `package:image`, re-encode as PNG, compress.
  ///
  /// The decode and the PNG encode run in a `compute()` isolate — they are
  /// pure CPU over bytes and would otherwise stall the caller's event loop.
  /// The compression step must **not** join them: `FlutterImageCompress` is a
  /// native plugin and cannot be sent into a Dart isolate, so moving it there
  /// fails at runtime rather than at compile time. That split is the whole
  /// reason this is two steps.
  /// `package:image` is only ever handed bytes the engine has already
  /// confirmed decode cleanly.
  ///
  /// That gate is load-bearing, not defensive tidiness. On a truncated PNG
  /// `package:image` does not throw its own `ImageException` — it throws
  /// `TypeError` (a `!` on a null frame in `png_decoder.dart`) or `RangeError`
  /// (an unguarded buffer read when the truncation lands mid-chunk). Both are
  /// `Error`s on `avoid_catching_error`'s fixed list, both cross back out of
  /// the `compute()` isolate, and neither can be caught here. And the path is
  /// reached precisely for bytes the native compressor already rejected — the
  /// malformed ones. Asking [isPixelDataComplete] first removes the input that
  /// triggers them instead of trying to catch what cannot be caught.
  static Future<Uint8List> _reEncodeViaPng(
    Uint8List bytes,
    int quality,
    int maxWidth,
    int maxHeight,
  ) async {
    if (!await ImageCodec.isPixelDataComplete(bytes)) {
      throw const ImageEncodeException(
        'the source pixel data is incomplete or corrupt, so it cannot be '
        're-encoded',
      );
    }
    final Uint8List? png = await compute<Uint8List, Uint8List?>(
      _decodeToPng,
      bytes,
    );
    if (png == null) {
      throw const ImageEncodeException(
        'the bytes could not be decoded by any available decoder',
      );
    }
    return _compressOrThrow(
      png,
      quality,
      maxWidth,
      maxHeight,
      're-encoding to WebP failed even after decoding through PNG',
    );
  }

  /// Runs inside a `compute()` isolate.
  ///
  /// Returns `null` rather than throwing on a failed decode: an exception
  /// raised here has to survive being sent across the isolate boundary, and a
  /// nullable return is the shape that cannot go wrong. The caller converts it
  /// into an [ImageEncodeException] on the other side.
  static Uint8List? _decodeToPng(Uint8List bytes) {
    try {
      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return null;
      }
      return Uint8List.fromList(img.encodePng(decoded));
    } on img.ImageException {
      return null;
    }
  }
}
