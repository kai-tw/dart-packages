/// Where `LogSystem` sends a log line, after severity routing.
///
/// Separate from `LogDataSource` because the two answer different questions:
/// a data source is *one* destination, this is the policy for how many of them
/// a given severity reaches. `debug` going nowhere near the crash reporter is
/// a decision that lives here, not in each sink.
abstract class LogRepository {
  Future<void> debug(String message, {Object? error, StackTrace? stackTrace});

  Future<void> info(String message);

  Future<void> warning(String message, {Object? error, StackTrace? stackTrace});

  Future<void> error(String message, {Object? error, StackTrace? stackTrace});

  Future<void> fatal(String message, {Object? error, StackTrace? stackTrace});

  Future<void> event(String name, {Map<String, Object>? parameters});
}
