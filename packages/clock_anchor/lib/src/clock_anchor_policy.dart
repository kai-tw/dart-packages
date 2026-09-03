/// The thresholds that decide when an anchor is still worth trusting and
/// which samples are allowed to replace it.
///
/// Every value is a judgement rather than a measurement, so they are gathered
/// here instead of being scattered as literals: an app that knows its own
/// network can tighten them, and a test can make any of them trigger without
/// waiting.
class ClockAnchorPolicy {
  /// The defaults are deliberately conservative — they prefer declaring an
  /// anchor stale over reporting a confident wrong time.
  const ClockAnchorPolicy({
    this.maxAnchorAge = const Duration(hours: 6),
    this.maxDiscrepancy = const Duration(seconds: 30),
    this.maxSampleUncertainty = const Duration(seconds: 10),
    this.unanchoredUncertainty = const Duration(hours: 12),
    this.driftPpm = 100,
  });

  /// How long an anchor may be held, in monotonic time, before it is treated
  /// as stale.
  ///
  /// Measured monotonically on purpose: an anchor cannot be expired early, or
  /// kept alive past its worth, by moving the device clock.
  final Duration maxAnchorAge;

  /// How far the device clock may drift from the monotonic base before the
  /// anchor is treated as stale.
  ///
  /// Only a *forward* drift counts. The wall clock running behind the
  /// monotonic base can only be a clock change, which leaves the anchor
  /// untouched; running ahead may instead be sleep the tick source did not
  /// count, which means the anchor may now lag.
  final Duration maxDiscrepancy;

  /// The widest sample this service will anchor on.
  ///
  /// A round trip of tens of seconds produces a sample whose error swamps
  /// anything it could tell us; anchoring on it would replace a good estimate
  /// with a worse one and reset the age while doing it.
  final Duration maxSampleUncertainty;

  /// The uncertainty reported when there is no anchor at all.
  ///
  /// A convention, not a measurement — an unchecked device clock can be wrong
  /// by any amount. Consumers must gate on `TimeReading.confidence`; this
  /// value exists so arithmetic on a reading does not have to special-case
  /// the unanchored state.
  final Duration unanchoredUncertainty;

  /// Assumed oscillator error, in parts per million, used to widen an
  /// anchor's uncertainty as it ages.
  ///
  /// Consumer crystals are specified around 20 ppm and do worse across
  /// temperature; 100 ppm is about 8.6 seconds a day, which is pessimistic
  /// and cheap.
  final double driftPpm;
}
