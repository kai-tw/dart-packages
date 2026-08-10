# log_system

Structured logging with a **redacted** crash-reporting egress.

Extracted from NovelGlide, where it had grown the parts that only show up once
an app has shipped: per-severity routing, a release-only egress gate, and a
redactor that stops an exception's `toString()` carrying user data into a crash
report.

## Wiring

The facade is static, but it is **not** resolved through a service locator —
that would make one app's DI container a dependency of every consumer. Install
it once at startup with whatever the host app already uses:

```dart
LogSystem.install(
  FanOutLogRepository(
    console: LoggerAdapter(),
    report: FirebaseCrashlyticsAdapter(
      FirebaseCrashlytics.instance,
      customKeys: <String, String>{'git_sha': BuildInfo.gitSha},
    ),
  ),
);
```

Then everything calls `LogSystem.debug/info/warning/error/fatal/event`.

**Logging before `install` is a silent no-op.** Unit tests that construct
production types directly never stand up the app's wiring, and a log line must
not be why one of them throws. Do not "fix" this by asserting installation.

Pass `report: null` for a build with no crash reporter — every level then stays
device-local.

## Severity routing

| level | console | crash reporter |
|---|---|---|
| `debug` | yes, and never in release | never |
| `info` | yes | breadcrumb, if `forwardInfo` |
| `warning` | yes | breadcrumb — never a fault entry |
| `error` / `fatal` | yes | `recordError`, non-fatal / fatal |
| `event` | yes | never |

`event` is **not** analytics dispatch. Nothing here reaches an analytics
backend, and wiring it to one is a consent decision, not a plumbing change.

## Redaction

Everything crossing to the crash reporter goes through `LogErrorRedactor`, and
no caller can opt out. An exception is reduced to a surrogate carrying its
runtime type name plus, for a few allow-listed types, one closed-vocabulary
structural field:

| type | kept | dropped |
|---|---|---|
| `PlatformException` | `code`, when it looks like an opaque token | `message`, `details` |
| `SocketException` / `FileSystemException` / `OSError` | `errno` | `address`, `path`, `message` |
| anything implementing `LogDiagnosticCode` | `diagnosticCode`, band-clamped | everything else |
| everything else | type name only | everything |

The redactor never calls `toString()` on the untrusted original — it reads
`runtimeType` and typed getters only, so a hostile `toString()` can neither
leak through nor throw. The surrogate's own `toString()` **leads with the type
name** so the reporter's non-fatal grouping still separates distinct error
types instead of collapsing them into one issue (flutterfire #3310).

### Teaching it about a type this package cannot depend on

```dart
LogErrorRedactor.addRule(
  LogErrorRule(
    matches: (Object e) => e is DioException,
    describe: (Object e, String type) =>
        '$type status=${(e as DioException).response?.statusCode ?? '-'}',
  ),
);
```

Rules run before the built-in arms, in registration order, so one can also
override a built-in. `describe` must lead with `type`, or grouping breaks.

`DioException` is a rule rather than a built-in arm on purpose: a built-in
would drag `package:dio` into consumers that removed their HTTP client.

## The framework-fatal path

`FlutterError.onError` does not go through the facade. Redact its details
before handing them over:

```dart
FlutterError.onError = (FlutterErrorDetails details) {
  if (kDebugMode) {
    FlutterError.presentError(details);
  }
  FirebaseCrashlytics.instance.recordFlutterFatalError(
    LogErrorRedactor.redactDetails(details),
  );
};
```

`redactDetails` drops `context` and `informationCollector` as well as reducing
the exception — both are `DiagnosticsNode`s that can carry widget-tree property
values, such as a `Text` widget's content in an overflow assertion.

`presentError` is gated on debug deliberately. In release
`dumpErrorToConsole` takes the `debugPrintStack(label: exception.toString())`
branch, and `debugPrint` is not assert-gated — so calling it unconditionally
prints the raw exception to logcat / oslog, which is the object the redactor
exists to stop, reaching a different sink.

## Console fidelity

`LoggerAdapter` forwards the **raw** error. The console is on-device developer
diagnostics, not a cloud egress. It is not invisible, though: in a release
build it reaches logcat / oslog, so an app whose log lines quote anything
user-derived should pass `suppressInRelease: true`, which drops everything
below `error` in release.
