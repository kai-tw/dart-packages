import 'package:connectivity_status/connectivity_status.dart';
import 'package:mocktail/mocktail.dart';

/// Safe for the same reason as `MockConnectivityDataSource`:
/// [ConnectivityRepository.observeStatus] is a method, not a stream getter.
class MockConnectivityRepository extends Mock
    implements ConnectivityRepository {}
