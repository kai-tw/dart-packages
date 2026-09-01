import 'log_entry.dart';

/// A destination a host app registers to observe its own logging.
///
/// This is the one seam a consumer may implement. `LogDataSource` and
/// `LogRepository` stay unexported because a caller who has to assemble them
/// is a caller who can assemble them wrong, and a wrongly-assembled graph
/// sends unredacted objects to the crash reporter. A sink cannot: it is handed
/// values that have **already** crossed the redaction boundary, so there is
/// nothing here to assemble incorrectly.
///
/// Two things it is for, and the second is why it exists at all:
///
/// - **An app with its own logging backend.** Register a sink through
///   `LogSystem.init(sink: ...)` and every level arrives alongside the console
///   and the crash reporter, rather than instead of them.
/// - **Making a log call observable in the app's own tests.** Every level is a
///   silent no-op until something is registered, which keeps a log line from
///   ever being why a unit test throws — but it also means an app cannot
///   assert that a fault was logged at all. A fake sink is how it can. Build
///   one in the app's own test tree; this package deliberately ships none (see
///   the class doc on `LogSystem`).
///
/// ```dart
/// final class FakeLogSink implements LogSink {
///   final List<LogEntry> entries = <LogEntry>[];
///
///   @override
///   void emit(LogEntry entry) => entries.add(entry);
/// }
/// ```
///
/// **A sink that throws does not break the call site.** The throw is captured
/// into the same discarded future a failing `LogDataSource` rejects, so it
/// surfaces to a zone handler rather than propagating out of
/// `LogSystem.error(...)`. Logging that silently stops working is worse than
/// logging that throws somewhere visible; logging that takes the app down with
/// it is worse than both.
abstract interface class LogSink {
  /// Receives one log line, at every level including `event`.
  void emit(LogEntry entry);
}
