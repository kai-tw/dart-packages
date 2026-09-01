## 0.4.0

`LogSink` — a host app can now register a destination of its own, either
alongside the console and the crash reporter (`init(sink: ...)`) or on its own
(`LogSystem.withSink(sink)` + `LogSystem.register(...)`). `LogSystem.reset()`
became public, because it is now half of a contract a host app has to hold up
in a `tearDown` rather than only this package's own test seam.

The version this ships from was `0.3.3` in the pubspec and was never tagged, so
its changes ship here too.

**What a sink receives is the redacted value, not the original.** That is the
whole reason the seam could be opened at all. A sink is a destination, not a
collaborator in the graph — it has nothing to assemble and therefore nothing to
assemble wrong, and it is handed values that have already crossed the redaction
boundary. Observing the egress and being able to widen it are different powers,
and only the second was ever what got withheld.

The cost is deliberate and was accepted knowingly: a test asserting *which*
failure was logged can only tell apart what the redactor can tell apart — the
exception's type and its `diagnosticCode`. A test that cannot distinguish two
failures is describing a pair of exceptions the crash reporter cannot
distinguish either. The pressure that creates points at splitting the exception
type, which is the right direction for it to point.

**This is not the seam that was refused.** `CLAUDE.md` records a standing
refusal to export `LogRepository` so a consuming app's mutation testing can
kill `statement_deletion` mutants on its log lines, and that refusal stands: a
seam designed to make a metric go green gets shaped by the metric. What changed
is the question. `LogRepository` would have exposed *which internal destination
a level reached* — the graph, the thing a caller can wire wrong. A `LogSink`
exposes *that a line was logged, and with what*, which is a question about this
package's own output. The first is the egress; the second never was.

Two consequences worth stating rather than discovering:

- **The redactor now has two call sites, and neither ever receives the other's
  output.** The first is inside `FirebaseCrashlyticsAdapter`, which guards its
  own egress so no caller can opt out on the way to Crashlytics; the second is
  in the repository, on the host-sink path, which does not pass through that
  adapter and would otherwise hand over the raw object. Each reduces once, for
  one destination. Chaining them would reduce a surrogate to the surrogate
  type's own name and collapse every distinct error in the app into one crash
  report issue.
- **A sink receives every level, including `debug` and `event`.** They are
  precisely the levels the crash reporter drops by routing, which makes them
  the ones an app cannot observe anywhere else; a sink inheriting the
  reporter's column would show an app only the half of its logging that was
  never in question. What reaches a sink is bounded by redaction, not by level.

`LogEntry` and `LogLevel` are exported alongside `LogSink`. No fake sink is
shipped: a test double belongs to the suite that asserts on it, and shipping
one would put its shape — what it records, how a matcher reads it — in this
package's public API, where changing it is a breaking change for every
consumer. The four-line implementation to copy is in the `LogSink` doc and the
README.

`LogSystem`'s generative constructor is now private. It took an unexported
`LogRepository`, so nothing outside this package could ever call it; the
change is a signature correction, not a removed capability.

## Earlier versions

Not reconstructed. This file starts at 0.4.0; before it, the git tags
(`log_system-v0.1.0` through `log_system-v0.3.2`) and their commits are the
record.
