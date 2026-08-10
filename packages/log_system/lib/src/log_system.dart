import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'data/adapters/firebase_crashlytics_adapter.dart';
import 'data/adapters/log_error_redactor.dart';
import 'data/adapters/logger_adapter.dart';
import 'data/log_repository_impl.dart';
import 'domain/log_repository.dart';

/// The whole public surface of this package.
///
/// ## Why the statics wrap a private instance
///
/// The layers below ([LogRepository], the sinks, the redactor) are a clean
/// architecture graph, and the instance methods here are its entry point. But
/// a log line is called from everywhere, and threading an instance to every
/// call site buys nothing — so the graph is built once by [init] and reached
/// through statics.
///
/// [init] is what stops that being a DI problem for the host app. The version
/// this was extracted from resolved `sl<LogSystem>()` on every call, which
/// inside one app is fine and in a package is impossible: it would make
/// `get_it` a dependency of every consumer and hard-code one app's locator.
/// Here the app supplies flags, and the wiring is this file's business.
///
/// **Logging before [init] is a silent no-op, on purpose.** Unit tests that
/// construct production types directly never stand up the app's wiring, and a
/// log line must not be the reason one of them throws. Do not "fix" it by
/// asserting initialisation.
class LogSystem {
  LogSystem(this._repository);

  final LogRepository _repository;

  void _debug(String message, {Object? error, StackTrace? stackTrace}) =>
      _repository.debug(message, error: error, stackTrace: stackTrace);

  void _info(String message) => _repository.info(message);

  void _warning(String message, {Object? error, StackTrace? stackTrace}) =>
      _repository.warning(message, error: error, stackTrace: stackTrace);

  void _error(String message, {Object? error, StackTrace? stackTrace}) =>
      _repository.error(message, error: error, stackTrace: stackTrace);

  void _fatal(String message, {Object? error, StackTrace? stackTrace}) =>
      _repository.fatal(message, error: error, stackTrace: stackTrace);

  void _event(String name, {Map<String, Object>? parameters}) =>
      _repository.event(name, parameters: parameters);

  /// Static members

  static LogSystem? _instance;

