/// Raised when an HLC string cannot be decoded.
///
/// The message deliberately carries only positions and lengths, never the
/// input itself: HLC strings arrive from cloud storage, so they are
/// attacker-influenced, and interpolating one into a logged message would
/// round-trip those bytes into Crashlytics.
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

/// Raised by [Mutex] when the mutex has been disposed.
///
/// Callers awaiting `lock()` get this rather than hanging forever when the
/// owner shuts down mid-wait.
class MutexDisposedException implements Exception {
  const MutexDisposedException();

  @override
  String toString() => 'MutexDisposedException';
}
