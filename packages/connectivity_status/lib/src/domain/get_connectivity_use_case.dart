import 'connectivity_repository.dart';
import 'connectivity_status.dart';

/// One-shot query for the device's current network state.
///
/// Use this when the caller needs the current [ConnectivityStatus] at a
/// single decision point and does not need to react to future
/// transitions. Subscribers that must re-render on every change use
/// [ObserveConnectivityUseCase] instead.
///
/// A plain class with a `call()` method, not a shared `UseCase` base —
/// this package takes no position on a consuming app's use-case
/// convention, the same reasoning that already keeps `ui_kit` and
/// `preference_store` framework-agnostic.
class GetConnectivityUseCase {
  const GetConnectivityUseCase(this._repository);

  /// No DI framework? This is the zero-config path — wraps the shared
  /// [ConnectivityRepository.instance] instead of one you build and pass
  /// in yourself.
  factory GetConnectivityUseCase.shared() =>
      GetConnectivityUseCase(ConnectivityRepository.instance);

  final ConnectivityRepository _repository;

  Future<ConnectivityStatus> call() => _repository.getStatus();
}
