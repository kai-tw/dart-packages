import 'package:clock_anchor/clock_anchor.dart';

/// A [MonotonicTicks] a test drives by hand.
///
/// Every scenario worth pinning here is about the *relationship* between
/// elapsed monotonic time and a wall clock somebody moved, so both have to be
/// controllable independently. A real `Stopwatch` would tie the first to how
/// long the test itself took.
class FakeMonotonicTicks implements MonotonicTicks {
  /// Starts at zero unless seeded.
  FakeMonotonicTicks([this._elapsed = Duration.zero]);

  Duration _elapsed;

  @override
  Duration get elapsed => _elapsed;

  /// Moves the monotonic base forward. Never backwards — that is the one
  /// thing a monotonic source cannot do, so the fake must not be able to
  /// fake it.
  void advance(Duration by) {
    if (by.isNegative) {
      throw ArgumentError.value(by, 'by', 'monotonic ticks cannot go back');
    }
    _elapsed += by;
  }
}
