import 'package:connectivity_status/connectivity_status.dart';
import 'package:flutter/material.dart';

void main() {
  // Required before touching any platform channel — the shared
  // ConnectivityRepository.instance behind `.shared()` seeds itself from
  // the connectivity and metered adapters immediately on first access, so
  // this must come first, not after runApp(), which would otherwise
  // initialize the binding one line too late.
  WidgetsFlutterBinding.ensureInitialized();

  // This example has no DI framework of its own — `.shared()` is the
  // zero-config path, wrapping ConnectivityRepository.instance. A consumer
  // using get_it or Riverpod would register that same instance with its
  // container instead and inject the result via the plain constructors.
  runApp(
    MyApp(
      getConnectivity: GetConnectivityUseCase.shared(),
      observeConnectivity: ObserveConnectivityUseCase.shared(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.getConnectivity,
    required this.observeConnectivity,
  });

  final GetConnectivityUseCase getConnectivity;
  final ObserveConnectivityUseCase observeConnectivity;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('connectivity_status example')),
        body: Center(
          child: StreamBuilder<ConnectivityStatus>(
            stream: observeConnectivity(),
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<ConnectivityStatus> snapshot,
                ) {
                  final ConnectivityStatus? status = snapshot.data;
                  return Text(
                    status == null ? 'Reading…' : 'Status: ${status.name}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  );
                },
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final ConnectivityStatus status = await getConnectivity();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('One-shot read: ${status.name}')),
              );
            }
          },
          label: const Text('Read once'),
        ),
      ),
    );
  }
}
