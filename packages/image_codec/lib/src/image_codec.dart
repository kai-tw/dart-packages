import 'package:flutter/foundation.dart';

import 'engine_image_boundary.dart';
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
}
