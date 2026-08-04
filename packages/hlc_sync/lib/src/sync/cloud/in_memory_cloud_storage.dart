import 'dart:async';
import 'dart:typed_data';

import 'cloud_auth.dart';
import 'cloud_storage.dart';

/// A [CloudStorage] that keeps everything in a map.
///
/// Ships in `lib/`, not `test/`, on purpose. Two devices syncing against one
/// store is the only way to exercise the merge logic end to end, and that
/// scenario has to be reachable from a test, a debug build, and eventually a
/// "try sync without an account" mode. Keeping it here means all three use the
/// same implementation rather than three drifting approximations.
class InMemoryCloudStorage implements CloudStorage {
  InMemoryCloudStorage({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final Map<String, Uint8List> _files = <String, Uint8List>{};
  final Map<String, DateTime> _modified = <String, DateTime>{};
  final DateTime Function() _now;

  /// Set to make every call throw [CloudOfflineException].
  ///
  /// The offline path is the one most likely to be wrong, because it is the
  /// one nobody exercises by hand.
  bool offline = false;

  /// Set to make every call throw this instead.
  ///
  /// Exists for the failures a real transport cannot classify — a platform
  /// channel error, a driver blowing up mid-write. Those reach the caller as
  /// something other than a [CloudStorageException], and the handling of
  /// *that* is what needs a test.
  Object? failWith;

  /// Set to make only [write] and [delete] throw.
  ///
  /// Models the connection dropping part-way through a round, after the
  /// listing already succeeded — which is the case where a round can look like
  /// it worked while uploading nothing.
  Object? failWritesWith;

  /// Every path currently stored. Test convenience.
  Iterable<String> get paths => _files.keys;

  /// How many times [list] has been called.
  ///
  /// One per record type per round, so a test can tell whether rounds have
  /// actually stopped rather than just looking settled at one instant.
  int listCalls = 0;

  @override
  Future<List<CloudFile>> list(String directory) async {
    _guard();
    listCalls++;
    final String prefix = directory.endsWith('/') ? directory : '$directory/';
    return _files.keys
        .where((String p) => p.startsWith(prefix))
        // Non-recursive, matching the interface: only direct children.
        .where((String p) => !p.substring(prefix.length).contains('/'))
        .map(
          (String p) => CloudFile(
            path: p,
            modifiedAt: _modified[p] ?? _now(),
          ),
        )
        .toList();
  }

  @override
  Future<Uint8List?> read(String path) async {
    _guard();
    return _files[path];
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    _guard();
    _guardWrites();
    // Copied, not aliased: callers reuse buffers, and a stored reference that
    // changed underneath would be a bug that only appears under load.
    _files[path] = Uint8List.fromList(bytes);
    _modified[path] = _now();
  }

  @override
  Future<void> delete(String path) async {
    _guard();
    _guardWrites();
    _files.remove(path);
    _modified.remove(path);
  }

  void _guardWrites() {
    final Object? failure = failWritesWith;
    if (failure != null) {
      throw failure;
    }
  }

  void _guard() {
    if (offline) {
      throw const CloudOfflineException();
    }
    final Object? failure = failWith;
    if (failure != null) {
      throw failure;
    }
  }
}

/// A [CloudAuth] that is signed in unless told otherwise.
class InMemoryCloudAuth implements CloudAuth {
  InMemoryCloudAuth({bool signedIn = true, this.account = 'account-a'})
    : _signedIn = signedIn;

  /// Stands in for the connected account. Change it to model a switch.
  String account;

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  bool _signedIn;

  /// Set to make [signIn] report a user cancellation.
  bool cancelNextSignIn = false;

  /// Set to make [signOut] throw.
  ///
  /// The platform call can fail, and what must survive that is the local
  /// cleanup — not the appearance of having disconnected.
  bool failNextSignOut = false;

  @override
  Stream<bool> get isSignedIn => _controller.stream;

  @override
  Future<bool> currentlySignedIn() async => _signedIn;

  @override
  Future<String?> accountFingerprint() async => _signedIn ? account : null;

  @override
  Future<bool> signIn() async {
    if (cancelNextSignIn) {
      cancelNextSignIn = false;
      return false;
    }
    _signedIn = true;
    _controller.add(true);
    return true;
  }

  @override
  Future<void> signOut() async {
    if (failNextSignOut) {
      failNextSignOut = false;
      _signedIn = false;
      throw StateError('platform sign-out failed');
    }
    _signedIn = false;
    _controller.add(false);
  }

  void dispose() {
    _controller.close();
  }
}
