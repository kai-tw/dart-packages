/// A non-fatal failure observed internally.
///
/// Every occurrence already has a safe fallback in effect by the time this
/// is emitted — [ConnectivityRepository.exceptions] exists purely so a
/// consumer can decide for itself whether and how to log or react to it.
/// This package has no logging dependency of its own; wiring this into
/// whatever the app already uses (`log_system`, Crashlytics, a debug
/// banner) is the consumer's call, not something this package makes for it.
///
/// `implements Exception`, not `extends Error` — this is an expected,
/// already-recovered-from failure a consumer may want to know about, not a
/// programmer bug that should propagate to a zone handler.
///
/// `sealed`, with one concrete subclass per distinct fault this package can
/// actually catch — a consumer's `switch` is a coverage contract instead of
/// a guess from a free-text message.
///
/// Unlike a typical project-scoped domain exception, a subclass here still
/// carries the raw caught [exception] and [stackTrace] rather than only
/// domain-relevant fields: this package has no redactor of its own to
/// translate a platform fault safely first, so the raw value is the
/// consumer's own logger's to read (and redact, if it needs to).
sealed class ConnectivityException implements Exception {
  const ConnectivityException(this.exception, this.stackTrace);

  final Object exception;
  final StackTrace stackTrace;

  @override
  String toString() => '$runtimeType: $exception';
}

/// The seed probe — the first status fetch a repository makes at
/// construction — faulted. The repository fell back to
/// `ConnectivityStatus.offline` until a later stream emission or
/// `getStatus()` call corrects it.
final class ConnectivitySeedException extends ConnectivityException {
  const ConnectivitySeedException(super.exception, super.stackTrace);
}

/// The adapter's `observeConnectivity` stream itself emitted an error — the
/// repository kept the last known status rather than propagating it onto
/// `ConnectivityRepository.observeStatus()`.
final class ConnectivityStreamException extends ConnectivityException {
  const ConnectivityStreamException(super.exception, super.stackTrace);
}

/// The native metered-probe channel faulted — e.g. a missing
/// `ACCESS_NETWORK_STATE` permission surfacing as a `PlatformException` on
/// Android. The repository degraded to its connection-type heuristic.
final class ConnectivityMeteredProbeException extends ConnectivityException {
  const ConnectivityMeteredProbeException(super.exception, super.stackTrace);
}

/// The native metered-probe channel outran its timeout — same heuristic
/// fallback as [ConnectivityMeteredProbeException].
final class ConnectivityMeteredProbeTimeoutException
    extends ConnectivityException {
  const ConnectivityMeteredProbeTimeoutException(
    super.exception,
    super.stackTrace,
  );
}
