import 'time_sample.dart';
import 'time_source_trust.dart';

/// Somewhere a current time can be obtained from.
///
/// A source owns exactly one thing: turning one round trip into one
/// [TimeSample], including reading the monotonic base on both sides of that
/// round trip. It owns no policy — whether the sample is good enough, whether
/// it may replace what is already anchored, and how long it stays valid are
/// all `ClockAnchorService`'s decisions.
abstract class TimeSource {
  /// Stable identifier, used in diagnostics and to attribute failures.
  String get id;

  /// How hard this source is to lie to.
  TimeSourceTrust get trust;

  /// Performs one round trip.
  ///
  /// Throws [TimeSourceException] if the source cannot be reached or its
  /// answer is unusable. Anything else escaping this method is a defect and
  /// is deliberately not caught by the service.
  Future<TimeSample> sample();
}
