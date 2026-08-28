/// A non-fatal failure observed internally.
///
/// Every occurrence already has a safe fallback in effect by the time this
/// is emitted — [ConnectivityRepository.errors] exists purely so a consumer
/// can decide for itself whether and how to log or react to it. This
/// package has no logging dependency of its own; wiring this into whatever
/// the app already uses (`log_system`, Crashlytics, a debug banner) is the
/// consumer's call, not something this package makes for it.
class ConnectivityError {
  const ConnectivityError(this.context, this.error, this.stackTrace);

  /// What was happening when [error] was caught, and what fallback took
  /// over — e.g. `'Connectivity seed failed → fallback offline'`.
  final String context;

  final Object error;
  final StackTrace stackTrace;

  @override
  String toString() => '$context: $error';
}
