# connectivity_status

The device's network state as one value — `offline`, `cellular`, or
`unmetered` — shared across my Flutter projects.

Extracted from NovelGlide's connectivity system, which every caller needing
"am I online" or "may I use the network right now without risking mobile-data
charges" went through. This package is that layer: the entity, the repository
contract, the `connectivity_plus` adapter, and the native metered-network
probe. CherishCRM's onboarding flow is the second consumer.

```dart
// Build it once — no DI framework needed, but nothing stops you using one.
final ConnectivityRepository connectivity = ConnectivityRepository();
final GetConnectivityUseCase getConnectivity = GetConnectivityUseCase(connectivity);
final ObserveConnectivityUseCase observeConnectivity = ObserveConnectivityUseCase(connectivity);

final ConnectivityStatus now = await getConnectivity();
observeConnectivity().listen((ConnectivityStatus status) {
  if (status.isOnline) retryWhatFailedOffline();
});
```

## `ConnectivityStatus`

```dart
enum ConnectivityStatus {
  offline,
  cellular, // metered — cellular, a metered Wi-Fi hotspot, or cellular-over-VPN
  unmetered, // Wi-Fi, ethernet, or anything else the OS reports as not metered
}
```

A single enum, not two booleans — `isOnline` is a getter (`!= offline`).
`cellular` exists for a Wi-Fi-only gate (a translation-pack download, say)
that must avoid mobile-data charges; a caller that only cares about
reachability never needs to look past `isOnline`.

Metered-ness comes from the **OS metered capability**
(`ConnectivityManager.isActiveNetworkMetered` on Android,
`NWPath.isExpensive` on iOS) rather than the connection type alone, so a VPN
tunnelling over cellular and a metered Wi-Fi hotspot both correctly resolve to
`cellular` — a plain Wi-Fi-vs-cellular check cannot tell either apart from a
genuine unmetered link. When the platform exposes no metered signal (desktop,
web) or the probe faults, the repository falls back to a Wi-Fi/ethernet
allowlist.

## Assembling it: a plain constructor, singleton-ness is your call

```dart
abstract class ConnectivityRepository {
  /// Builds a fully-wired repository, backed by the real platform adapters.
  factory ConnectivityRepository() = ...;

  Stream<ConnectivityException> get exceptions;
  Future<ConnectivityStatus> getStatus();
  ValueStream<ConnectivityStatus> observeStatus();
}
```

This package takes no view on whether the result should be a singleton. A
device has exactly one real network state, but nothing about that requires
*this package* to enforce a single shared object — that's a DI decision,
and DI decisions belong to the app, not the library:

```dart
// No DI framework — build it once in main() and pass it down.
final ConnectivityRepository connectivity = ConnectivityRepository();

// get_it
sl.registerLazySingleton<ConnectivityRepository>(ConnectivityRepository.new);

// riverpod
@riverpod
ConnectivityRepository connectivityRepository(Ref ref) =>
    ConnectivityRepository();
```

This is also why the package ships the wiring at all, unlike
`preference_store`: `PreferenceRepository<T>` is a template each domain
(reader settings, TTS, …) instantiates into its own shape, so there is no
one correct wiring a package could hand back; `ConnectivityRepository` has
no such variance — every consumer wants the same real adapters behind it,
just not necessarily the same *object*.

**Nothing behind the contract is exported** — not the concrete
`ConnectivityRepositoryImpl`, not the `ConnectivityDataSource` /
`ConnectivityMeteredDataSource` adapters it's built from. A consumer never
has a name to spell other than `ConnectivityRepository`, so it can't
accidentally couple to the implementation instead of the contract.

## Failures are a stream, not a logging call

This package has no logging dependency of its own — it never decides how a
failure gets recorded. Instead, every non-fatal fault it catches internally
is emitted on `exceptions` as one of four concrete, `sealed`-enforced
causes:

```dart
sealed class ConnectivityException implements Exception {
  final Object exception;
  final StackTrace stackTrace;
}

final class ConnectivitySeedException extends ConnectivityException {}
final class ConnectivityStreamException extends ConnectivityException {}
final class ConnectivityMeteredProbeException extends ConnectivityException {}
final class ConnectivityMeteredProbeTimeoutException extends ConnectivityException {}
```

`implements Exception`, not `extends Error` — this is an expected,
already-recovered-from condition worth knowing about, not a Dart `Error` (a
programmer bug that should propagate to a zone handler, never be caught and
reported like this). `sealed` so a consumer's `switch` is a coverage
contract, not a guess from a free-text message — a fifth cause added later
fails to compile until every `switch` handles it:

```dart
connectivity.exceptions.listen((ConnectivityException e) {
  final String cause = switch (e) {
    ConnectivitySeedException() => 'seed probe failed',
    ConnectivityStreamException() => 'connectivity stream errored',
    ConnectivityMeteredProbeException() => 'metered probe failed',
    ConnectivityMeteredProbeTimeoutException() => 'metered probe timed out',
  };
  // Wire this into whatever the app already uses — log_system, Crashlytics,
  // a debug banner. This package has no opinion on which.
  myLogger.warning(cause, error: e.exception, stackTrace: e.stackTrace);
});
```

Unlike a typical project-scoped domain exception, each subclass still
carries the raw caught `exception` rather than only domain-relevant fields:
this package has no redactor of its own to translate a platform fault
safely first, so the raw value is the consumer's own logger's to read (and
redact, if it needs to).

Every occurrence already has a safe fallback in effect by the time it's
emitted — `getStatus()` and `observeStatus()` keep working regardless of
whether anything listens to `errors`. An expected platform absence (desktop
/ web registering no metered handler) is never emitted here; that isn't a
failure, it's documented behavior (see below).

## What this package does not do

- **No app-specific policy.** "May a download start right now, given the
  user's Wi-Fi-only preference" is a decision an app makes over
  `ConnectivityStatus`, not something this package has an opinion on.
- **No shared use-case base class.** `GetConnectivityUseCase` and
  `ObserveConnectivityUseCase` are plain classes with a `call()` method — the
  same reasoning that already keeps `ui_kit` and `preference_store`
  framework-agnostic.

## The metered probe is real native code

Unlike the rest of this package, the metered signal cannot be read from Dart
alone — `connectivity_plus` reports a connection *type*, not whether the OS
considers it metered. This package ships as a proper federated Flutter
plugin (`ios/`, `android/`, a `pluginClass` in `pubspec.yaml`) specifically so
that native code is registered automatically by `GeneratedPluginRegistrant`;
a consuming app never calls anything in its own `AppDelegate` /
`MainActivity`.

A platform with no native handler registered (desktop, web) surfaces a
`MissingPluginException` internally, which this package treats as "no
metered signal on this platform" — the documented case the repository's
allowlist fallback exists for, not a swallowed failure. A consumer that needs
to probe the plugin's own platform-interface layer directly (rare — most
should go through `ConnectivityRepository`) can still reach
`ConnectivityStatusPlatform.instance`, the federated plugin's own
extensibility point.

Requires `android.permission.ACCESS_NETWORK_STATE` on Android. iOS needs no
extra entitlement.

**Deployment floor:** iOS 13.0 — Flutter's own current floor, not something
this package's native code needs on its own (`connectivity_plus` itself only
requires 12.0).
