/// The device's network state, as a single value so callers branch on
/// one status instead of juggling two booleans.
///
/// Consumers that only care about reachability read [isOnline]; a caller
/// that must avoid mobile-data charges (a Wi-Fi-only download gate, say)
/// distinguishes [cellular] (metered) from [unmetered]. Never infer
/// reachability from the metered-ness — use [isOnline].
enum ConnectivityStatus {
  /// No connectivity of any kind.
  offline,

  /// Online over a **metered** link, per the OS metered capability —
  /// cellular, a metered Wi-Fi hotspot, or a VPN whose underlying
  /// transport is cellular. When the platform exposes no metered signal
  /// (desktop / web), the repository falls back to a Wi-Fi/ethernet
  /// allowlist, so any other link (cellular, vpn, bluetooth) is treated
  /// as this.
  cellular,

  /// Online over an **unmetered** link — Wi-Fi, ethernet, or any link
  /// the OS reports as not metered.
  unmetered;

  /// `true` for any online state — everything except [offline].
  bool get isOnline => this != ConnectivityStatus.offline;
}
