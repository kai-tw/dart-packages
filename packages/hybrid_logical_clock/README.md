# hybrid_logical_clock

Hybrid logical clocks — timestamps two devices order the same way without
agreeing on a wall clock.

A wall-clock timestamp cannot decide which of two offline edits came first. One
device's clock is three minutes slow, so every edit it makes loses, forever, and
nothing in the system says so. An `Hlc` pairs physical time with a logical
counter and a device-stable node id: any two stamps compare deterministically,
and every device reaches the same answer.

```dart
final HlcClock clock = HlcClockImpl(nodeId: myDeviceId);

final Hlc stamp = clock.tick();        // strictly greater than everything so far
clock.receive(stampFromAnotherDevice); // fold in what a peer emitted

stamp.encode();                        // '1735689600000-0-6f1c…'
Hlc.decode('1735689600000-0-6f1c…');
```

Compare order is `physicalMs → logical → nodeId`. The node-id tiebreak is
deterministic; it does not claim the lower id "wrote first", only that every
device picks the same winner.

## Per-field stamps

`FieldHlcs` encodes one stamp per field of a record as a single JSON value:

```dart
final String column = FieldHlcs.stamp(existing, <String>['name'], clock.tick());
final Map<String, Hlc> stamps = FieldHlcs.decode(column);
```

One value rather than a column per field, because nothing queries a field stamp
— it is only ever compared against the same field's stamp on the other side.
And a record type gaining a field needs no schema change.

This is what lets two devices editing *different* fields of one record both keep
their edit. Whole-record comparison throws one of them away silently.

A missing key means the field has never been stamped, which compares as older
than anything — so a record written before stamping existed loses to any later
edit rather than winning by accident.

## Clock skew is treated as hostile

`HlcDto` is the trust boundary for a stamp read back out of storage the app does
not control. `toDomain()` rejects any timestamp more than `Hlc.futureSkewCeilingMs`
(24 hours) ahead of the reader's wall clock, and any logical counter above 2^20.

It rejects rather than clamps. A stamp far in the future wins every comparison
forever, and clamping accepts the forged ordering quietly. Anything that can
write to shared storage can write such a value — including one of the user's own
devices with a wrong clock.

**Two entry points, one ceiling.** A stamp can also enter without the HLC fields
being present at all: a backward-compat read that finds only a plain `createdAt`
and seeds from that. `toDomain()` never runs on this path, so
`Hlc.fromUntrustedWallClock` applies the same ceiling — otherwise the gate is
bypassed by simply not writing the fields it guards. Its ungated sibling
`Hlc.fromLegacyWallClock` is for timestamps the device produced itself
(migration times, receive times), where there is no trust boundary to police.
Pick by where the `DateTime` came from, not by what it looks like.

The ceiling is a **bound, not an authentication**. It cannot stop a forged
`now + 23h`. What it removes is the unbounded case: `compareTo` orders on
`physicalMs` first, so an uncapped far-future stamp outranks every real write
*permanently*, turning one bad row into a record that can never be corrected.

Decode errors carry only positions and lengths, never the input: these strings
are attacker-influenced, and interpolating one into a log message round-trips
those bytes into whatever crash reporter is attached.

## What this is not

- **Not a sync engine.** No transport, no merge, no storage interface, no
  conflict model. This package decides ordering; everything built on that
  ordering is yours. An earlier version shipped a Drive-backed engine alongside
  it and was cut back to this — the engine had one consumer, which stopped
  needing it.
- **Not a CRDT.** An `Hlc` orders two writes. It does not merge them.

## Dependencies

One: [`clock`](https://pub.dev/packages/clock), so tests can control wall time
through `withClock`.

There is deliberately no build step. Two apps sharing this package would
otherwise have to move their code-generator versions in lockstep, which is a
worse problem than the twenty hand-written lines it saves.

## Status

`0.1.0`. The `Hlc` wire form (`<physicalMs>-<logical>-<nodeId>`) and the
`FieldHlcs` JSON shape are both persisted by consumers, so neither changes
without a major version. Pin exactly until `1.0.0`.
