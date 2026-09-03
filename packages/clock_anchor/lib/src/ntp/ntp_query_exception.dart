import '../time_source_exception.dart';

/// An SNTP exchange failed, or produced a reply that cannot be used.
///
/// The message carries only shapes and numbers — never bytes from the reply.
/// A UDP packet on port 123 is unauthenticated and can be written by anyone
/// on the path, and both consuming apps route log messages verbatim to a
/// crash reporter.
class NtpQueryException extends TimeSourceException {
  /// See [TimeSourceException].
  const NtpQueryException(super.sourceId, super.reason);
}