  /// Builds the graph and wires it. Call once, during startup, before
  /// anything logs.
  ///
  /// [forwardInfo] — whether an `info` line becomes a crash-reporter
  /// breadcrumb. A breadcrumb only ever surfaces alongside a later crash, so
  /// it is cheap, but it is still an egress: an app whose `info` lines quote
  /// anything user-derived wants this off, which leaves `info` device-local
  /// exactly like `debug`.
  ///
  /// [reportCrashes] — off keeps every level device-local **and switches
  /// Crashlytics collection off at the SDK**. Gating what this package sends
  /// does nothing about the native crash capture, which runs with no Dart code
  /// involved, so the switch has to be thrown either way.
  ///
  /// Collection is therefore set on every [init], to whatever `reportCrashes &&
  /// kReleaseMode` comes to, and is never left at the SDK's default — which is
  /// on. **That means [init] requires `Firebase.initializeApp()` to have run**,
  /// and it throws if it has not.
  ///
  /// ⚠️ `reportCrashes: false` is **not** the "no Firebase" case — that
  /// one is detected, see below. This means Firebase *is* there and must be
  /// told to stay quiet: a beta build, a harness that stands Firebase up.
  /// Conflating the two is how this parameter first shipped, and it made the
  /// configuration that most needed to avoid Firebase the one that crashed on
  /// startup.
  ///
  /// [customKeys] are stamped on the crash reporter as-is and **bypass
  /// redaction entirely**, so only provably non-identifying values belong
  /// there — a commit sha, a release channel. [deferredCustomKeys] is for one
  /// that needs a platform round-trip; it lands a moment after launch, so a
  /// crash in the first frames may miss it.
  ///
  /// [describeExtra] keeps one structural field from an error type this
  /// package cannot name — the built-in arms cover `dart:io` and
  /// `package:flutter` only, because an arm for an HTTP client's exception
  /// would make that client a dependency of every consumer. Return the
  /// **field only**; the type name is prepended, so a describer cannot break
  /// crash-report grouping. An app's own exceptions should extend
  /// `LoggableException` instead of going through here.
  ///
  /// [installErrorHandlers] assigns `FlutterError.onError` and
  /// `PlatformDispatcher.instance.onError`. On by default, because leaving it
  /// to each app is how two of them ended up disagreeing about which uncaught
  /// errors count as crashes. Pass false only if the app installs its own —
  /// and note that this **reassigns two global handlers**, which is a side
  /// effect worth knowing [init] has.
  ///
  /// **Calling this again replaces the wiring** rather than throwing, which is
  /// a deliberate departure from what `init` usually implies: an integration
  /// harness re-inits to swap the real reporter out.
  ///
  /// ## When Firebase is absent
  ///
  /// [init] needs `Firebase.initializeApp()` to have run, because setting the
  /// collection flag means touching `FirebaseCrashlytics`. When it has not —
  /// an integration harness booting the real graph against no backend — this
  /// wires the console alone and says so through the console.
  ///
  /// Neither of the obvious alternatives works. **Throwing** would let a
  /// logging library stop an app from starting, a worse failure than the one
  /// it guards against, and it would break the harness this case exists for.
  /// **Asserting** is the same thing wearing a debug badge — it aborts the
  /// rest of `init`, so the harness gets an exception *and* no logging at all.
  /// **Degrading silently** would let an app that simply forgot
  /// `initializeApp()` get no crash reporting and no complaint.
  ///
  /// A warning through the sink that is definitely wired costs nothing in
  /// release, appears where a developer is already looking in debug, and
  /// leaves everything working either way.
  static void init({
    bool forwardInfo = false,
    bool reportCrashes = true,
    bool installErrorHandlers = true,
    Map<String, String> customKeys = const <String, String>{},
    Future<Map<String, String>> Function()? deferredCustomKeys,
    String? Function(Object error)? describeExtra,
  }) {
    LogErrorRedactor.describeExtra = describeExtra;

    // A registry read, not an app lookup, so it is safe before
    // `initializeApp()` — it answers with an empty list rather than throwing.
    final bool hasFirebase = Firebase.apps.isNotEmpty;

    _instance = LogSystem(
      LogRepositoryImpl(
        console: LoggerAdapter(),
        // Built even when it will send nothing, because building it is what
        // switches collection **off** at the SDK. Skipping it on
        // `reportCrashes: false` would leave the SDK default — on — and the
        // native layer captures a crash with no Dart code involved, so the
        // build that most wanted silence would be the one still reporting.
        report: hasFirebase
            ? FirebaseCrashlyticsAdapter(
                FirebaseCrashlytics.instance,
                enabled: reportCrashes && kReleaseMode,
                forwardInfo: forwardInfo,
                customKeys: customKeys,
                deferredCustomKeys: deferredCustomKeys,
              )
            : null,
      ),
    );

    if (installErrorHandlers) {
      _installErrorHandlers();
    }

    // After the wiring, deliberately — this is the one message that has to go
    // out through the sink it is complaining about.
    if (!hasFirebase) {
      warning(
        'log: no Firebase app, so nothing will be reported — console only',
      );
    }
  }

