# hlc_sync

Field-level, last-writer-wins sync over any passive blob store, ordered by
hybrid logical clocks.

The store is assumed to be **dumb**: it holds bytes at paths and does nothing
else. No server of yours, no live peer connection, no code generation. If you
can `list`, `read`, `write` and `delete` byte blobs somewhere — Google Drive's
app data folder, an object store, a synced directory — you can sync two devices
through it.

```dart
final SyncEngine engine = SyncEngine(
  storage: myCloudStorage,   // you implement: moves bytes
  mirror: myMirrorStore,     // you implement: remembers the last agreed state
  sources: <SyncableSource>[customers, tasks],  // you implement: your own rows
  now: DateTime.now,
);

final SyncReport report = await engine.syncAll();
if (report.hasConflicts) {
  // Nothing was written for these. Both sides kept what they had.
}
```

## What makes it field-level

Two devices editing *different fields of the same record* both keep their edit.
Whole-record last-write-wins would throw one away silently.

That works because every field carries its own HLC stamp, and because a
**mirror** — a local copy of what the record looked like the last time both
sides agreed — gives the merge a common ancestor. With a base to diff against,
"both sides changed this field" is distinguishable from "one side is merely
behind", which is the distinction last-write-wins cannot make.

When both sides really did change the *same* field, nothing is written and the
record is reported as a conflict. It stays divergent until someone chooses. An
unresolved conflict must not quietly resolve itself on the next round.

To let a human choose, `readConflict` returns both sides — read fresh, not
snapshotted, because the other device may have moved on while the user was
deciding — and `resolveConflict` applies the answer:

```dart
final ConflictDetail? detail = await engine.readConflict(
  recordType: 'customer',
  id: conflict.id,
);
await engine.resolveConflict(
  recordType: 'customer',
  id: conflict.id,
  choice: ConflictChoice.keepLocal,
);
```

## What you implement

| | |
|---|---|
| `CloudStorage` | `list` / `read` / `write` / `delete` on `/`-rooted paths. |
| `MirrorStore` | Stores one row per `(recordType, id)`. `InMemoryMirrorStore` ships for tests. |
| `SyncableSource` | Reads and writes your own rows, one implementation per record type. |

`InMemoryCloudStorage` ships too — it is the reference implementation and it can
simulate being offline, so a full two-device round trip runs in a unit test with
no network and no account.

## Deletes

Tombstones must be included in `SyncableSource.readAll()`. Omitting them is what
makes a delete look like a record the other side has simply not received, so it
comes back. `SyncEntityPresence` has three states rather than two for the same
reason: "deleted" and "never heard of it" are different facts.

## Clock skew is treated as hostile

`HlcDto.toDomain` rejects any timestamp more than 24 hours ahead of the reader's
wall clock, because an HLC far in the future would win every conflict forever.
It rejects rather than clamps — clamping silently accepts a forged ordering.
Anything that can write to the shared store can write such a value, including
one of the user's own devices with a wrong clock.

## What this is not

- **Not a general CRDT.** Each field is an LWW register. Concurrent edits to the
  same field are surfaced, not merged. If you need text that merges
  character-by-character, you want an actual CRDT library.
- **Not a transport.** There is no Drive, S3 or HTTP code here, and no
  dependency on any of them. `CloudStorage` is the seam; the adapter is yours.
- **Not live.** A round is something you trigger. Nothing pushes.

## Logging is a seam, not a dependency

The engine takes an optional `SyncWarning` callback and never imports a logger.
That is deliberate: warnings name types and record types but the sink is the
app's choice, and a sink that forwards to a crash reporter sends everything
passed to it off the device. `SyncReport.skipped` still counts what was stepped
over even with no callback wired, so ignoring the seam loses detail but never
the fact.

## Dependencies

One: [`clock`](https://pub.dev/packages/clock), so tests can control wall time.

There is deliberately no build step. Two apps sharing this package would
otherwise have to move their code-generator versions in lockstep, which is a
worse problem than the twenty hand-written lines it saves.

## Status

`0.1.0`. Used in production by two apps, but the `CloudFile` shape is still
expected to change — it needs a version token before concurrent writers from two
devices can be made safe. Pin exactly until `1.0.0`.
