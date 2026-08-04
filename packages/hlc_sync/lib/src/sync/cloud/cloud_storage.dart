import 'dart:typed_data';

/// A file in cloud storage, identified by path.
class CloudFile {
  const CloudFile({required this.path, required this.modifiedAt});

  /// Always a `/`-rooted logical path such as `/records/<recordType>/<id>.json`.
  final String path;

  final DateTime modifiedAt;
}

/// Somewhere to put bytes, addressed by path.
///
/// Deliberately narrow, and deliberately path-based. Drive's own file ids are
/// opaque handles that mean nothing outside Drive; letting them reach the sync
/// layer would tie every decision above this line to one provider and make the
/// whole thing untestable without a network and an account. Paths keep the
/// provider swappable and let the fake below stand in completely.
///
/// Nothing here knows about records, HLCs or conflicts — this moves bytes.
abstract class CloudStorage {
  /// Files under [directory], non-recursively.
  Future<List<CloudFile>> list(String directory);

  /// Null when the path does not exist. Not an error: a missing file is the
  /// normal state for a record this device has never pushed.
  Future<Uint8List?> read(String path);

  Future<void> write(String path, Uint8List bytes);

  Future<void> delete(String path);
}

/// Raised when the cloud is reachable but refused the operation.
class CloudStorageException implements Exception {
  const CloudStorageException(this.message);

  final String message;

  @override
  String toString() => 'CloudStorageException: $message';
}

/// Raised when the device is offline.
///
/// Kept distinct from [CloudStorageException] because the two want different
/// handling: offline means "try again later, nothing is wrong", while a
/// storage failure means something needs looking at. Collapsing them turns
/// every subway ride into an error worth showing someone.
class CloudOfflineException implements Exception {
  const CloudOfflineException();

  @override
  String toString() => 'CloudOfflineException';
}