  /// The two handlers every uncaught throw arrives at, wired once here so two
  /// apps cannot drift apart on the judgements they involve. They did.
  static void _installErrorHandlers() {
    // Release only. In debug `FlutterError.onError` already defaults to
    // `FlutterError.presentError`, so overriding it there reimplements the
    // default — and presenting *and* logging prints the same error twice while
    // the reporter is disabled and there is nothing to report.
    //
    // It also keeps `presentError` out of release structurally. There
    // `dumpErrorToConsole` takes the `debugPrintStack(label:
    // exception.toString())` branch, and `debugPrint` is not assert-gated, so
    // it would put the raw exception on logcat / oslog — the object the
    // redaction exists to stop, reaching a different sink.
    if (kReleaseMode) {
      FlutterError.onError = (FlutterErrorDetails details) {
        // `details.silent` is the framework's own fatal/non-fatal signal, set
        // at the throw site: "errors that could be triggered by environmental
        // conditions (as opposed to logic errors)". The HTTP library sets it
        // so a 404 on flaky wifi does not read like a bug, and the framework
        // honours it in `dumpErrorToConsole`. FlutterFire's
        // `recordFlutterError` never looks at it, which is how its documented
        // pattern files every one of them as a crash — and `fatal: true` feeds
        // crash-free users, the number a release is judged by.
        //
        // `details.exception` rather than `details` is also what drops
        // `context` and `informationCollector`, both `DiagnosticsNode`s that
        // can carry widget-tree property values.
        if (details.silent) {
          error(
            'flutter: environmental framework error',
            error: details.exception,
            stackTrace: details.stack,
          );
          return;
        }
        fatal(
          'flutter: uncaught framework error',
          error: details.exception,
          stackTrace: details.stack,
        );
      };
    }

    // Unconditional, because Flutter installs nothing here by default.
    //
    // Not fatal, and there is no `silent` to consult on this path. `return
    // true` says the app has handled the error and will keep running, so
    // filing it as a crash would contradict the line above it.
    PlatformDispatcher.instance.onError = (Object err, StackTrace stack) {
      error('uncaught async error', error: err, stackTrace: stack);
      return true;
    };
  }

  /// Wires a repository directly, for **this package's own tests**.
  ///
  /// Not a seam for host apps, and structurally cannot be: [LogRepository] is
  /// unexported, so nothing outside can name the argument. An app that wants
  /// its logging quiet under test simply does not call [init] — every level is
  /// a no-op until it does.
  @visibleForTesting
  static void initWithRepositoryForTest(LogRepository repository) =>
      _instance = LogSystem(repository);

  /// Drops the wiring. Test seam — production code never calls it.
  @visibleForTesting
  static void reset() {
    _instance = null;
    LogErrorRedactor.describeExtra = null;
  }

  /// Local-only, for expected non-error events — a user cancelling, an
  /// expected offline transition. Never leaves the device, and is skipped
  /// entirely in release.
  static void debug(String message, {Object? error, StackTrace? stackTrace}) {
    _instance?._debug(message, error: error, stackTrace: stackTrace);
  }

  /// Takes no error object, and that asymmetry is deliberate: `info` describes
  /// an expected condition. An exception worth keeping makes it a [warning] or
  /// an [error].
  static void info(String message) {
    _instance?._info(message);
  }

  /// Something went wrong but the app carried on. Reaches the crash reporter
  /// as a breadcrumb, never as a fault entry.
  static void warning(String message, {Object? error, StackTrace? stackTrace}) {
    _instance?._warning(message, error: error, stackTrace: stackTrace);
  }

  /// A fault worth a report. [error] is reduced to a non-identifying surrogate
  /// on the way out — pass the exception itself rather than describing it in
  /// [message], which crosses verbatim.
  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    _instance?._error(message, error: error, stackTrace: stackTrace);
  }

  /// As [error], reported fatal.
  static void fatal(String message, {Object? error, StackTrace? stackTrace}) {
    _instance?._fatal(message, error: error, stackTrace: stackTrace);
  }

  /// A named occurrence, console only.
  ///
  /// **This is not analytics dispatch.** Nothing here reaches an analytics
  /// backend — the level exists so an app has one place to route to one
  /// later, and wiring that is a consent decision rather than a plumbing
  /// change.
  static void event(String name, {Map<String, Object>? parameters}) {
    _instance?._event(name, parameters: parameters);
  }
}
