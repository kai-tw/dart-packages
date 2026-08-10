/// Structured logging with a redacted crash-reporting egress.
///
/// Two symbols, and deliberately no more:
///
/// - [LogSystem] — `init` once at startup, then `debug` / `info` / `warning` /
///   `error` / `fatal` / `event` from anywhere.
/// - [LoggableException] — the base an app's own exceptions extend, so they
///   survive redaction with one structural code instead of a type name alone.
///
/// The repository, the sinks and the redactor stay unexported. They are the
/// reason this package exists rather than a snippet, but a caller who has to
/// assemble them is a caller who can assemble them *wrong* — and getting the
/// crash-reporter egress wrong is the failure it was extracted to prevent.
/// Configuration is flags on [LogSystem.init] instead, which is also what
/// keeps the host app out of this package's DI.
library;

export 'src/domain/loggable_exception.dart' show LoggableException;
export 'src/log_system.dart' show LogSystem;
