import 'package:connectivity_plus/connectivity_plus.dart';

import 'connectivity_data_source.dart';

class ConnectivityDataSourceImpl implements ConnectivityDataSource {
  ConnectivityDataSourceImpl([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() =>
      _connectivity.checkConnectivity();

  @override
  Stream<List<ConnectivityResult>> observeConnectivity() =>
      _connectivity.onConnectivityChanged;
}
