import 'time_confidence.dart';

/// What the package will say the time is, and how much that is worth.
///
/// Always carries a usable [utc] — an app that must render a timestamp or
/// stamp a record cannot be handed `null` — with [confidence] saying what it
/// is allowed to be used for. A consumer that must fail closed reads
/// [confidence] first and the value second.
class TimeReading {
  /// [uncertainty] is the half-width of the interval [utc] is believed to lie
  /// in; it is not meaningful when [confidence] is [TimeConfidence.unknown].
  TimeReading({
    required DateTime utc,
    required this.confidence,
    required this.uncertainty,
  }) : utc = utc.toUtc();

  /// The best available estimate of the current instant, in UTC.
  final DateTime utc;

  /// How much [utc] is worth.
  final TimeConfidence confidence;

  /// Half-width of the interval [utc] is believed to lie in.
  final Duration uncertainty;

  /// The earliest instant it could currently be.
  ///
  /// Use this when acting *too early* is the danger — "has at least an hour
  /// passed since this file was staged" wants the pessimistic answer, so a
  /// sweep never deletes something a receiver may still be reading.
  DateTime get earliest => utc.subtract(uncertainty);

  /// The latest instant it could currently be.
  ///
  /// Use this when acting *too late* is the danger, which covers both of this
  /// package's own consumers: a signature check assumes now is as late as it
  /// could be, so an expired delegation fails closed; and a stamp is only
  /// called implausible once it is ahead of even this, so an uncertain
  /// reading accuses fewer stamps rather than more.
  DateTime get latest => utc.add(uncertainty);

  /// Whether this reading may be used for a security decision: a fresh anchor
  /// and nothing observed against it.
  bool get isTrustworthy => confidence == TimeConfidence.anchored;

  @override
  String toString() => 'TimeReading($utc, ${confidence.name}, +/-$uncertainty)';
}
