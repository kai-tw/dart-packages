import 'package:clock/clock.dart';

import 'clock_anchor_service.dart';

/// A `package:clock` [Clock] whose `now()` comes from a [ClockAnchorService].
///
/// This is the whole integration surface. Anything already written against
/// the ambient `clock` — `HlcClockImpl.tick()`, `HlcDto.toDomain()`'s future
/// ceiling, an expiry check — starts reading anchored time by being run
/// inside `withClock(AnchoredClock(service), ...)`, with no change at the
/// call site.
///
/// **Install it narrowly.** Wrapping the whole app hands anchored time to
/// code that must not have it: a reminder set for 09:00 is a wall-clock event
/// in the user's own timezone, and a "3 minutes ago" label should agree with
/// the watch on their wrist. Both of those want the device clock, wrong or
/// not. Wrap the cross-device comparisons instead — stamping, and the gates
/// that read stamps.
///
/// `now()` can step backwards when a new sample corrects an anchor that was
/// wrong. That is correct behaviour for an estimate and is safe for HLC,
/// whose `tick()` takes the maximum of the wall reading and what it has
/// already emitted; a consumer that needs a non-decreasing sequence must say
/// so itself rather than assume it here.
class AnchoredClock extends Clock {
  /// Reads through to [service] on every `now()`, so a refresh takes effect
  /// immediately with nothing to re-wire.
  AnchoredClock(ClockAnchorService service) : super(service.now);
}
