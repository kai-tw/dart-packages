import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import 'log_data_source.dart';

/// Console (device-local) sink.
///
/// Deliberately forwards the **raw** error at full fidelity — redaction is for
/// the crash reporter only. The console is on-device developer diagnostics,
/// not a cloud egress, so CWE-532 does not apply; stripping the error here
/// would cost debuggability and buy nothing.
///
/// ⚠️ Device-local is not the same as invisible. `debug` is skipped entirely in
/// release, but the remaining levels do print in a release build, and on a
/// device that means logcat / oslog — reachable through `adb logcat`, a bug
/// report or a sysdiagnose. Pass [suppressInRelease] to drop everything below
/// `error` in release when the app's log lines carry values it would rather
/// not put there.
class LoggerAdapter extends LogDataSource {
  LoggerAdapter({this.suppressInRelease = false});

  /// Whether `info` / `warning` are dropped in release builds too.
  final bool suppressInRelease;

  final Logger _logger = Logger(
    printer: PrettyPrinter(
      excludePaths: <String>['package:log_system'],
      methodCount: 50,
      errorMethodCount: 50,
    ),
  );

  final Logger _infoLogger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      excludePaths: <String>['package:log_system'],
    ),
  );

  bool get _quiet => kReleaseMode && suppressInRelease;

  @override
  Future<void> debug(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    // Local development diagnostics — never emitted in release, whatever
    // [suppressInRelease] says.
    if (kReleaseMode) {
      return;
    }
    return _logger.d(message, error: error, stackTrace: stackTrace);
  }

  @override
  Future<void> info(String message) async {
    if (_quiet) {
      return;
    }
    return _infoLogger.i(message);
  }

  @override
  Future<void> warning(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    if (_quiet) {
      return;
    }
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
}
