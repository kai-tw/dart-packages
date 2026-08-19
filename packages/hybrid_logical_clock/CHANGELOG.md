# Changelog

## 0.2.0

`Hlc.fromUntrustedWallClock` — the gated sibling of `fromLegacyWallClock`, for
seeding a stamp from a timestamp that came out of bytes rather than off the
local clock.

A consumer found the gap the hard way. `HlcDto.toDomain` applies the future-skew
ceiling, but it only runs when the stored shape actually carries the HLC fields;
a backward-compat read that falls back to a plain `createdAt` never reaches it.
Omitting the HLC fields entirely was therefore a documented way around the
ceiling, and the consumer had to re-implement the gate on its own side —
including a second copy of the 24h literal, in another repo, with nothing
keeping the two in sync.

- **Added** `Hlc.fromUntrustedWallClock`. Applies the ceiling and throws
  `HlcCorruptedException`, matching `HlcDto.toDomain`'s reject-don't-clamp
  stance.
- **Added** `Hlc.futureSkewCeilingMs` (public). It was
  `HlcDto._physicalMsFutureSkewCeilingMs`; it belongs on `Hlc` because it has to
  bound *every* construction from untrusted bytes, and there are two.
  `HlcDto.toDomain` now reads it from there, so the value is defined once.
- **Docs**: `fromLegacyWallClock` now states that it is ungated by design and
  names its trusted-input contract — the two factories are told apart only by
  where the caller got the `DateTime`, so that had to stop being implicit. The
  ceiling's own doc now says plainly that it is a bound, not an authentication:
  it cannot stop a forged `now + 23h`, it stops an uncapped stamp from winning
  `compareTo` permanently.

Non-breaking: additive, and `HlcDto.toDomain` behaviour is unchanged.

## 0.1.0

Hybrid logical clocks, extracted from a Flutter CRM that was already running
them.

- `Hlc`, `HlcClock` — a total order over stamps from any number of devices, with
  a deterministic node-id tiebreak and a sentinel ordering for writes that
  predate stamping.
- `FieldHlcs` — one stamp per field of a record, encoded as a single JSON value.
- `HlcDto` — the validating trust boundary for stamps read back out of storage
  the app does not control.

Differences from the code it was extracted from:

- `HlcDto` is hand-written rather than `freezed`-generated, and `Hlc` no longer
  uses `equatable`. The package has no build step and one runtime dependency.
- `Hlc.tryDecode` is new: a malformed stamp arriving from shared storage is an
  ordinary condition rather than a fault, so a caller that means to tolerate it
  says so with a null check instead of a catch — which would also swallow a
  defect in the decoder and report it as "this field has no stamp".

### Not shipped, though an earlier draft of this package had it

A Drive-backed sync engine — `SyncEngine`, `CloudStorage`, `MirrorStore`,
`SyncRecord` and their in-memory fakes — was written here alongside the clocks
and is deliberately absent. Its one consumer stopped syncing records through a
blob store, which left the engine with no user and no way to be exercised, while
its `MirrorStore` and `InMemoryMirrorStore` stayed on the public surface of a
package that consumer still wants for the clocks. Ordering and merging are
separable, and this package is the half that had a second use.
