import 'package:connectivity_status/src/data/connectivity_data_source.dart';
import 'package:mocktail/mocktail.dart';

/// Safe under the "no `Mock implements` over a stream getter" rule:
/// [ConnectivityDataSource]'s stream surface is a *method*
/// ([ConnectivityDataSource.observeConnectivity]), not a stream getter.
class MockConnectivityDataSource extends Mock
    implements ConnectivityDataSource {}
