import 'dart:async';

import 'package:connectivity_status/connectivity_status.dart';
import 'package:rxdart/rxdart.dart';

/// Hand-written fake for [ConnectivityRepository].
///
/// [ConnectivityRepository.errors] is a public `Stream`-returning getter, so
/// `Mock implements ConnectivityRepository` would trip `avoid_listenable_mock`
/// (Prong B) — a mocktail proxy stubs a stream getter without exercising real
/// subscription behavior. [errors] here is backed by a real, unused
/// `StreamController`; [getStatus] and [observeStatus] are simple
/// configurable stand-ins for what the use-case tests actually exercise.
class FakeConnectivityRepository implements ConnectivityRepository {
  final StreamController<ConnectivityError> _errors =
      StreamController<ConnectivityError>.broadcast();

  @override
  Stream<ConnectivityError> get errors => _errors.stream;

  /// Configures what [getStatus] resolves to, or throws [throwWith] instead.
  ConnectivityStatus? response;
  Object? throwWith;
  int getStatusCallCount = 0;

  @override
  Future<ConnectivityStatus> getStatus() async {
    getStatusCallCount++;
    final Object? err = throwWith;
    if (err != null) {
      throw err;
    }
    final ConnectivityStatus? status = response;
    if (status == null) {
      throw StateError('FakeConnectivityRepository.response was never set');
    }
    return status;
  }

  /// Configures what [observeStatus] returns.
  ValueStream<ConnectivityStatus>? observeStatusResult;
  int observeStatusCallCount = 0;

  @override
  ValueStream<ConnectivityStatus> observeStatus() {
    observeStatusCallCount++;
    final ValueStream<ConnectivityStatus>? result = observeStatusResult;
    if (result == null) {
      throw StateError(
        'FakeConnectivityRepository.observeStatusResult was never set',
      );
    }
    return result;
  }
}
