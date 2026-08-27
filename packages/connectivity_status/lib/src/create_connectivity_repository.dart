import 'data/connectivity_data_source_impl.dart';
import 'data/connectivity_metered_data_source_impl.dart';
import 'data/connectivity_repository_impl.dart';
import 'domain/connectivity_repository.dart';

/// Builds the one real [ConnectivityRepository]: the platform's
/// [ConnectivityDataSourceImpl] and [ConnectivityMeteredDataSourceImpl]
/// behind [ConnectivityRepositoryImpl].
///
/// Unlike `preference_store`'s `PreferenceRepository<T>` — a template every
/// consumer instantiates into its own shape — there is exactly one correct
/// way to assemble this repository. Nothing here assumes a DI framework:
/// register the *result* with whatever your app already uses.
///
/// ```dart
/// // get_it
/// sl.registerLazySingleton<ConnectivityRepository>(createConnectivityRepository);
///
/// // riverpod
/// @riverpod
/// ConnectivityRepository connectivityRepository(Ref ref) =>
///     createConnectivityRepository();
/// ```
ConnectivityRepository createConnectivityRepository() =>
    ConnectivityRepositoryImpl(
      ConnectivityDataSourceImpl(),
      ConnectivityMeteredDataSourceImpl(),
    );
