import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'fan_out_log_repository.dart';
import 'firebase_crashlytics_adapter.dart';
import 'log_error_redactor.dart';
import 'log_repository.dart';
import 'logger_adapter.dart';

/// The whole public surface of this package.
///
/// Static, and **not** resolved through a service locator. The version this
/// was extracted from read `sl<LogSystem>()` on every call, which is fine
/// inside one app and impossible in a package: it would make `get_it` a
/// dependency of every consumer and hard-code one app's locator instance.
///
/// It also takes no objects. [init] takes flags and builds the sinks itself,
/// so there is no wiring for a host to get wrong — assembling a
/// console-plus-crash-reporter fan-out by hand is exactly how the egress ends
/// up unredacted, which is the failure this package exists to prevent.
///
/// **Logging before [init] is a silent no-op, on purpose.** Unit tests that
/// construct production types directly never stand up the app's wiring, and a
/// log line must not be the reason one of them throws. Do not "fix" it by
/// asserting initialisation.
class LogSystem {
  LogSystem._();

  static LogRepository? _repository;

  /// Wires the log system. Call once, during startup, before anything logs.
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
  /// [customKeys] are stamped on the crash reporter as-is and **bypass
  /// redaction entirely**, so only provably non-identifying values belong
  /// there — a commit sha, a release channel. [deferredCustomKeys] is for one
  /// that needs a platform round-trip; it lands a moment after launch, so a
  /// crash in the first frames may miss it.
  ///
  /// [describeExtra] keeps one structural field from an error type this
  /// package cannot name. It is reduced to a type name by default, and the
  /// built-in arms cover `dart:io` and `package:flutter` only — an arm for an
  /// HTTP client's exception would make that client a dependency of every
  /// consumer. The host app already has it, so the host app describes it:
  ///
  /// ```dart
  /// describeExtra: (Object e) => switch (e) {
  ///   DioException() => 'status=${e.response?.statusCode ?? '-'}',
  ///   _ => null,
  /// },
  /// ```
  ///
  /// Return the **field only** — the type name is prepended for you, so a
  /// describer cannot break crash-report grouping. Returning null falls
  /// through to the built-in arms. It must not throw, and it must not call
  /// `toString()` on the error; it is handed an untrusted object, and its
  /// output is still gated for path- and sentence-shaped values before
  /// anything crosses.
  ///
  /// **Calling this again replaces the wiring** rather than throwing, which is
  /// a deliberate departure from what `init` usually implies: an integration
  /// harness swaps in a reporter-less setup to keep a test build off the real
  /// crash reporter.
  static void init({
    bool forwardInfo = false,
    bool suppressConsoleInRelease = false,
    bool reportCrashes = true,
    Map<String, String> customKeys = const <String, String>{},
    Future<Map<String, String>> Function()? deferredCustomKeys,
    String? Function(Object error)? describeExtra,
  }) {
    LogErrorRedactor.describeExtra = describeExtra;
    _repository = FanOutLogRepository(
      console: LoggerAdapter(suppressInRelease: suppressConsoleInRelease),
      report: reportCrashes
          ? FirebaseCrashlyticsAdapter(
              FirebaseCrashlytics.instance,
              forwardInfo: forwardInfo,
              customKeys: customKeys,
              deferredCustomKeys: deferredCustomKeys,
            )
          : null,
    );
  }

  /// Wires a repository directly. **Package-internal test seam** — the type it
  /// takes is not exported, so this is unusable from outside.
  @visibleForTesting
  static void initWithRepository(LogRepository repository) =>
      _repository = repository;

  /// Drops the wiring. Test seam — production code never calls it.
  @visibleForTesting
  static void reset() => _repository = null;

  /// Local-only, for expected non-error events — a user cancelling, an
  /// expected offline transition. Never leaves the device, and is skipped
  /// entirely in release.
  static void debug(String message, {Object? error, StackTrace? stackTrace}) {
    _repository?.debug(message, error: error, stackTrace: stackTrace);
  }

  /// Takes no error object, and that asymmetry is deliberate: `info` describes
  /// an expected condition. An exception worth keeping makes it a [warning] or
  /// an [error].
  static void info(String message) {
    _repository?.info(message);
  }

  /// Something went wrong but the app carried on. Reaches the crash reporter
  /// as a breadcrumb, never as a fault entry.
  static void warning(String message, {Object? error, StackTrace? stackTrace}) {
    _repository?.warning(message, error: error, stackTrace: stackTrace);
  }

  /// A fault worth a report. [error] is reduced to a non-identifying surrogate
  /// on the way out — pass the exception itself rather than describing it in
  /// [message], which crosses verbatim.
  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    _repository?.error(message, error: error, stackTrace: stackTrace);
  }

  /// As [error], reported fatal.
  static void fatal(String message, {Object? error, StackTrace? stackTrace}) {
    _repository?.fatal(message, error: error, stackTrace: stackTrace);
  }
}
