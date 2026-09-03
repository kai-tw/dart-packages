/// A [TimeSource] could not produce a sample.
///
/// `ClockAnchorService.refresh` catches exactly this and nothing wider: a
/// source that cannot be reached is an ordinary, expected condition, while
/// anything else coming out of a source is a defect and must keep
/// propagating.
///
/// Concrete rather than abstract, and throwable as it stands. That is the
/// contract for [CallbackTimeSource] in particular — an app wrapping its own
/// transport translates a network failure into this, because the package
/// cannot catch a type it does not know about. The subclasses in this package
/// exist to name a *specific* failure, not to make the base unusable.
class TimeSourceException implements Exception {
  /// [sourceId] identifies which source failed, so a caller inspecting
  /// `ClockAnchorService.lastRefreshFailures` can tell them apart.
  const TimeSourceException(this.sourceId, this.reason);

  /// The failing source's id.
  final String sourceId;

  /// What went wrong, in terms that carry no remote payload.
  ///
  /// Messages here must stay free of bytes read off the network. They reach
  /// logs, and on both consuming apps a log message travels verbatim to a
  /// crash reporter.
  final String reason;

  @override
  String toString() => '$runtimeType($sourceId): $reason';
}
