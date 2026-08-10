/// Structured logging with a redacted crash-reporting egress.
///
/// The entire public surface is [LogSystem] — `init` once at startup, then
/// `debug` / `info` / `warning` / `error` / `fatal` from anywhere.
///
/// Everything else (the repository, the sinks, the redactor) is deliberately
/// unexported. They are the reason this package exists rather than a snippet,
/// but a caller who has to assemble them is a caller who can assemble them
/// *wrong* — and getting the crash-reporter egress wrong is the failure this
/// package was extracted to prevent. Configuration is flags on [LogSystem.init]
/// instead.
library;

export 'src/log_system.dart' show LogSystem;
