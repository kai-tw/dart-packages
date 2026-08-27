# connectivity_status

The device's network state as one value — `offline`, `cellular`, or
`unmetered` — shared across my Flutter projects.

Extracted from NovelGlide's connectivity system, which every caller needing
"am I online" or "may I use the network right now without risking mobile-data
charges" went through. This package is that layer: the entity, the repository
contract, the `connectivity_plus` adapter, and the native metered-network
probe. CherishCRM's onboarding flow is the second consumer.

```dart
// No DI framework? .shared() wraps ConnectivityRepository.instance.
final GetConnectivityUseCase getConnectivity = GetConnectivityUseCase.shared();
final ObserveConnectivityUseCase observeConnectivity = ObserveConnectivityUseCase.shared();

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

## Assembling it: on the contract, not the implementation

```dart
abstract class ConnectivityRepository {
  /// The real platform wiring — a fresh instance every call.
  factory ConnectivityRepository.platform() => ...;

  /// Shared instance for a consumer with no DI framework — built once,
  /// on first access, via [platform].
  static ConnectivityRepository get instance => ...;

  Future<ConnectivityStatus> getStatus();
  ValueStream<ConnectivityStatus> observeStatus();
}
```

This package ships that wiring rather than leaving every consumer to
re-derive it, unlike `preference_store`. `PreferenceRepository<T>` is a
template — each domain (reader settings, TTS, …) instantiates it into its
own shape, so there is no one correct wiring a package could hand back.
`ConnectivityRepository` has no such variance: every consumer wants the
exact same real data source and metered probe behind it, so the assembly
belongs here once instead of copied into every app that depends on this
package.

**The concrete class is never exported.** `.platform()` and `.instance`
live on `ConnectivityRepository` itself — the interface, not
`ConnectivityRepositoryImpl` — so no consumer ever has a reason to spell
the implementation's name. A consumer that never sees that name can't
accidentally couple to it instead of the contract.

- **`ConnectivityRepository.platform()`** — a fresh instance every call.
  Register *this* (a tear-off, not a call) with whatever DI your app uses:

  ```dart
  // get_it
  sl.registerLazySingleton<ConnectivityRepository>(ConnectivityRepository.platform);

  // riverpod
  @riverpod
  ConnectivityRepository connectivityRepository(Ref ref) =>
      ConnectivityRepository.platform();
  ```

- **`ConnectivityRepository.instance`** — the shared instance for an app
  with no DI framework at all. `GetConnectivityUseCase.shared()` and
  `ObserveConnectivityUseCase.shared()` wrap it, so the zero-config path
  never needs to touch `ConnectivityRepository` directly either:

  ```dart
  final getConnectivity = GetConnectivityUseCase.shared();
  final observeConnectivity = ObserveConnectivityUseCase.shared();
  ```

  A consumer using a DI framework should register `.platform` with its
  container and inject the result via the plain constructors
  (`GetConnectivityUseCase(repository)`) instead of reading `.instance` —
  that keeps the app's own container the one source of truth for the
  instance, rather than two caches that could disagree.

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

A platform with no native handler registered (desktop, web) leaves
`ConnectivityMeteredDataSourceImpl` seeing a `MissingPluginException`, which
it treats as "no metered signal on this platform" — the documented case the
repository's allowlist fallback exists for, not a swallowed failure.

Requires `android.permission.ACCESS_NETWORK_STATE` on Android. iOS needs no
extra entitlement.

**Deployment floor:** this package's own dependency on `log_system` pulls in
`firebase_crashlytics` / `firebase_core`, which require iOS 15 via Swift
Package Manager — this package's podspec and `Package.swift` declare that
floor accordingly. Every consumer this was built for (NovelGlide, CherishCRM)
already targets iOS 15+.
