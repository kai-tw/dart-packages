/// A non-fatal failure observed internally.
///
/// Every occurrence already has a safe fallback in effect by the time this
/// is emitted — [ConnectivityRepository.exceptions] exists purely so a
/// consumer can decide for itself whether and how to log or react to it.
/// This package has no logging dependency of its own; wiring this into
/// whatever the app already uses (`log_system`, Crashlytics, a debug
/// banner) is the consumer's call, not something this package makes for it.
///
/// Named `ConnectivityException`, not `ConnectivityError` — this is an
/// expected, already-recovered-from failure a consumer may want to know
/// about, not a Dart `Error` (a programmer bug that should propagate to a
/// zone handler, never be caught and reported like this).
class ConnectivityException {
  const ConnectivityException(this.context, this.exception, this.stackTrace);

  /// What was happening when [exception] was caught, and what fallback took
  /// over — e.g. `'Connectivity seed failed → fallback offline'`.
  final String context;

  final Object exception;
  final StackTrace stackTrace;

  @override
  String toString() => '$context: $exception';
}
