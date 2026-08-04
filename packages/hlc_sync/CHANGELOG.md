# Changelog

## 0.1.0

Initial extraction, from the sync layer of a Flutter CRM that was already
running it.

- `Hlc`, `HlcClock` — hybrid logical clocks with a deterministic node-id
  tiebreak and a sentinel ordering for pre-HLC legacy writes.
- `SyncEngine` — three-way, field-level merge rounds against a `CloudStorage`
  and a `MirrorStore`, plus `readConflict` / `resolveConflict` for handing an
  unresolved conflict to a human and applying their answer.
- `CloudStorage` / `CloudAuth` — the transport seam, plus `InMemoryCloudStorage`
  and `InMemoryMirrorStore` so a two-device round trip runs in a unit test.
- `HlcDto` — the validating trust boundary for timestamps read back out of
  shared storage.

Differences from the code it was extracted from:

- `SyncEngine` takes an abstract `MirrorStore` rather than a concrete
  database accessor, so the package carries no storage dependency.
- Warnings go to an optional `SyncWarning` callback instead of straight to a
  crash reporter. Where they end up is the app's decision, not this package's.
- `HlcDto` is hand-written rather than `freezed`-generated, and `Hlc` no longer
  uses `equatable`. The package has no build step and one runtime dependency.
