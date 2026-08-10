# log_system

Structured logging with a **redacted** crash-reporting egress.

Extracted from NovelGlide, where it had grown the parts that only show up once
an app has shipped: per-severity routing, a release-only egress gate, and a
redactor that stops an exception's `toString()` carrying user data into a crash
report.

## The whole API

```dart
LogSystem.init();                                   // once, at startup

LogSystem.debug('cache miss');
LogSystem.info('sync: round finished');
LogSystem.warning('sync: retrying', error: e, stackTrace: s);
LogSystem.error('sync: round failed', error: e, stackTrace: s);
LogSystem.fatal('db: unreadable', error: e, stackTrace: s);
```

That is deliberately all of it. The repository, the sinks and the redactor are
unexported: they are the reason this package exists rather than a snippet, but
a caller who has to assemble them is a caller who can assemble them *wrong* —
and getting the crash-reporter egress wrong is the failure it was extracted to
prevent. Configuration is flags, not objects.

**Logging before `init` is a silent no-op.** Unit tests that construct
production types directly never stand up the app's wiring, and a log line must
not be why one of them throws. Do not "fix" this by asserting initialisation.

Calling `init` again **replaces** the wiring, which is a deliberate departure
from what `init` usually implies: an integration harness passes
`reportCrashes: false` to keep a test build off the real crash reporter, and
throwing on the second call would take that away.

### Flags

| flag | default | what it decides |
|---|---|---|
| `forwardInfo` | `false` | whether an `info` line becomes a crash-reporter breadcrumb. Cheap — a breadcrumb only surfaces alongside a later crash — but still an egress. Off leaves `info` device-local, like `debug`. |
| `reportCrashes` | `true` | off wires no crash reporter at all. Every level then stays device-local. |
| `customKeys` | `{}` | stamped on the crash reporter as-is. **Bypasses redaction**, so only provably non-identifying values belong here — a commit sha, a release channel. |
| `deferredCustomKeys` | `null` | for a key needing a platform round-trip. Lands a moment after launch, so a crash in the first frames may miss it. |

### No Firebase at all

`init` needs `Firebase.initializeApp()` to have run, because setting the
collection flag means touching `FirebaseCrashlytics`. When it has not — an
integration harness booting the real graph against no backend — `init` detects
it (`Firebase.apps` is a registry read, safe before initialisation), wires the
console alone, and says so through the console.

Nothing for the app to branch on, and nothing to pass.

Neither obvious alternative works. **Throwing** would let a logging library
stop an app from starting, and would break the harness this case exists for.
**Asserting** is the same thing wearing a debug badge — it aborts the rest of
`init`, so the harness gets an exception *and* no logging. **Silence** would let
an app that simply forgot `initializeApp()` get no crash reporting and no
complaint.

⚠️ `init(reportCrashes: false)` is a different case: Firebase *is* there, and is
being told to stay quiet.

### The console never reaches a release build

`logger`'s default `DevelopmentFilter` wraps its whole decision in
`assert(() { … }())` — "In release mode ALL logs are omitted", in its own words
— so every level is dropped with asserts off, not just `debug`. There is no
flag for this and there was never anything for one to do.

Worth stating rather than assuming, because the sibling hazard looks identical
and is real: `FlutterError.presentError` in release goes to
`debugPrintStack(label: exception.toString())` → `print`, and `debugPrint` is
**not** assert-gated. Raw exceptions do reach logcat / oslog — that way, never
this one. See the framework-fatal section below.

## Severity routing

| level | console | crash reporter |
|---|---|---|
| `debug` | yes, and never in release | never |
| `info` | yes | breadcrumb, if `forwardInfo` |
| `warning` | yes | breadcrumb — never a fault entry |
| `error` / `fatal` | yes | `recordError`, non-fatal / fatal |

`info` takes no error object on purpose: it describes an expected condition. An
exception worth keeping makes it a `warning` or an `error`.

## Redaction

Everything crossing to the crash reporter is reduced first, and no caller can
opt out. An exception arrives as a surrogate carrying its runtime type name
plus, for a few allow-listed types, one closed-vocabulary structural field:

| type | kept | dropped |
|---|---|---|
| `PlatformException` | `code`, when it looks like an opaque token | `message`, `details` |
| `SocketException` / `FileSystemException` / `OSError` | `errno` | `address`, `path`, `message` |
| everything else | type name only | everything |

The redactor never calls `toString()` on the untrusted original — it reads
`runtimeType` and typed getters only, so a hostile `toString()` can neither
leak through nor throw. The surrogate's own `toString()` **leads with the type
name** so the reporter's non-fatal grouping still separates distinct error
types instead of collapsing them into one issue (flutterfire #3310).

The arms cover `dart:io` and `package:flutter` only — types every consumer
already has. An arm for another package's exception would make that package a
dependency of everyone, so an app that wants a distinction preserved should
translate at its own boundary into a domain type whose **name** carries it:
`CloudOfflineException` reads better in a crash report than
`SocketException errno=61` anyway.

## The two uncaught-error handlers

`init` installs both — `FlutterError.onError` and
`PlatformDispatcher.instance.onError` — so nothing is copied into an app's
bootstrap. Pass `installErrorHandlers: false` if the app installs its own, and
note that this means `init` **reassigns two global handlers**.

They live here because leaving them to each app is how two of them ended up
disagreeing about which uncaught errors count as crashes. Four judgements are
baked in:

**Release only, for `FlutterError.onError`.** In debug it already defaults to
`FlutterError.presentError`, so overriding it there reimplements the default —
and presenting *and* logging prints the same error twice while the reporter is
disabled. Installing it release-only also keeps `presentError` out of release
structurally: there `dumpErrorToConsole` takes the
`debugPrintStack(label: exception.toString())` branch, and `debugPrint` is not
assert-gated, so it would put the raw exception on logcat / oslog.

**`details.silent` decides fatal.** The framework sets it at the throw site —
"errors that could be triggered by environmental conditions (as opposed to
logic errors)"; the HTTP library sets it so a 404 on flaky wifi does not read
like a bug — and honours it in `dumpErrorToConsole`. FlutterFire's
`recordFlutterError` never looks at it, so its documented pattern files every
one of them as a crash. `fatal: true` feeds crash-free users, the number a
release is judged by.

**The async handler is never fatal.** It has no `silent` to consult and it
returns `true` — the app saying it has handled the error and will keep running.
Filing that as a crash contradicts the line above it.

**`details.exception` is passed, not `details`**, which is what drops `context`
and `informationCollector`: both are `DiagnosticsNode`s that can carry
widget-tree property values, such as a `Text` widget's content in an overflow
assertion.
