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
  /// [suppressConsoleInRelease] — whether the console drops everything below
  /// `error` in a release build. "Device-local" is not "invisible": in release
  /// the console reaches logcat / oslog, readable through `adb logcat`, a bug
  /// report or a sysdiagnose.
  ///
  /// [reportCrashes] — off wires no crash reporter at all, which is what an
  /// integration harness wants. Every level then stays device-local.
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
  /// **Calling this again replaces the wiring** rather than throwing, which is
  /// a deliberate departure from what `init` usually implies: an integration
  /// harness re-inits with `reportCrashes: false` to keep a test build off the
  /// real crash reporter.
  static void init({
    bool forwardInfo = false,
    bool suppressConsoleInRelease = false,
    bool reportCrashes = true,
    Map<String, String> customKeys = const <String, String>{},
    Future<Map<String, String>> Function()? deferredCustomKeys,
    String? Function(Object error)? describeExtra,
  }) {
    LogErrorRedactor.describeExtra = describeExtra;
    _instance = LogSystem(
      LogRepositoryImpl(
        console: LoggerAdapter(suppressInRelease: suppressConsoleInRelease),
        report: reportCrashes
            ? FirebaseCrashlyticsAdapter(
                FirebaseCrashlytics.instance,
                forwardInfo: forwardInfo,
                customKeys: customKeys,
                deferredCustomKeys: deferredCustomKeys,
              )
            : null,
      ),
    );
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
