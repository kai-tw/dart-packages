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
/// Never implemented outside this package — [platform] and [instance] are
/// the only way to get one. The concrete class stays internal on purpose:
/// a consumer that never has to spell its name can't accidentally couple to
/// it instead of this contract.
abstract class ConnectivityRepository {
  /// The real platform wiring — a fresh instance every call. Register the
  /// *tear-off*, not a call, with whatever DI your app uses:
  ///
  /// ```dart
  /// sl.registerLazySingleton<ConnectivityRepository>(ConnectivityRepository.platform);
  /// ```
  factory ConnectivityRepository.platform() =>
      ConnectivityRepositoryImpl.platform();

  /// The shared instance for a consumer with no DI framework of its own.
  /// Built once, on first access, via [ConnectivityRepository.platform].
  ///
  /// A consumer using `get_it`, Riverpod, or anything else registers
  /// [ConnectivityRepository.platform] with it instead of reading this
  /// getter — that keeps the app's own container the one source of truth
  /// for the instance, rather than two caches that could disagree.
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
