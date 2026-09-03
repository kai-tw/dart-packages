/// Wall-clock time an app can still act on when the device clock cannot be
/// trusted.
///
/// A hybrid logical clock already makes *ordering* independent of the wall
/// clock. What it cannot do is make the wall clock itself right, and several
/// decisions around a sync engine need that: a future-stamp ceiling is
/// measured against the reader's own clock, a signature's expiry is a real
/// instant, and "how old is this" is a real duration. On a device whose owner
/// moved the clock — or whose clock was simply never set — every one of those
/// is decided by the wrong number.
///
/// The mechanism is one idea. A remote time is pinned to a monotonic tick
/// reading taken at the same instant, and every later answer is derived from
/// elapsed ticks:
///
/// ```
/// timeAt(ticksNow) = referenceUtc + (ticksNow - ticksAtReference)
/// ```
///
/// There is no device-clock term in that expression, so changing the device
/// clock — once, or five times a second — moves nothing. That is the whole
/// point, and it is why this is not an "offset": an offset added to the
/// device clock would be wrong again the moment the clock moved.
///
/// What is here:
///
/// * [ClockAnchorService] — holds the anchor, decides what may replace it,
///   and answers [TimeReading]s.
/// * [AnchoredClock] — a `package:clock` `Clock` over that service, which is
///   how existing code starts reading anchored time without changing.
/// * [TimeSource] and its implementations — [CallbackTimeSource] for a
///   service the app already talks to, [HttpDateTimeSource] for a TLS `Date`
///   header. The SNTP client lives in `clock_anchor_ntp.dart` so that
///   `dart:io` stays out of this library.
/// * [ClockIntegrity] — rollback detection over a persisted watermark, which
///   never feeds a timestamp and can be corrected by a trusted source.
/// * [StampRepairPolicy] — which stamps were written while the clock was
///   wrong and should be re-issued.
///
/// What is deliberately not here: no transport, no storage, no scheduling,
/// and no timezone handling. A reminder set for 09:00 is a wall-clock event
/// in the user's own zone and must keep using the device clock; nothing in
/// this package should reach that code.
library;

export 'src/anchored_clock.dart';
export 'src/callback_time_source.dart';
export 'src/clock_anchor_policy.dart';
export 'src/clock_anchor_service.dart';
export 'src/clock_integrity.dart';
export 'src/clock_integrity_report.dart';
export 'src/http_date_exception.dart';
export 'src/http_date_time_source.dart';
export 'src/monotonic_ticks.dart';
export 'src/stamp_repair_decision.dart';
export 'src/stamp_repair_policy.dart';
export 'src/time_anchor.dart';
export 'src/time_confidence.dart';
export 'src/time_reading.dart';
export 'src/time_sample.dart';
export 'src/time_source.dart';
export 'src/time_source_exception.dart';
export 'src/time_source_trust.dart';
export 'src/watermark_store.dart';
