# CLAUDE.md — log_system

## The internals stay unexported to protect the EGRESS, not to be tidy

`LogRepository`, the data sources and the redactor are not exported, and the
barrel says why: a caller who has to assemble them is a caller who can assemble
them **wrong**, and a wrongly-assembled graph sends unredacted objects to
Crashlytics — the exact failure this package was extracted to prevent.

Read that as the load-bearing constraint. Everything else about the public
surface follows from it: configuration is flags on `init` rather than injected
collaborators, and `initWithRepositoryForTest` is for this package's own tests
and structurally cannot serve a host app (nothing outside can name its
argument).

`LogSink` is the one thing on the other side of that line, and the reason it is
allowed there is the test to apply to anything proposed next: **it is a
destination, not a collaborator in the graph.** There is nothing to assemble,
and what it receives has already crossed the redaction boundary. Observing the
egress and being able to widen it are different powers; only the second was
ever what got withheld.

## Do not open `LogRepository` to make a metric go green

This will be asked, and it has been: a consuming app's mutation testing finds
`statement_deletion` removing whole `LogSystem.warning(...)` / `error(...)`
lines with the suite still green, and the obvious fix looks like "export the
repository so a test can assert the call".

**That refusal stands, and `LogSink` did not overturn it.** A seam designed to
kill mutants gets shaped by the metric. What `LogSink` changed is the question,
not the answer:

- `LogRepository` would expose **which internal destination a level reached** —
  the graph, the part a caller can wire wrong.
- `LogSink` exposes **that a line was logged, and with what** — this package's
  own output, at one destination the app itself owns.

A sink deliberately cannot see whether the console or the reporter got a line;
that is still the routing table's business and is still tested only from
inside. If the next proposal needs to see *that*, it is the refused one wearing
a new name.

## The redactor has two call sites, and they must never chain

`FirebaseCrashlyticsAdapter` reduces on the way to Crashlytics — that is what
makes "no caller can opt out" true. `LogRepositoryImpl` reduces on the
host-sink path, because a sink does not pass through that adapter and would
otherwise receive the raw object.

Each reduces **once, for one destination, and never the other's output**.
Chaining them collapses a surrogate to the private surrogate type's own name,
which loses the original type name that keeps crash-report grouping apart
(flutterfire #3310). Moving redaction "up" into the repository to have one site
would trade that safety for tidiness: the adapter would then depend on its
caller having done it.

## A sink sees every level; the reporter's column is not the model

`debug` and `event` never reach the crash reporter, by routing. That makes them
exactly the levels an app cannot observe anywhere else, so a sink inheriting
the reporter's column would show an app only the half of its logging that was
never in question. What reaches a sink is bounded by **redaction**, not by
level.

## The package now lets an app assert a log call, and still takes no position on whether it should

Both halves of this were got wrong once and nearly shipped as a conclusion:

- **A deleted log line is a real change, not an equivalent mutant.** The levels
  here are differentiated by egress and each documents its own: `debug` never
  leaves the device and is dropped in release, `info` is local-only, `warning`
  reaches the crash reporter as a breadcrumb, `error`/`fatal` as a fault entry,
  `event` is console-only and explicitly not analytics. Deleting an `error(...)`
  removes a documented external consequence.
- **And a test asserting the call is still a change detector.** It pins that a
  particular line exists in a particular place, not that a fault reached the
  reporter. Both statements are true at once; that is the uncomfortable shape
  of this problem, and collapsing it to either half is what to avoid.

What changed in 0.4.0 is that the assertion is now *possible*. What did not
change is that this package does not tell an app to write it. The
generalisation to refuse is still "log calls have no verifiable effect" — they
have one, it is documented per level, and now it is observable too.

## Startup behaviour that reads like a bug and is not

- **Logging before anything is registered is a silent no-op.** Unit tests that
  construct production types directly never stand up the app's wiring, and a
  log line must not be why one of them throws. An app that wants its logging
  quiet under test simply registers nothing.
- **Calling `init` twice replaces the wiring** instead of throwing. An
  integration harness re-inits to swap the real reporter out. `register` has
  the same replace-don't-throw semantics for the same reason.
- **No Firebase app present wires the console alone and warns through it.**
  Throwing would let a logging library stop an app from starting; asserting
  aborts the rest of `init` so the harness gets no logging at all; degrading
  silently lets an app that merely forgot `initializeApp()` lose crash
  reporting with no complaint.
- **`reportCrashes: false` is not the "no Firebase" case.** It means Firebase
  IS present and must be told to stay quiet. Conflating the two is how this
  parameter first shipped, and it made the configuration that most needed to
  avoid Firebase the one that crashed on startup.
- **The Crashlytics adapter is built even when it will send nothing**, because
  building it is what switches collection off at the SDK. Skipping it would
  leave the SDK default — on — and the native layer captures a crash with no
  Dart code involved.
- **`LogSystem.withSink` exists instead of `init(sink:)` for tests** because
  `init` is wrong to call from a `setUp` whatever it is passed: it reads the
  Firebase registry, reassigns `PlatformDispatcher.instance.onError`
  process-wide, and logs a warning of its own.
