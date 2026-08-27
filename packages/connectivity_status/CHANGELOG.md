## 0.1.0

Initial extraction, from NovelGlide's connectivity system.

- `ConnectivityStatus` — the three-value network state (`offline` /
  `cellular` / `unmetered`) plus `isOnline`.
- `ConnectivityRepository` / `ConnectivityRepositoryImpl` — one-shot
  `getStatus()` and a live `ValueStream` via `observeStatus()`, seeded
  synchronously so `.value` never throws.
- `ConnectivityDataSource` / `ConnectivityDataSourceImpl` — thin adapter over
  `connectivity_plus`.
- `ConnectivityMeteredDataSource` / `ConnectivityMeteredDataSourceImpl` — the
  OS metered-capability probe, backed by this package's own federated
  plugin (`android/`, `ios/`) rather than a raw `MethodChannel` a consumer
  has to wire up itself.
- `GetConnectivityUseCase` / `ObserveConnectivityUseCase` — plain classes
  with a `call()` method, no shared `UseCase` base. Each also has a
  `.shared()` factory for the zero-config path (see below).
- `ConnectivityRepositoryImpl.platform()` — the one correct wiring of the
  real data source and metered probe, as a factory constructor rather than
  a registration. Unlike `preference_store`'s `PreferenceRepository<T>`,
  there is no per-consumer shape to leave open here, so this package hands
  back the assembly instead of making every consumer re-derive it. Still
  framework-agnostic: register the constructor *tear-off* with whatever DI
  (`get_it`, Riverpod, none) your app already uses.
- `ConnectivityRepositoryImpl.instance` — the shared instance for an app
  with no DI framework, built once on first access via `.platform()`.
  `GetConnectivityUseCase.shared()` / `ObserveConnectivityUseCase.shared()`
  wrap it, so the zero-config path never has to name
  `ConnectivityRepositoryImpl` directly. `@visibleForTesting
  ConnectivityRepositoryImpl.resetInstance()` drops the cache — a test seam,
  same shape as `log_system`'s `LogSystem.reset()`.

Deliberately not a top-level function: two named constructors on
`ConnectivityRepositoryImpl` keep both paths discoverable from the type
instead of adding a name to the package's flat namespace.

Differences from the code it was extracted from:

- `AppDownloadPolicyUseCase` (NovelGlide's "download over Wi-Fi only"
  product policy) stayed behind — this package owns network-state plumbing,
  not one app's policy over it. `setupConnectivityDependencies()`
  (NovelGlide's GetIt registration) also stayed behind, but the assembly it
  did — building `ConnectivityRepositoryImpl` from the real adapters — is
  now `ConnectivityRepositoryImpl.platform()`, so NovelGlide's own wiring
  shrinks to one line registering that constructor, and CherishCRM's
  Riverpod provider can call it directly.
- The two use cases dropped their `extends UseCase<Return, Parameter>`
  inheritance from NovelGlide's app-local base class, so this package does
  not force a consumer into that convention.
- The metered probe's platform channel is renamed from
  `com.kai_wu.novelglide/connectivity_metered` to
  `net.kaiwu.connectivity_status/metered` — a shared package's channel name
  must not carry one consuming app's identity, and `net.kaiwu` (not
  `com.kai_wu`) is the current org identifier, matching CherishCRM's
  Android namespace and iOS bundle identifier.
- The native Swift/Kotlin, previously loose files manually registered from
  each app's `AppDelegate` / `MainActivity`, is now a proper federated
  plugin. `GeneratedPluginRegistrant` wires it automatically; no consumer
  needs a native registration call of its own.
