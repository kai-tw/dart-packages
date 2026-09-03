import 'time_sample.dart';
import 'time_source_trust.dart';

/// A remote time pinned to a monotonic tick reading, from which any later
/// instant can be derived without consulting the device clock.
///
/// ```
/// timeAt(ticksNow) = referenceUtc + (ticksNow - ticksAtReference)
/// ```
///
/// There is no device clock term in that expression, which is the property
/// the whole package exists to provide: the user can change the phone's time
/// as often as they like and every value derived from an anchor is unmoved.
class TimeAnchor {
  /// Prefer [TimeAnchor.fromSample]; this exists for tests that need to build
  /// an anchor in a specific state.
  TimeAnchor({
    required DateTime referenceUtc,
    required this.ticksAtReference,
    required DateTime deviceWallAtReference,
    required this.uncertainty,
    required this.trust,
    required this.sourceId,
  }) : referenceUtc = referenceUtc.toUtc(),
       deviceWallAtReference = deviceWallAtReference.toUtc();

  /// Pins [sample] as the new reference point.
  factory TimeAnchor.fromSample(TimeSample sample) => TimeAnchor(
    referenceUtc: sample.remoteUtc,
    ticksAtReference: sample.ticksAtReceipt,
    deviceWallAtReference: sample.deviceWallAtReceipt,
    uncertainty: sample.uncertainty,
    trust: sample.trust,
    sourceId: sample.sourceId,
  );

  /// True time at the instant [ticksAtReference] was read.
  final DateTime referenceUtc;

  /// The monotonic reading at that instant.
  final Duration ticksAtReference;

  /// The device clock's reading at that instant. Used only by
  /// [discrepancyAt]; never to derive a time.
  final DateTime deviceWallAtReference;

  /// Half-width of the uncertainty interval at the moment of anchoring.
  /// [uncertaintyAt] widens it as the anchor ages.
  final Duration uncertainty;

  /// Trust level of the source this anchor came from.
  final TimeSourceTrust trust;

  /// Which source produced it.
  final String sourceId;

  /// True time at the moment [ticksNow] was read.
  DateTime timeAt(Duration ticksNow) =>
      referenceUtc.add(ticksNow - ticksAtReference);

  /// How long this anchor has been held, measured in monotonic time.
  ///
  /// Monotonic, so an anchor cannot be aged out — or kept alive — by moving
  /// the device clock.
  Duration ageAt(Duration ticksNow) => ticksNow - ticksAtReference;

  /// Uncertainty widened by the oscillator drift accumulated since anchoring.
  ///
  /// [driftPpm] is parts per million of elapsed time; consumer-grade crystals
  /// are specified around 20 ppm and behave worse across temperature, so the
  /// package's default is deliberately pessimistic.
  Duration uncertaintyAt(Duration ticksNow, double driftPpm) {
    final Duration age = ageAt(ticksNow);
    final int drift = (age.inMicroseconds.abs() * driftPpm / 1000000).round();
    return uncertainty + Duration(microseconds: drift);
  }

  /// How far the device clock has moved relative to the monotonic base since
  /// this anchor was taken.
  ///
  /// Zero on a well-behaved device. The sign carries information and the two
  /// signs are not equally ambiguous:
  ///
  /// * **Negative** — the wall clock advanced less than the ticks did, i.e. it
  ///   went backwards. Nothing but a clock change can do this; sleep cannot.
  /// * **Positive** — the wall clock advanced more than the ticks did. Either
  ///   the clock was moved forward, or the device slept and the tick source
  ///   did not count it. These are indistinguishable from pure Dart, and both
  ///   call for the same response: treat the anchor as stale and re-sample.
  Duration discrepancyAt(Duration ticksNow, DateTime deviceNow) =>
      deviceNow.toUtc().difference(deviceWallAtReference) -
      (ticksNow - ticksAtReference);

  @override
  String toString() =>
      'TimeAnchor($sourceId, ${trust.name}, referenceUtc=$referenceUtc)';
}
