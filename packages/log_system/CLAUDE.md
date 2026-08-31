# CLAUDE.md — log_system

## The internals stay unexported to protect the EGRESS, not to be tidy

`LogRepository`, the sinks and the redactor are not exported, and the barrel
says why: a caller who has to assemble them is a caller who can assemble them
**wrong**, and a wrongly-assembled graph sends unredacted objects to
Crashlytics — the exact failure this package was extracted to prevent.

Read that as the load-bearing constraint. Everything else about the public
surface follows from it: configuration is flags on `init` rather than injected
collaborators, `initWithRepositoryForTest` is for this package's own tests and
structurally cannot serve a host app (nothing outside can name its argument),
and there is no observation point anywhere.

**A host app that wants quiet logging under test does not call `init`.** Every
level is a silent no-op until it does. That is the supported answer, and it is
stated on `init` and on `initWithRepositoryForTest`.

## Do not open `LogRepository` to make a metric go green

This will be asked, and it has been: a consuming app's mutation testing finds
`statement_deletion` removing whole `LogSystem.warning(...)` / `error(...)`
lines with the suite still green, and the obvious fix looks like "export the
repository so a test can assert the call".

Refuse that framing. A seam designed to kill mutants gets shaped by the metric.
If an egress-observation seam is ever wanted, it starts from **"how does an app
verify a fault actually reached the reporter"** — which is an integration-level
question about the sink, not a unit-level question about the call site — and it
is a cross-repo design conversation, not a package tweak.

## The package takes NO position on asserting that a log call happened

`init`'s doc says something adjacent and stops short: log calls must be
**inert** in unit tests, because a unit test that constructs production types
never stands up the wiring and a log line must not be why it throws. That is
about logging not breaking tests. It says nothing about whether an app should
assert one occurred, and the silence is now deliberate rather than accidental.

What is worth recording, because it was got wrong once and nearly shipped as a
conclusion to the founder:

- **A deleted log line is a real change, not an equivalent mutant.** The levels
  here are differentiated by egress and each one documents its own: `debug`
  never leaves the device and is dropped in release, `info` is local-only,
  `warning` reaches the crash reporter as a breadcrumb, `error`/`fatal` as a
  fault entry, `event` is console-only and explicitly not analytics. Deleting
  an `error(...)` removes a documented external consequence.
- **And a unit test asserting the call is still a change detector.** It pins
  that a particular line exists in a particular place, not that a fault reached
  the reporter. Both statements are true at once; that is the uncomfortable
  shape of this problem, and collapsing it to either half is what to avoid.

The generalisation to refuse is "log calls have no verifiable effect". They
have one; it is documented per level; it is simply not observable from a host
app's own tests, on purpose (see above).

## Startup behaviour that reads like a bug and is not

- **Calling `init` twice replaces the wiring** instead of throwing. An
  integration harness re-inits to swap the real reporter out.
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
