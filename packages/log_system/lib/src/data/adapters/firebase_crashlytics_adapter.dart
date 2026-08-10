import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../log_data_source.dart';
import 'log_error_redactor.dart';

/// Crash-reporter sink. Everything that leaves the device does so from here.
///
/// Two gates, and both are deliberate:
///
/// - **release only** ([enabled] defaults to `kReleaseMode`). In debug nothing
///   reaches Firebase. Unlike analytics this does not distinguish a store
///   build from an internal one — every release build reports crashes, which
///   is the point. Provenance is carried by [customKeys] instead.
/// - **redaction** ([LogErrorRedactor]). No caller can opt out; the error
///   object is reduced on the way through, so an exception whose `toString()`
///   carries a customer name or a key reaches the sink as its type name.
class FirebaseCrashlyticsAdapter extends LogDataSource {
  FirebaseCrashlyticsAdapter(
    this._instance, {
    bool? enabled,
    this.forwardInfo = true,
    Map<String, String> customKeys = const <String, String>{},
    Future<Map<String, String>> Function()? deferredCustomKeys,
  }) : enabled = enabled ?? kReleaseMode {
    // Collection is switched at the SDK as well as gated in this class, and
    // both are needed: this class only guards what *it* sends, while an
    // uncaught crash is captured by the native layer with no Dart code
    // involved. An app that leaves the SDK's default on ships debug-run
    // crashes to the same project as real ones.
    unawaited(_instance.setCrashlyticsCollectionEnabled(this.enabled));

    if (!this.enabled) {
      return;
    }
    // Custom keys bypass the redactor entirely, so only provably
    // non-identifying values belong here — a commit sha, a release channel.
    // The host app supplies them rather than this package reading them,
    // because every source of them (a generated BuildInfo, package_info_plus)
    // is a dependency one consumer has and another does not.
    for (final MapEntry<String, String> entry in customKeys.entries) {
      unawaited(_instance.setCustomKey(entry.key, entry.value));
    }
    // Unawaited, and separate, because it needs a platform round-trip: it
    // lands a moment after launch and a crash in the first frames may miss it.
    // Nobody can act on a failed key write, and awaiting would stall startup
    // on a network-backed plugin call.
    if (deferredCustomKeys != null) {
      unawaited(_stampDeferred(deferredCustomKeys));
    }
  }

  final FirebaseCrashlytics _instance;

  /// Whether anything leaves the device at all.
  final bool enabled;

  /// Whether `info` becomes a breadcrumb.
  ///
  /// A breadcrumb is only ever surfaced alongside a later crash, so it is
  /// cheap — but it is still an egress, and an app whose `info` lines quote
  /// anything user-derived wants this off. Off means `info` is device-local,
  /// exactly like `debug`.
  final bool forwardInfo;

  Future<void> _stampDeferred(
    Future<Map<String, String>> Function() resolve,
  ) async {
    final Map<String, String> keys = await resolve();
    for (final MapEntry<String, String> entry in keys.entries) {
      await _instance.setCustomKey(entry.key, entry.value);
    }
  }

  @override
  Future<void> debug(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    // Local-only, always. A debug breadcrumb is for the person holding the
    // device, and shipping every one of them to a 90-day retained sink is
    // collection nobody asked for.
  }

  @override
  Future<void> info(String message) async {
    if (!enabled || !forwardInfo) {
      return;
    }
    return _instance.log('Info: $message');
  }

  @override
  Future<void> warning(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    if (!enabled) {
      return;
    }
    // A warning stays a breadcrumb, never `recordError` — that would file a
    // fault entry for something that is not a fault. The error is redacted
    // first: its raw `toString()` would otherwise reach the breadcrumb.
    final StringBuffer buffer = StringBuffer('Warning: $message');
    if (error != null) {
      buffer.write(' — ${LogErrorRedactor.redact(error)}');
    }
    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }
    return _instance.log(buffer.toString());
  }

  @override
  Future<void> error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    if (!enabled) {
      return;
    }
    return _instance.recordError(
      LogErrorRedactor.redact(error),
      stackTrace,
      reason: message,
      // Local printing belongs to the console sink, which has already run.
      // Left at its default (`kDebugMode`) the plugin prints the *redacted*
      // surrogate underneath the real one, which reads like the error lost
      // its detail.
      printDetails: false,
      fatal: false,
    );
  }

  @override
  Future<void> fatal(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    if (!enabled) {
      return;
    }
    return _instance.recordError(
      LogErrorRedactor.redact(error),
      stackTrace,
      reason: message,
      printDetails: false,
      fatal: true,
    );
  }

  @override
  Future<void> event(String name, {Map<String, Object>? parameters}) async {
    // No-op. An event is not a fault, and it is not a breadcrumb either — the
    // level exists for an analytics backend an app may wire later, and letting
    // it drip into crash reports meanwhile would make that wiring look like it
    // had already happened.
  }
}
