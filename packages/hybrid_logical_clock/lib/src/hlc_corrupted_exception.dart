import 'hlc_decode_exception.dart';

/// Raised when an HLC's values are outside what a real clock could produce.
///
/// Separate from [HlcDecodeException]: the string parsed fine, but the values
/// it carries are not plausible, which is a different failure to report.
class HlcCorruptedException implements Exception {
  const HlcCorruptedException(this.message);

  final String message;

  @override
  String toString() => 'HlcCorruptedException: $message';
}
