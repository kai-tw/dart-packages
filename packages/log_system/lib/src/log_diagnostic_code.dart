/// Opt-in marker an exception implements to surface **one** closed-vocabulary
/// structural diagnostic code across the egress boundary.
///
/// Read by `LogErrorRedactor`: an error implementing this forwards
/// `'$runtimeType code=$diagnosticCode'` instead of the default type-name-only
/// surrogate, so a translated domain exception — which drops the raw
/// infrastructure exception it wrapped — can still carry the triage
/// discriminator the original `SocketException` held.
///
/// Contract (do not regress — this is the redactor's extension surface, and it
/// is the reason a domain exception may expose a field to the log path at all):
///
/// - **closed-vocabulary structural code only.** [diagnosticCode] is an OS
///   errno, or an equivalent small bounded non-user-derived integer that
///   changes a triage decision. It is NEVER an id, hash, timestamp, count of
///   user data, or any value derived from user content — those re-open the
///   CWE-532 channel the redactor exists to close. The redactor additionally
///   band-clamps the value, but the type-level contract is: do not put a
///   user-derived integer here.
/// - **pure field read.** The getter reads a stored field with no side effects
///   and never throws — the redactor calls it on an untrusted error object.
/// - **`null` means "no code available"** (a `ClientException` translated to
///   the same domain type carries no errno). The redactor renders it `code=-`.
abstract interface class LogDiagnosticCode {
  int? get diagnosticCode;
}
