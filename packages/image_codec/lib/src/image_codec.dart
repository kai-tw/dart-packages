import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

import 'engine_image_boundary.dart';
import 'image_codec_exception.dart';
import 'image_size.dart';

/// Reads facts out of image bytes, and turns image bytes into other image
/// bytes.
///
/// Bytes in, bytes out — deliberately. Taking a decoded `img.Image` would put
/// `package:image` in every caller's imports, which is what this package
/// exists to stop: a consumer should not have to pick a decoding library, nor
/// know that three different ones fail in three different shapes underneath.
///
/// Every operation here is a pure function of its input bytes, so there is no
/// instance to hold: `abstract final` because the language then refuses
/// `ImageCodec()` outright, rather than a private constructor blocking it as
/// an afterthought.
///
/// **This deliberately does not offer an injectable instance.** Dependency
/// injection buys a seam where behaviour varies — configuration, state, a
/// substitutable implementation. None of those exist here: the answer depends
/// only on the bytes handed in. There is deliberately no fake point either:
/// what a test would want to substitute is the platform decoder itself, and
/// that is the engine, not a collaborator this package could hand you. A
/// consumer whose container wants a registered object should wrap this in its
/// own adapter, where that decision belongs.
///
/// **ROOT ISOLATE ONLY.** Every read here goes through the engine, and the
/// engine's decoder registry is reachable only from the root isolate. Calling
/// [readImageSize],
/// [isPixelDataComplete] or [decodeImageSizes] from a spawned isolate does not
/// throw a clear error — it fails the decode, which this package reports as
/// "not a readable image". A perfectly good image comes back `null`.
///
/// That is the one failure mode here that is silent, and it is why this
/// warning is at the top of the type rather than buried on a method. If you
/// are replacing a pure-Dart header parser with this package, check every call
/// site for `Isolate.spawn` / `compute()` first: the old code was
/// isolate-safe and this is not, so a call that reads as unchanged changes
/// meaning. A comment claiming "isolate-safe" beside such a call is describing
/// the code being replaced.
abstract final class ImageCodec {
  /// The dimensions declared in [bytes]' header, or `null` when the bytes are
  /// not a readable image.
  ///
  /// **Root isolate only** — see the note on [ImageCodec]. From a spawned
  /// isolate this returns `null` for images that are perfectly readable.
  ///
  /// Does **not** prove the pixel data is complete; a truncated file reports
  /// its declared dimensions. Use [isPixelDataComplete] when that matters.
  static Future<ImageSize?> readImageSize(Uint8List bytes) =>
      EngineImageBoundary.readSize(bytes);

  /// Whether [bytes] carries a complete, decodable pixel stream.
  ///
  /// **Root isolate only** — see the note on [ImageCodec].
  static Future<bool> isPixelDataComplete(Uint8List bytes) =>
      EngineImageBoundary.isPixelDataComplete(bytes);

  /// Dimensions for a batch of images, keyed as the input was.
  ///
  /// **An entry whose dimensions cannot be read is omitted from the result** —
  /// and a missing key means the caller drops that image entirely, not that it
  /// renders without dimensions. If you build your output by iterating this
  /// map, an unreadable input silently vanishes rather than degrading. A
  /// caller that wants degrade-not-drop must iterate its own input and look up
  /// each key here.
  ///
  /// Reads run on the calling isolate: the engine's decoder registry is only
  /// reachable from the root isolate, and a header read does not occupy the
  /// event loop long enough for a `compute()` hop to buy anything.
  static Future<Map<String, ImageSize>> decodeImageSizes(
    Map<String, Uint8List> images,
  ) async {
    final Map<String, ImageSize> sizes = <String, ImageSize>{};
    for (final MapEntry<String, Uint8List> entry in images.entries) {
      final ImageSize? size = await readImageSize(entry.value);
      if (size != null) {
        sizes[entry.key] = size;
      }
    }
    return sizes;
  }

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
    if (direct != null && await readImageSize(direct) != null) {
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
    if (!await isPixelDataComplete(bytes)) {
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
