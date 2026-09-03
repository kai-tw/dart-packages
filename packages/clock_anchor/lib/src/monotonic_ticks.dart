/// Elapsed time that a change to the device's wall clock cannot move.
///
/// Everything in this package is derived from a pair — a remote time and the
/// tick reading taken at the same instant — precisely so that reading the
/// current time never has to consult the device clock again. That only holds
/// if this source is genuinely monotonic, so it is a seam: production uses
/// [StopwatchMonotonicTicks], tests supply one they can drive.
///
/// **It does not survive a process restart**, and on both mobile platforms it
/// does not advance while the device is asleep (Android's `CLOCK_MONOTONIC`,
/// iOS's `mach_absolute_time`; the variants that do count sleep are
/// `CLOCK_BOOTTIME` and `mach_continuous_time`, neither reachable from pure
/// Dart). Both gaps are handled by the anchor rather than pretended away —
/// see `TimeAnchor.discrepancyAt`, which reads an under-counting tick source
/// as a reason to re-sample rather than as a reason to trust the wall clock.
abstract class MonotonicTicks {
  /// Time elapsed since this instance started counting. Never decreases.
  Duration get elapsed;
}

/// The production [MonotonicTicks], counting from the moment it is built.
///
/// `Stopwatch` is the only monotonic source in the Dart core libraries. It
/// starts on construction rather than lazily so that the zero point is a
/// single, obvious event.
class StopwatchMonotonicTicks implements MonotonicTicks {
  /// Starts counting immediately.
  StopwatchMonotonicTicks() : _stopwatch = Stopwatch()..start();

  final Stopwatch _stopwatch;

  @override
  Duration get elapsed => _stopwatch.elapsed;
}
