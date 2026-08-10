import 'package:flutter/foundation.dart';

import 'log_repository.dart';

/// The only symbol callers touch. Static, and **not** resolved through a
/// service locator.
///
/// The original version read `sl<LogSystem>()` on every call. That is fine
/// inside one app and impossible in a package: it would make `get_it` a
/// dependency of every consumer and hard-code one app's locator instance.
/// [init] replaces it — a host app wires its own graph however it likes
/// (get_it, Riverpod, a bare constructor) and hands the result here once.
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
  /// **Replacing an existing repository is allowed**, which is a deliberate
  /// departure from what `init` usually implies. An integration harness swaps
  /// in a no-op repository to keep a test build off the real crash reporter,
  /// and throwing on a second call would take that away.
  static void init(LogRepository repository) => _repository = repository;

  /// Drops the wiring. Test seam — production code never calls it.
  @visibleForTesting
  static void reset() => _repository = null;

  /// Whether a repository has been wired. A caller never needs this; it exists
  /// so a harness can assert its own setup ran.
  static bool get isInitialized => _repository != null;

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

  /// A named occurrence, console only. This is **not** analytics dispatch —
  /// nothing here reaches an analytics backend, and wiring it to one is a
  /// consent decision, not a plumbing change.
  static void event(String name, {Map<String, Object>? parameters}) {
    _repository?.event(name, parameters: parameters);
  }
}
