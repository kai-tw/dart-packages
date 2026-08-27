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
