/// Persistence for the rollback watermark — the highest wall-clock instant
/// this device has ever reported.
///
/// A port, not an implementation: the value has to outlive the process (a
/// clock moved while the app was closed is exactly the case worth catching),
/// and where it is stored is the app's decision — `preference_store`,
/// `SharedPreferences`, a row in the app's own database.
///
/// It holds no secret and nothing about the user, so it does not need secure
/// storage. It **must** be somewhere the device's owner cannot trivially edit
/// while the app is not running, which rules out an exported file.
abstract class WatermarkStore {
  /// The stored watermark, or null if none has ever been written.
  Future<DateTime?> read();

  /// Replaces the stored watermark.
  Future<void> write(DateTime value);
}

/// A [WatermarkStore] that forgets everything when the process ends.
///
/// For tests, and for an app that has decided the cross-restart half of
/// rollback detection is not worth a preference key. Using it in production
/// is a real reduction in coverage, not a shortcut: the clock change most
/// worth catching happens while the app is closed.
class InMemoryWatermarkStore implements WatermarkStore {
  /// Optionally seeded, so a test can start from a known watermark.
  InMemoryWatermarkStore([this._value]);

  DateTime? _value;

  @override
  Future<DateTime?> read() async => _value;

  @override
  Future<void> write(DateTime value) async {
    _value = value.toUtc();
  }
}
