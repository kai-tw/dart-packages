/// Base for an app's own exceptions, so they survive redaction usefully.
///
/// The redactor's default is deny: an unrecognised type crosses to the crash
/// reporter as its runtime type name and nothing else, because a `message`
/// field is free-form and may carry a customer name, a file path or a record
/// id. That default is right, and it costs a real triage discriminator —
/// a domain exception that translated a `SocketException` no longer says
/// *which* socket failure it was.
///
/// Extending this is how an app buys that back, for one value, on terms the
/// redactor can enforce — see [diagnosticCode] for what that value may be.
///
/// ```dart
/// class CloudSocketException extends LoggableException {
///   const CloudSocketException({super.diagnosticCode});
/// }
/// ```
abstract class LoggableException implements Exception {
  const LoggableException({this.diagnosticCode});

  /// An OS errno, HTTP status or equivalent bounded structural value.
  ///
  /// A `String` code reads better (`'connection-refused'`), and is exactly
  /// the field that turns into a PII channel the first time someone writes
  /// `'failed for $bookId'`. An `int` cannot carry a name, a path or a
  /// sentence at all, whatever a future implementer does — and it is what the
  /// values actually are: an OS errno, an HTTP status, a platform result
  /// code.
  ///
  /// The redactor additionally band-clamps it, so an implementer who returns
  /// a timestamp or a record count degrades to type-name-only rather than
  /// widening the egress. But the type-level contract is the real one:
  ///
  /// - **closed-vocabulary structural value only.** Never an id, hash,
  ///   timestamp, count of user data, or anything derived from user content.
  /// - **null means "no code available"** — a failure translated to the same
  ///   type from a source that had no errno. Renders as `code=-`.
  final int? diagnosticCode;

  /// Deliberately carries no message. This is what the console prints and
  /// what a `toString()` in any other sink would surface, so the type is not
  /// given the chance to describe itself in free text.
  @override
  String toString() => diagnosticCode == null
      ? '$runtimeType'
      : '$runtimeType(code=$diagnosticCode)';
}
