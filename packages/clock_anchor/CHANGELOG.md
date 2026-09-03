# Changelog

## 0.1.0

First release.

The problem it exists for: `hybrid_logical_clock` makes ordering independent of
the wall clock, but three decisions around it are not — `HlcDto.toDomain()`'s
24-hour future ceiling is measured against the reader's own clock, signature
expiry is a real instant, and record age is a real duration. A device whose
clock is wrong decides all three wrongly, and the failure is silent in both
directions: two days fast and every peer rejects its writes, two days slow and
it rejects every peer's.

- **`ClockAnchorService`** — pins a remote time to a monotonic tick reading and
  derives every later answer from elapsed ticks, so the device clock is not a
  term in the expression. Adoption rules cover sample width, trust ordering and
  precision; readings are graded `unknown` / `deviceOnly` / `staleAnchor` /
  `anchored`.
- **`AnchoredClock`** — a `package:clock` `Clock`, which is the whole
  integration surface: `withClock` and no call site changes.
- **Sources** — `CallbackTimeSource` (a service the app already talks to),
  `HttpDateTimeSource` (a TLS `Date` header, with a hand-written parser for all
  three RFC 9110 forms), and `NtpTimeSource` in a separate library so `dart:io`
  stays out of the core. The SNTP client checks mode, leap indicator, stratum,
  a random nonce echo, and handles the 2036 era rollover.
- **`ClockIntegrity`** — rollback detection over a persisted watermark that
  never feeds a timestamp and can be pulled back down by a trusted anchor.
- **`StampRepairPolicy`** — finds stamps written while the clock was wrong,
  and refuses to act on an untrustworthy reading.

92 tests, including `test/hlc_integration_test.dart`, which runs against the
real `hybrid_logical_clock` rather than a stand-in: the claim being made is
about the two packages together.
