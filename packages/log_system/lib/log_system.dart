/// Structured logging with a redacted crash-reporting egress.
///
/// - [LogSystem] — `init` once at startup, then `debug` / `info` / `warning` /
///   `error` / `fatal` / `event` from anywhere.
/// - [LoggableException] — the base an app's own exceptions extend, so they
///   survive redaction with one structural code instead of a type name alone.
/// - [LogSink] / [LogEntry] / [LogLevel] — the destination a host app
///   registers to route logging into its own backend, or to let its own tests
///   see that a fault was logged.
///
/// The repository, the sinks and the redactor stay unexported. They are the
/// reason this package exists rather than a snippet, but a caller who has to
/// assemble them is a caller who can assemble them *wrong* — and getting the
/// crash-reporter egress wrong is the failure it was extracted to prevent.
/// Configuration is flags on [LogSystem.init] instead, which is also what
/// keeps the host app out of this package's DI.
///
/// [LogSink] is the one exception, and it is one because it cannot make that
/// mistake: it is a destination, not a collaborator in the graph, and what it
/// receives has **already** crossed the redaction boundary. Observing the
/// egress and being able to widen it are different powers, and only the
/// second was ever the thing being withheld.
library;

export 'src/domain/log_entry.dart' show LogEntry, LogLevel;
export 'src/domain/log_sink.dart' show LogSink;
export 'src/domain/loggable_exception.dart' show LoggableException;
export 'src/log_system.dart' show LogSystem;
