import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

import '../data/connectivity_repository_impl.dart';
import 'connectivity_status.dart';

/// One-app source of truth for network state.
///
/// Consumers can either fetch the current status once via [getStatus] or
/// subscribe to the full lifetime via [observeStatus], which emits the
/// current value immediately and then again on every change.
///
/// Never implemented outside this package — [instance] is the only way to
/// get one. The concrete class stays internal on purpose: a consumer that
/// never has to spell its name can't accidentally couple to it instead of
/// this contract. There is no separate "build me a fresh one" constructor
/// either — a device has exactly one real network state, so every consumer,
/// DI framework or none, reads the same [instance].
abstract class ConnectivityRepository {
  /// The shared repository. Built once, on first access.
  ///
  /// A consumer using `get_it`, Riverpod, or anything else registers this
  /// getter's *value*, not a rebuild of it:
  ///
  /// ```dart
  /// // get_it
  /// sl.registerLazySingleton<ConnectivityRepository>(() => ConnectivityRepository.instance);
  ///
  /// // riverpod
  /// @riverpod
  /// ConnectivityRepository connectivityRepository(Ref ref) =>
  ///     ConnectivityRepository.instance;
  /// ```
  static ConnectivityRepository get instance =>
      ConnectivityRepositoryImpl.instance;

  /// Drops the shared [instance]. Test seam — production code never calls
  /// it. Without this, the first test in a suite to touch [instance] would
  /// leave every later test sharing its repository (and its already-open
  /// platform-channel subscriptions).
  @visibleForTesting
  static void resetInstance() => ConnectivityRepositoryImpl.resetInstance();

  /// One-shot query for the current network state.
  Future<ConnectivityStatus> getStatus();

  /// Emits the current [ConnectivityStatus] immediately, then emits again
  /// whenever the device's network state changes.
  ///
  /// Returns a [ValueStream] — late subscribers receive the most-recently
  /// emitted status as their first event and [ValueStream.value] gives the
  /// same truth synchronously without an await.
  ValueStream<ConnectivityStatus> observeStatus();
}
