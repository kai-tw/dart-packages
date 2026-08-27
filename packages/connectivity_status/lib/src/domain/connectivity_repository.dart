import 'package:rxdart/rxdart.dart';

import 'connectivity_status.dart';

/// One-app source of truth for network state.
///
/// Consumers can either fetch the current status once via [getStatus] or
/// subscribe to the full lifetime via [observeStatus], which emits the
/// current value immediately and then again on every change.
abstract class ConnectivityRepository {
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
