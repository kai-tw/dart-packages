import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'log_diagnostic_code.dart';

/// Describes an error type this app wants to keep one structural field from.
///
/// Registered via [LogErrorRedactor.addRule] so a host app can teach the
/// redactor about a type this package must not depend on. The reason this
/// exists rather than a longer built-in list: the built-in arms cover types
/// from `dart:io` and `package:flutter`, which every consumer already has.
/// A `DioException` arm would drag `package:dio` into projects that removed
/// their HTTP client years ago.
///
/// [matches] must not throw and must not call `toString()` on [error].
/// [describe] returns the **whole** surrogate description, and must lead with
/// the runtime type name so Crashlytics grouping still discriminates types —
/// `'$type status=404'`, not `'status=404'`.
class LogErrorRule {
  const LogErrorRule({required this.matches, required this.describe});

  final bool Function(Object error) matches;
  final String Function(Object error, String type) describe;
}

/// Reduces an error object before it crosses the log → crash-reporter boundary.
///
/// Eliminates CWE-532 structurally: a raw exception's `toString()` can carry
/// PII — file paths, request URLs, record ids, free-form messages — so the
/// boundary forwards a surrogate exposing only the runtime type name plus a
/// per-type allow-list of closed-vocabulary structural fields (error code, HTTP
/// status, errno) that change a triage decision but cannot carry user data.
///
/// Contract (do not regress):
///
/// - **default-deny.** An unrecognised type is reduced to its runtime type name
///   with zero fields, so a newly-introduced exception type is safe by
///   construction — keeping a field requires an explicit arm or rule.
/// - **the allow-list never admits a free-form field.** `message` / `details` /
///   `path` / `uri` / `host` / `address` / `query` / `reason` are dropped. Only
///   closed-vocabulary structural fields survive, each annotated with the
///   triage decision it changes.
/// - **a domain exception is type-name-only unless it opts in via
///   [LogDiagnosticCode].** Its `message` is free-form and may carry
///   identifiers, so it is never read — the type name is itself the useful
///   signal.
/// - **the redactor never calls `toString()` on the untrusted original.** It
///   reads `runtimeType` (which cannot throw) and typed allow-listed getters,
///   so a hostile `toString()` can neither leak through nor throw.
/// - **the surrogate's `toString()` leads with the original runtime type name**
///   so the crash reporter's non-fatal grouping — keyed on exception
///   type/message + stack — still separates distinct error types instead of
///   collapsing every redacted error into one issue (flutterfire #3310).
class LogErrorRedactor {
  LogErrorRedactor._();

  static final List<LogErrorRule> _rules = <LogErrorRule>[];

  /// Teaches the redactor about a type this package cannot depend on.
  ///
  /// Rules are consulted **before** the built-in arms, in registration order,
  /// so a host app can also override one. Call during startup, before the
  /// first log; there is no removal, because a redactor that can be narrowed
  /// at runtime is a redactor whose behaviour depends on call order.
  static void addRule(LogErrorRule rule) => _rules.add(rule);

  /// Drops every registered rule. Test seam — production code never calls it.
  @visibleForTesting
  static void resetRules() => _rules.clear();

  static Object? redact(Object? error) {
    // Null short-circuit: a no-error log forwards nothing.
    if (error == null) {
      return null;
    }

    final String type = error.runtimeType.toString();

    for (final LogErrorRule rule in _rules) {
      if (rule.matches(error)) {
        return _RedactedError(rule.describe(error, type));
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
    if (error is LogDiagnosticCode) {
      // Opt-in marker: a translated domain exception surfaces one errno after
      // the raw exception is gone. An out-of-band value is treated as a
      // suspected PII smuggle and degraded, so the marker can never widen the
      // egress surface.
      final int? code = error.diagnosticCode;
      if (code == null) {
        return _RedactedError('$type code=-');
      }
      return _RedactedError(
        (code < 0 || code > 65535) ? type : '$type code=$code',
      );
    }

    return _RedactedError(type);
  }

  /// Whether [value] is shaped like embedded free-form data rather than an
  /// opaque token — a path, URL or sentence, or an over-long payload. Gates
  /// the one allow-listed `String` field so it cannot become a PII channel.
  static bool _looksFreeForm(String value) {
    if (value.length > 48) {
      return true;
    }
    return value.contains(' ') ||
        value.contains('/') ||
        value.contains(r'\') ||
        value.contains('\n');
  }

  /// Rebuilds [details] for the framework-fatal path
  /// (`FlutterError.onError`), which does not go through [LogSystem].
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
