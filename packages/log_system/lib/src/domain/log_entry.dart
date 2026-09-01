/// One log line as it reaches a `LogSink`.
///
/// [redactedError] and [parameters] are mutually exclusive: the first is set
/// only for the levels that carry an error object, the second only for
/// [LogLevel.event]. They are one class rather than two because a fake sink
/// wants a single list in call order — `warning` then `event` then `error` is
/// an assertion two separate callbacks could not express.
final class LogEntry {
  const LogEntry({
    required this.level,
    required this.message,
    this.redactedError,
    this.stackTrace,
    this.parameters,
  });

  final LogLevel level;

  /// Crosses **verbatim**, exactly as it does to the crash reporter. Keeping
  /// identifiers out of a log message is an authoring-time discipline here as
  /// it is there; no runtime flag can fix a message that was written wrong.
  final String message;

  /// The error object after the redactor, as text — a runtime type name plus
  /// at most one closed-vocabulary structural field (`errno=2`, `code=404`).
  /// Null when the call carried no error object.
  ///
  /// **Not the original.** A sink receiving the raw object would be a way
  /// around the redaction boundary this package exists to hold, so the door is
  /// shut here rather than left to each host's discretion.
  ///
  /// The cost is real, and it is the intended incentive: an app asserting
  /// *which* failure was logged can only distinguish what the redactor can
  /// distinguish, which is the exception's type and its `diagnosticCode`. A
  /// test that cannot tell two failures apart is describing a pair of
  /// exceptions the crash reporter cannot tell apart either — split the type
  /// rather than widen this field.
  final String? redactedError;

  /// Passed through unreduced. A stack trace names the app's own frames, not
  /// its user's data, and the crash reporter already receives it as-is.
  final StackTrace? stackTrace;

  /// [LogLevel.event] only; null at every other level. Host-authored values,
  /// forwarded as given — the same authoring-time discipline as [message].
  final Map<String, Object>? parameters;

  @override
  String toString() {
    final StringBuffer buffer = StringBuffer('${level.name}: $message');
    if (redactedError != null) {
      buffer.write(' — $redactedError');
    }
    if (parameters != null) {
      buffer.write(' $parameters');
    }
    return buffer.toString();
  }
}

/// What a [LogEntry] was logged at.
///
/// [event] is not a severity — it is a separate channel that happens to share
/// this enum, and the routing behind it differs in kind rather than in degree:
/// it never reaches the crash reporter at any setting. It is here so a sink
/// observes one ordered stream instead of two.
enum LogLevel { debug, info, warning, error, fatal, event }
