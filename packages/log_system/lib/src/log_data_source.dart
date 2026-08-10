/// One destination a log line can reach.
///
/// Implementations are the console and the crash reporter. Every method
/// returns `Future<void>` rather than `void` even where the work is
/// synchronous, so a sink that later becomes async does not change this
/// interface and every fan-out can await uniformly.
abstract class LogDataSource {
  Future<void> debug(String message, {Object? error, StackTrace? stackTrace});

  Future<void> info(String message);

  Future<void> warning(String message, {Object? error, StackTrace? stackTrace});

  Future<void> error(String message, {Object? error, StackTrace? stackTrace});

  Future<void> fatal(String message, {Object? error, StackTrace? stackTrace});
}
