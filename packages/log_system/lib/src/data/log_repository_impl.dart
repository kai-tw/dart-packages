import '../domain/log_repository.dart';
import 'log_data_source.dart';

/// Sends each severity to the sinks that severity is allowed to reach.
///
/// The routing is the whole reason this layer exists, and flattening it is how
/// a local debug line ends up in a 90-day retained sink:
///
/// | level | console | crash reporter |
/// |---|---|---|
/// | `debug` | yes (never in release) | never |
/// | `info` | yes | breadcrumb, if the sink forwards it |
/// | `warning` | yes | breadcrumb — never a fault entry |
/// | `error` / `fatal` | yes | `recordError`, non-fatal / fatal |
/// | `event` | yes | never |
///
/// A failing sink rejects the combined future rather than being swallowed:
/// logging that silently stops working is worse than logging that throws
/// somewhere a zone handler can see it.
class LogRepositoryImpl extends LogRepository {
  LogRepositoryImpl({required LogDataSource console, LogDataSource? report})
    : _console = console,
      _report = report;

  final LogDataSource _console;

  /// Null in a build with no crash reporter at all — a test harness, or an
  /// app that has not wired one yet. Every level then stays device-local.
  final LogDataSource? _report;

  Future<void> _both(Future<void> Function(LogDataSource sink) call) async {
    final LogDataSource? report = _report;
    await Future.wait(<Future<void>>[
      call(_console),
      if (report != null) call(report),
    ]);
  }

  @override
  Future<void> debug(String message, {Object? error, StackTrace? stackTrace}) {
    // Console only, by routing rather than by the sink's discretion.
    return _console.debug(message, error: error, stackTrace: stackTrace);
  }

  @override
  Future<void> info(String message) {
    return _both((LogDataSource sink) => sink.info(message));
  }

  @override
  Future<void> warning(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    return _both(
      (LogDataSource sink) =>
          sink.warning(message, error: error, stackTrace: stackTrace),
    );
  }

  @override
  Future<void> error(String message, {Object? error, StackTrace? stackTrace}) {
    return _both(
      (LogDataSource sink) =>
          sink.error(message, error: error, stackTrace: stackTrace),
    );
  }

  @override
  Future<void> fatal(String message, {Object? error, StackTrace? stackTrace}) {
    return _both(
      (LogDataSource sink) =>
          sink.fatal(message, error: error, stackTrace: stackTrace),
    );
  }

  @override
  Future<void> event(String name, {Map<String, Object>? parameters}) {
    // Console only. Routing an event to the crash reporter is how a log level
    // quietly becomes analytics.
    return _console.event(name, parameters: parameters);
  }
}
