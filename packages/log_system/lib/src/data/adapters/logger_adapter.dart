import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import '../log_data_source.dart';

/// Console (device-local) sink.
///
/// Deliberately forwards the **raw** error at full fidelity — redaction is for
/// the crash reporter only. The console is on-device developer diagnostics,
/// not a cloud egress, so CWE-532 does not apply; stripping the error here
/// would cost debuggability and buy nothing.
///
/// **Nothing here reaches a release build.** `logger`'s default
/// `DevelopmentFilter` wraps its whole decision in `assert(() { … }())` — "In
/// release mode ALL logs are omitted", in its own words — so every level is
/// dropped with asserts off, not just `debug`.
///
/// That is worth stating rather than assuming, because the sibling hazard is
/// real and looks identical: `FlutterError.presentError` in release goes to
/// `debugPrintStack(label: exception.toString())` → `print`, and `debugPrint`
/// is **not** assert-gated. So an app that routes uncaught errors through
/// `presentError` unconditionally does put raw exceptions on logcat / oslog —
/// via that path, never via this one.
///
/// A `suppressInRelease` flag lived here briefly. It was dead: it gated levels
/// the filter had already dropped.
class LoggerAdapter extends LogDataSource {
  /// [output] is a seam for this package's own tests only — production never
  /// passes it, and `Logger`'s own default (`ConsoleOutput`, printing to the
  /// system console) is what a null value falls back to, unchanged from
  /// before this parameter existed. A test supplies `MemoryOutput()` to read
  /// back what was actually printed — the only way to assert, rather than
  /// merely assume, that this adapter forwards an error at full fidelity
  /// while [FirebaseCrashlyticsAdapter] redacts the same object.
  LoggerAdapter({LogOutput? output})
    : _logger = Logger(
        printer: PrettyPrinter(
          excludePaths: <String>['package:log_system'],
          methodCount: 50,
          errorMethodCount: 50,
        ),
        output: output,
      ),
      _infoLogger = Logger(
        printer: PrettyPrinter(
          methodCount: 0,
          excludePaths: <String>['package:log_system'],
        ),
        output: output,
      );

  final Logger _logger;
  final Logger _infoLogger;

  @override
  Future<void> debug(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    // Local development diagnostics. The filter drops this in release too,
    // but skipping the call means not building the message at all.
    if (kReleaseMode) {
      return;
    }
    return _logger.d(message, error: error, stackTrace: stackTrace);
  }

  @override
  Future<void> info(String message) async {
    return _infoLogger.i(message);
  }

  @override
  Future<void> warning(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    return _logger.w(message, error: error, stackTrace: stackTrace);
  }

  @override
  Future<void> error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    return _logger.e(message, error: error, stackTrace: stackTrace);
  }

  @override
  Future<void> fatal(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    return _logger.f(message, error: error, stackTrace: stackTrace);
  }

  @override
  Future<void> event(String name, {Map<String, Object>? parameters}) async {
    return _logger.i('Event: $name\n$parameters');
  }
}
