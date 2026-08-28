import 'package:rxdart/rxdart.dart';

import '../data/connectivity_repository_impl.dart';
import 'connectivity_exception.dart';
import 'connectivity_status.dart';

/// One-app source of truth for network state.
///
/// Consumers can either fetch the current status once via [getStatus] or
/// subscribe to the full lifetime via [observeStatus], which emits the
/// current value immediately and then again on every change.
///
/// Never implemented outside this package. The concrete class stays
/// internal on purpose: a consumer that never has to spell its name can't
/// accidentally couple to it instead of this contract.
abstract class ConnectivityRepository {
  /// Builds a fully-wired repository, backed by the real platform adapters.
  ///
  /// This package takes no view on whether the result should be a
  /// singleton — a device has one real network state either way, so ask
  /// whatever DI you use to only build one if that's the shape you want:
  ///
  /// ```dart
  /// // get_it
  /// sl.registerLazySingleton<ConnectivityRepository>(ConnectivityRepository.new);
  ///
  /// // riverpod
  /// @riverpod
  /// ConnectivityRepository connectivityRepository(Ref ref) =>
  ///     ConnectivityRepository();
  ///
  /// // no DI framework — build it once in main() and pass it down
  /// final ConnectivityRepository connectivity = ConnectivityRepository();
  /// ```
  factory ConnectivityRepository() = ConnectivityRepositoryImpl.create;

  /// Non-fatal failures observed internally — a seed probe fault, a stream
  /// error, a metered-probe fault or timeout. Every one already has a safe
  /// fallback in effect by the time it's emitted here; this exists so a
  /// consumer can log or react to it however it already does for its own
  /// errors. Never emits for an expected platform absence (desktop / web
  /// registering no metered handler) — that isn't a failure.
  Stream<ConnectivityException> get exceptions;

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
