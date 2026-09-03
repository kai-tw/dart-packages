# clock_anchor

Wall-clock time an app can still act on when the device clock cannot be
trusted.

A hybrid logical clock already makes *ordering* independent of the wall clock.
What it cannot do is make the wall clock right, and a sync engine has several
decisions that need it: a future-stamp ceiling is measured against the reader's
own clock, a signature's expiry is a real instant, "how old is this" is a real
duration. On a device whose owner moved the clock — or whose clock was simply
never set — every one of those is decided by the wrong number.

## The idea, and why it is not an offset

A remote time is pinned to a monotonic tick reading taken at the same instant,
and every later answer is derived from elapsed ticks:

```
timeAt(ticksNow) = referenceUtc + (ticksNow - ticksAtReference)
```

There is no device-clock term in that expression. Change the phone's time once,
or five times a second, and nothing derived from an anchor moves.

An offset would not survive that. `correctedNow = deviceNow + offset` still
reads the device clock on every call, so it is wrong again the moment the clock
moves and stays wrong until the next sample.

```dart
final ClockAnchorService service = ClockAnchorService(
  ticks: StopwatchMonotonicTicks(),
  integrity: ClockIntegrity(store: myWatermarkStore),
  sources: <TimeSource>[firestoreSource, cdnDateSource, ntpSource],
);

await service.refresh();          // on start, on foreground, on reconnect
final TimeReading now = service.read();
if (now.isTrustworthy) { /* … */ }
```

## Three kinds of time, and only one of them belongs here

| Question | Clock to use |
|---|---|
| Which of two devices wrote first; is this stamp plausible; has this expired | **anchored** — this package |
| What time does the user's watch say; when should a 09:00 reminder fire | **device** — `DateTime.now()`, and the device's own timezone |
| How long did this take; how old is this staged file | **monotonic** — `Stopwatch`, never a wall clock |

Install `AnchoredClock` narrowly, over the cross-device comparisons. Wrapping
a whole app hands anchored time to reminder scheduling, which is a wall-clock
event in the user's own zone and must keep using the device clock.

## Integrating with `hybrid_logical_clock`

Both `HlcClockImpl.tick()` and `HlcDto.toDomain()`'s 24-hour future ceiling
read the ambient `package:clock`, so the integration is one wrapper and no call
site changes:

```dart
withClock(AnchoredClock(service), () {
  final Hlc stamp = hlcClock.tick();       // tracks anchored time
  final Hlc peer = peerDto.toDomain();     // ceiling measured against it too
});
```

That closes both halves of the failure. A device two days fast stamps writes
every peer rejects; a device two days slow rejects every peer's valid stamp and
silently stops syncing. Both are pinned in `test/hlc_integration_test.dart`
against the real package.

## Trust levels

Ordering is load-bearing in exactly two decisions — which sample may replace a
disagreeing anchor, and which may lower the rollback watermark.

| Level | Example | May lower the watermark |
|---|---|---|
| `unauthenticated` | SNTP over UDP | no |
| `transportAuthenticated` | an HTTPS `Date` header | yes |
| `serverAttested` | Firestore `serverTimestamp`, Drive `modifiedTime` | yes |

SNTP is here because it needs no account and works on a first run, which covers
the common case of an honestly wrong clock. It cannot be trusted against a
deliberate one: the exchange is plaintext UDP, and whoever set the clock also
controls the network. The nonce echo raises the bar to *on-path*; it does not
clear it.

## Rollback detection

`ClockIntegrity` keeps a persisted high-water mark of the highest instant this
device ever reported. A reading below it means the clock was set back.

**It never feeds a timestamp.** A watermark used as a floor under emitted
stamps poisons every later write for as long as the bogus value stands — wind
the clock forward three days once and the device is unusable for three days,
which is worse than the failure it prevents. It answers one question, and the
answer goes to consumers whose safe response is to refuse and retry.

It is also not permanent. A `transportAuthenticated` or better anchor pulls a
future watermark back down, and vindicates the device clock separately once
that clock agrees with the truth again.

## Repairing what was written before the anchor existed

Anchoring cannot retract stamps written offline, on a first run, or between a
clock change and the next sample. `StampRepairPolicy` finds them:

```dart
final List<Record> broken = policy.plan<Record>(
  pendingUploads,                       // see the two preconditions below
  stampOf: (Record r) => r.stampTime,
  now: service.read(),
);
```

Three rules the caller has to know:

1. **Only pass stamps this device produced** — with HLC, filter on the node id.
   Re-issuing a peer's stamp overwrites their ordering with yours.
2. **Only pass records no peer has accepted yet.** Repair lowers a stamp; a
   peer holding the high one still ranks it above the repaired value. The
   pending-upload set is the right input.
3. **Re-seat the HLC clock before re-stamping.** `HlcClockImpl` takes the
   maximum of the wall reading and what it has already emitted, so re-stamping
   through the same instance carries the bad value forward. Its `_lastEmitted`
   is in-memory only, so building a fresh `HlcClockImpl` with the same node id
   is a valid reset — and running the repair at startup, before the first tick,
   avoids the problem altogether.

Nothing is repaired unless the reading is `anchored`. Repairing against a
device clock would be the same mistake in the other direction: a device merely
running behind would rewrite every correct stamp it owns.

## Sleep, and what it costs

`Stopwatch` does not advance while the device is asleep on either mobile
platform (`CLOCK_MONOTONIC`, `mach_absolute_time`; the variants that count
sleep are not reachable from pure Dart). So an anchor can lag after a long
sleep, and that is indistinguishable from someone winding the clock forward.

Both are handled the same way rather than guessed at: a wall clock running
*ahead* of the monotonic base marks the anchor `staleAnchor` and widens its
uncertainty by the discrepancy. A wall clock running *behind* it can only be a
clock change — sleep cannot produce it — so the anchor keeps full confidence.
Refresh on foreground and the window stays short.

## What this is not

- **Not a sync engine, and not a clock replacement.** It produces one reading.
- **Not authentication.** The trust ordering ranks how hard a source is to
  lie to; none of it proves a time is true.
- **No transport, no storage, no timezones.** Sources take an injected probe,
  the watermark takes a `WatermarkStore` port, and reminder scheduling is
  none of its business.

## Dependencies

One: [`clock`](https://pub.dev/packages/clock). `dart:io` appears only in
`clock_anchor_ntp.dart`, so the core library stays free of it.

## Status

`0.1.0`. The `WatermarkStore` value is persisted by consumers, so its meaning
does not change without a major version. Pin exactly until `1.0.0`.
