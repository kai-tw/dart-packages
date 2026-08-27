import 'package:connectivity_plus/connectivity_plus.dart';

/// Thin adapter contract over `connectivity_plus`.
///
/// Exists so the repository can be tested against a plain mock without going
/// through the `Connectivity` class, which exposes a stream getter that would
/// otherwise force a `Mock implements` over a stream-returning member.
///
/// Internal to this package, same as `ConnectivityRepositoryImpl` — not
/// exported. No consumer depends on this directly; they depend on
/// `ConnectivityRepository`, which is the seam this package actually
/// commits to.
abstract class ConnectivityDataSource {
  Future<List<ConnectivityResult>> checkConnectivity();

  Stream<List<ConnectivityResult>> observeConnectivity();
}
