import 'package:rxdart/rxdart.dart';

import 'connectivity_repository.dart';
import 'connectivity_status.dart';

/// Observes the device's network state.
///
/// Emits the current [ConnectivityStatus] immediately, then again on every
/// transition. Consumers can detect offline → online transitions to
/// trigger retries of work that previously failed due to no connectivity.
///
/// Returns a [ValueStream] — [ValueStream.value] gives the current status
/// synchronously without an await.
///
/// A plain class with a `call()` method, not a shared `UseCase` base — see
/// [GetConnectivityUseCase] for why.
class ObserveConnectivityUseCase {
  const ObserveConnectivityUseCase(this._repository);

  /// No DI framework? This is the zero-config path — see
  /// [GetConnectivityUseCase.shared].
  factory ObserveConnectivityUseCase.shared() =>
      ObserveConnectivityUseCase(ConnectivityRepository.instance);

  final ConnectivityRepository _repository;

  ValueStream<ConnectivityStatus> call() => _repository.observeStatus();
}
