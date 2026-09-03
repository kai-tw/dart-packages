import 'time_source_exception.dart';

/// An HTTP response carried no usable `Date` header.
///
/// The message never quotes the header's bytes. They are attacker-influenced
/// and both consuming apps route log messages verbatim to a crash reporter.
class HttpDateException extends TimeSourceException {
  /// See [TimeSourceException].
  const HttpDateException(super.sourceId, super.reason);
}
