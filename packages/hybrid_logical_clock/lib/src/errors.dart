/// Raised when an HLC string cannot be decoded.
///
/// The message deliberately carries only positions and lengths, never the
/// input itself: HLC strings arrive from storage the app does not control, so
/// they are attacker-influenced, and interpolating one into a logged message
/// would round-trip those bytes into whatever crash reporter is attached.
class HlcDecodeException implements Exception {
  const HlcDecodeException(this.message);

  final String message;

  @override
  String toString() => 'HlcDecodeException: $message';
}

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
