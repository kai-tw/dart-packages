import 'package:clock/clock.dart';

import 'monotonic_ticks.dart';
import 'time_sample.dart';
import 'time_source.dart';
import 'time_source_trust.dart';

/// A [TimeSource] backed by a callback the app supplies.
///
/// This is how a service the app is *already* talking to becomes a time
/// source — Firestore's `serverTimestamp` written and read back, a Drive
/// file's `modifiedTime` — without this package growing a dependency on
/// either. The app owns the transport and the credentials; this owns the
/// measurement around them.
///
/// The callback must throw a `TimeSourceException` when it cannot reach the
/// service. Anything else it throws is treated as a defect and propagates.
class CallbackTimeSource implements TimeSource {
  /// [resolution] is the granularity the remote timestamp is truncated to —
  /// one second for most APIs that report whole seconds, zero when the remote
  /// reports finer than the round trip can resolve.
  CallbackTimeSource({
    required this.id,
    required this.trust,
    required MonotonicTicks ticks,
    required Future<DateTime> Function() probe,
    Duration resolution = Duration.zero,
    Clock deviceClock = const Clock(),
  }) : _ticks = ticks,
       _probe = probe,
       _resolution = resolution,
       _deviceClock = deviceClock;

  @override
  final String id;

  @override
  final TimeSourceTrust trust;

  final MonotonicTicks _ticks;
  final Future<DateTime> Function() _probe;
  final Duration _resolution;
  final Clock _deviceClock;

  @override
  Future<TimeSample> sample() async {
    final Duration sentAt = _ticks.elapsed;
    final DateTime remote = await _probe();
    final Duration receivedAt = _ticks.elapsed;

    // The round trip is measured on the monotonic base, never on the wall
    // clock: a clock change landing mid-request would otherwise produce a
    // nonsense round trip and, with it, a nonsense sample.
    final Duration roundTrip = receivedAt - sentAt;

    // Two independent unknowns, each contributing half its width both to the
    // estimate and to the error bar: where in the round trip the remote
    // stamped its answer, and where inside one resolution step the true
    // instant fell.
    final Duration halfTrip = roundTrip ~/ 2;
    final Duration halfStep = _resolution ~/ 2;

    return TimeSample(
      remoteUtc: remote.toUtc().add(halfTrip).add(halfStep),
      ticksAtReceipt: receivedAt,
      deviceWallAtReceipt: _deviceClock.now(),
      uncertainty: halfTrip + halfStep,
      trust: trust,
      sourceId: id,
    );
  }
}
