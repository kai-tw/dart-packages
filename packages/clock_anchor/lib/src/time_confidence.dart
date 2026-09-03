/// How much a [TimeReading] is worth, ordered weakest first.
///
/// Four states rather than a nullable `DateTime`, because the two ways of
/// having no anchor are not equivalent and the fail-closed consumers need to
/// tell them apart: a device clock with nothing known against it is a usable
/// estimate, and a device clock already caught moving backwards is not.
enum TimeConfidence {
  /// No anchor, and the device clock is not usable either — it has been
  /// caught going backwards against the watermark.
  ///
  /// Every security decision that depends on time must fail closed here.
  /// Classify that failure as **transient**, not conclusive: the correct
  /// remedy is to sample a source and retry, not to record a verdict.
  unknown,

  /// No anchor; the device clock is the only thing available and nothing has
  /// been observed against it.
  ///
  /// Ordinary on a first run and while offline. Fine for ordering and for
  /// display; not enough to expire a signature.
  deviceOnly,

  /// An anchor exists but something has happened to it — it has aged past the
  /// policy's limit, or the wall clock has moved relative to the monotonic
  /// base since it was taken (a clock change, or a sleep the tick source did
  /// not count; the two are indistinguishable and both want a fresh sample).
  staleAnchor,

  /// A fresh anchor with no discrepancy against it. The device clock has not
  /// been consulted.
  anchored,
}

/// Comparison for [TimeConfidence], so no call site reaches for `index`.
extension TimeConfidenceRank on TimeConfidence {
  /// Whether this level is at least as strong as [other].
  bool isAtLeast(TimeConfidence other) => index >= other.index;
}
