import 'time_source_trust.dart';

/// One observation of a remote clock, paired with the monotonic reading taken
/// at the same instant.
///
/// The pairing is the entire point. A sample that carried only "the server
/// says 10:04:00" would have to be combined with the device clock to be
/// useful later, which puts the untrusted value back into every subsequent
/// answer. Carrying [ticksAtReceipt] instead lets an anchor derive the time
/// at any later moment from elapsed ticks alone.
///
/// [deviceWallAtReceipt] is recorded too, but never to compute time — only so
/// the anchor can later notice that the device clock has moved relative to
/// the monotonic base.
class TimeSample {
  /// All five parts are taken at the same instant by the source that built
  /// this sample.
  TimeSample({
    required DateTime remoteUtc,
    required this.ticksAtReceipt,
    required DateTime deviceWallAtReceipt,
    required this.uncertainty,
    required this.trust,
    required this.sourceId,
  }) : remoteUtc = remoteUtc.toUtc(),
       deviceWallAtReceipt = deviceWallAtReceipt.toUtc();

  /// Best estimate of true time at the moment [ticksAtReceipt] was read.
  ///
  /// A source that measures a round trip folds half of it in here, because
  /// the remote's timestamp describes an instant that had already passed by
  /// the time the response arrived.
  final DateTime remoteUtc;

  /// The monotonic reading taken at the same instant as [remoteUtc].
  final Duration ticksAtReceipt;

  /// What the device's own clock said at that instant. Diagnostic only —
  /// nothing derives a time from it.
  final DateTime deviceWallAtReceipt;

  /// Half-width of the interval [remoteUtc] is known to lie in.
  ///
  /// Typically half the round trip, plus whatever the source's own resolution
  /// costs (a one-second HTTP `Date` adds 500 ms).
  final Duration uncertainty;

  /// How hard this observation is to forge.
  final TimeSourceTrust trust;

  /// Which source produced it, for diagnostics and logging.
  final String sourceId;

  /// This device's clock error at the moment of the sample: positive when the
  /// device is behind true time.
  Duration get deviceOffset => remoteUtc.difference(deviceWallAtReceipt);

  @override
  String toString() =>
      'TimeSample($sourceId, ${trust.name}, '
      'remoteUtc=$remoteUtc, uncertainty=$uncertainty)';
}
