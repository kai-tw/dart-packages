/// What one look at the device clock, against the watermark, concluded.
class ClockIntegrityReport {
  /// [delta] is the magnitude of the move; zero for [ClockIntegrityVerdict.intact].
  const ClockIntegrityReport({
    required this.verdict,
    required this.delta,
    required this.watermark,
  });

  /// The verdict.
  final ClockIntegrityVerdict verdict;

  /// How far the clock moved, as a non-negative magnitude. The direction is
  /// in [verdict].
  final Duration delta;

  /// The watermark in force after this observation, if there is one.
  final DateTime? watermark;

  /// Whether the device clock has been caught going backwards and has not
  /// been vindicated by a trusted source since.
  bool get isRolledBack => verdict == ClockIntegrityVerdict.rolledBack;

  @override
  String toString() => 'ClockIntegrityReport(${verdict.name}, delta=$delta)';
}

/// The three things an observation of the device clock can conclude.
enum ClockIntegrityVerdict {
  /// The clock is at or above the watermark and did not jump implausibly far
  /// ahead. The ordinary case.
  intact,

  /// The clock moved forward by more than elapsed monotonic time explains.
  ///
  /// Not proof of tampering on its own — a device that was asleep looks
  /// identical — so it raises the watermark and asks for a fresh sample
  /// rather than condemning the clock.
  advanced,

  /// The clock is behind the watermark: it has been set backwards, since the
  /// watermark only ever recorded instants this device itself reported.
  ///
  /// This is the one verdict a security decision must fail closed on.
  rolledBack,
}
