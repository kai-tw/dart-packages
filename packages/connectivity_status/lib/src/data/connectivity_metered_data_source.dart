import 'connectivity_metered_data_source_impl.dart';

/// Reads the active network's OS-level metered capability.
///
/// Returns `true` when the active link is metered (cellular, a metered Wi-Fi
/// hotspot, or a VPN whose underlying transport is cellular), `false` when it
/// is unmetered, and `null` when the running platform exposes no metered
/// signal at all (desktop / web register no native handler) — in which case
/// the repository falls back to its connection-type heuristic.
///
/// Unexpected platform failures are deliberately NOT absorbed here: they
/// propagate so the repository (the caller) owns the error-isolation
/// decision.
///
/// Lives as its own seam — separate from `ConnectivityDataSource`, which
/// wraps `connectivity_plus` — so the repository can be tested against a
/// plain mock instead of a real platform channel.
///
/// The concrete class stays internal to this package, same as
/// [ConnectivityRepository] — reach the real one only through [platform].
abstract class ConnectivityMeteredDataSource {
  /// The real platform channel. A consumer isolating this specific probe
  /// (an integration test verifying the native side directly, say) uses
  /// this instead of naming the implementation.
  factory ConnectivityMeteredDataSource.platform() =>
      ConnectivityMeteredDataSourceImpl();

  Future<bool?> isActiveNetworkMetered();
}
