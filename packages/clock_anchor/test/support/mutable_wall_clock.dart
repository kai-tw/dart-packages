import 'package:clock/clock.dart';

/// A device wall clock a test can move to any instant, in either direction —
/// which is exactly what the user under test is doing.
class MutableWallClock {
  /// [_now] is the initial reading.
  MutableWallClock(this._now);

  DateTime _now;

  /// Moves the device clock to [value]. Forwards, backwards, repeatedly.
  set now(DateTime value) => _now = value.toUtc();

  /// The current reading, as a tear-off for [clock].
  DateTime read() => _now;

  /// The `package:clock` view, for injecting as a service's device clock.
  Clock get clock => Clock(read);
}
