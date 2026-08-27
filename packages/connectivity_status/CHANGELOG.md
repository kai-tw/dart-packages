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
  with a `call()` method, no shared `UseCase` base.

Differences from the code it was extracted from:

- `AppDownloadPolicyUseCase` (NovelGlide's "download over Wi-Fi only"
  product policy) and `setupConnectivityDependencies()` (GetIt wiring) both
  stayed behind — this package owns network-state plumbing, not one app's
  policy over it or its DI convention.
- The two use cases dropped their `extends UseCase<Return, Parameter>`
  inheritance from NovelGlide's app-local base class, so this package does
  not force a consumer into that convention.
- The metered probe's platform channel is renamed from
  `com.kai_wu.novelglide/connectivity_metered` to
  `com.kai_wu.connectivity_status/metered` — a shared package's channel name
  must not carry one consuming app's identity.
- The native Swift/Kotlin, previously loose files manually registered from
  each app's `AppDelegate` / `MainActivity`, is now a proper federated
  plugin. `GeneratedPluginRegistrant` wires it automatically; no consumer
  needs a native registration call of its own.
