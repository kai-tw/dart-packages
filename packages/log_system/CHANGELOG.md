## 0.4.1

Tests only — no API or behaviour change to anything a host app calls.

`FirebaseCrashlyticsAdapter` — the crash-reporter egress, and until now the
single least-tested file in the package (0% line coverage) — is now covered
end to end with a `mocktail`-based `MockFirebaseCrashlytics`: the `enabled`
gate, that `debug`/`event` never reach it regardless, custom-key stamping
(including the deferred, unawaited path), and that `warning`/`error`/`fatal`
hand the reporter the *redacted* surrogate, never the raw object.

Two internals gained a narrow, additive seam so this package's own tests can
reach logic that was previously sealed behind `kReleaseMode` — a compile-time
constant, always false under `flutter test`, so no test can flip it:

- `LogSystem`'s two uncaught-error handler bodies (`FlutterError.onError`'s
  environmental/logic-error split, `PlatformDispatcher.instance.onError`'s
  "handled" contract) are now `LogSystem.handleFrameworkErrorForTest` /
  `handleAsyncErrorForTest` — ordinary `@visibleForTesting` static methods
  rather than closures written inline inside the release-only gate, in the
  same shape as the existing `initWithRepositoryForTest`: not exported from
  the public barrel, reachable only from this package's own tests. The
  gate's *assignment* is still release-only and still untestable under
  `flutter test`; only the handler *logic* moved somewhere a test can reach.
- `LoggerAdapter` takes an optional `output` constructor parameter (defaults
  to `logger`'s own `ConsoleOutput`, unchanged from before this existed), so
  a test can inject `MemoryOutput()` and read back what was actually
  printed — which is what caught that `debug` and `fatal` were previously
  asserted only to complete, never to have printed anything, so a
  `kReleaseMode` read backwards would have passed silently.

**Every line change was checked against this package's own `CLAUDE.md`:
`LogRepository` and the redactor's call sites are untouched.** Nothing here
exposes which internal destination a level reached, and the redaction
boundary still reduces at exactly its two existing sites and nowhere else.

Line coverage 100% (211/211, `--check-ignore`); mutation 94.4% (119/126,
`dart_mutants`). The 7 survivors are two families, both already the subject
of a `// coverage:ignore` pragma in the source for the identical reason:
code gated on `kReleaseMode` (always false under `flutter test`, so the
gate's own *assignment* — as opposed to the logic behind it, see above — is
dead in every test build), and the two lines that construct
`FirebaseCrashlyticsAdapter` from the real `FirebaseCrashlytics.instance`
(verified empirically to fail an internal plugin assertion in a pure-Dart
test binary before this package's own code runs, since reaching it needs a
registered `FirebaseCrashlyticsPlatform` this package does not own).

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
