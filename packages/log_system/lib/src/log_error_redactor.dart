import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reduces an error object before it crosses the log → crash-reporter boundary.
///
/// Eliminates CWE-532 structurally: a raw exception's `toString()` can carry
/// PII — file paths, request URLs, record ids, free-form messages — so the
/// boundary forwards a surrogate exposing only the runtime type name plus a
/// per-type allow-list of closed-vocabulary structural fields (error code,
/// errno) that change a triage decision but cannot carry user data.
///
/// Contract (do not regress):
///
/// - **default-deny.** An unrecognised type is reduced to its runtime type name
///   with zero fields, so a newly-introduced exception type is safe by
///   construction — keeping a field requires an explicit arm.
/// - **the allow-list never admits a free-form field.** `message` / `details` /
///   `path` / `uri` / `host` / `address` / `query` / `reason` are dropped. Only
///   closed-vocabulary structural fields survive, each annotated with the
///   triage decision it changes.
/// - **a domain exception is type-name-only.** Its `message` is free-form and
///   may carry identifiers, so it is never read — the type name is itself the
///   useful signal.
/// - **the redactor never calls `toString()` on the untrusted original.** It
///   reads `runtimeType` (which cannot throw) and typed allow-listed getters,
///   so a hostile `toString()` can neither leak through nor throw.
/// - **the surrogate's `toString()` leads with the original runtime type name**
///   so the crash reporter's non-fatal grouping — keyed on exception
///   type/message + stack — still separates distinct error types instead of
///   collapsing every redacted error into one issue (flutterfire #3310).
///
/// The built-in arms are limited to types from `dart:io` and
/// `package:flutter`, which every consumer already has. An arm for a type from
/// another package — an HTTP client's exception, say — would make that package
/// a dependency of every consumer, so [describeExtra] exists instead: the host
/// app, which already has the dependency, supplies the one field worth keeping.
class LogErrorRedactor {
  LogErrorRedactor._();

  /// Host-supplied describer for types this package cannot name.
  ///
  /// Set from `LogSystem.init`. Returns the field suffix only — the type name
  /// is prepended here, so a describer cannot break issue grouping however it
  /// is written. Returning null falls through to the built-in arms.
  static String? Function(Object error)? describeExtra;

  static Object? redact(Object? error) {
    // Null short-circuit: a no-error log forwards nothing.
    if (error == null) {
      return null;
    }

    final String type = error.runtimeType.toString();

    // Host describer first, so an app can also override a built-in arm.
    final String? Function(Object)? describer = describeExtra;
    if (describer != null) {
      final String? extra = describer(error);
      if (extra != null) {
        // Still gated: a describer that returns a path or a sentence is a
        // mistake this boundary must absorb rather than forward, because the
        // whole point is that no code outside can widen the egress.
        return _RedactedError(
          _describerLooksFreeForm(extra) ? type : '$type $extra',
        );
      }
    }

    if (error is PlatformException) {
      // `code` is a stable channel/plugin error code ('channel-error') and
      // separates platform failure modes; message/details are free-form and
      // dropped. Unlike the other allow-listed fields it is a plugin-set
      // String with no type guarantee, so it is forwarded only when it has the
      // shape of an opaque token — a plugin smuggling a path or a sentence
      // into it degrades to type-name-only.
      final String code = error.code;
      return _RedactedError(_looksFreeForm(code) ? type : '$type code=$code');
    }
    if (error is FileSystemException) {
      // errno separates ENOSPC / EACCES / ENOENT. path/message are PII.
      return _RedactedError('$type errno=${error.osError?.errorCode ?? '-'}');
    }
    if (error is SocketException) {
      // errno separates connection-refused / host-unreachable. address dropped.
      return _RedactedError('$type errno=${error.osError?.errorCode ?? '-'}');
    }
    if (error is OSError) {
      // errno is the discriminator; the OS message string is dropped.
      return _RedactedError('$type errno=${error.errorCode}');
    }

    return _RedactedError(type);
  }

  /// Whether [value] is shaped like embedded free-form data rather than an
  /// opaque token — a path, URL or sentence, or an over-long payload. Gates
  /// the one allow-listed plugin `String` so it cannot become a PII channel.
  static bool _looksFreeForm(String value) {
    if (value.length > 48) {
      return true;
    }
    return value.contains(' ') ||
        value.contains('/') ||
        value.contains(r'\') ||
        value.contains('\n');
  }

  /// As [_looksFreeForm], for a host describer's output.
  ///
  /// Separate because a describer legitimately returns more than one field —
  /// `'status=404 connectionTimeout'` — so a space cannot be the signal here.
  /// Each field is checked individually instead, and the count is capped: a
  /// sentence is a sentence however few slashes it contains.
  static bool _describerLooksFreeForm(String value) {
    if (value.length > 48) {
      return true;
    }
    final List<String> fields = value.split(' ');
    if (fields.length > 3) {
      return true;
    }
    return fields.any(
      (String field) =>
          field.isEmpty ||
          field.contains('/') ||
          field.contains(r'\') ||
          field.contains('\n'),
    );
  }

  /// Rebuilds [details] for the framework-fatal path (`FlutterError.onError`),
  /// which does not go through `LogSystem`.
  ///
  /// The exception is redacted, and `context` / `informationCollector` are
  /// dropped: both are `DiagnosticsNode`s that can carry widget-tree property
  /// values — a `Text` widget's content in an overflow assertion, for
  /// instance. Only the redacted exception, the stack and the library survive.
  static FlutterErrorDetails redactDetails(FlutterErrorDetails details) {
    return FlutterErrorDetails(
      // `redact` returns null only for a null input and `details.exception` is
      // non-null, so the fallback is unreachable. It exists to satisfy the
      // non-null field, and is itself a surrogate so even an unforeseen null
      // cannot leak the raw object.
      exception: redact(details.exception) ?? const _RedactedError('redacted'),
      stack: details.stack,
      library: details.library,
    );
  }
}

/// Non-identifying surrogate forwarded in place of the raw error. Its
/// [toString] is the only thing the sink surfaces, and it leads with the
/// original runtime type name to preserve issue grouping.
class _RedactedError {
  const _RedactedError(this._description);

  final String _description;

  @override
  String toString() => _description;
}
