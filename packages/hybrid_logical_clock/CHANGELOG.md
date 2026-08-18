# Changelog

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
