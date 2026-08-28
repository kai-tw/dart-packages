import 'package:connectivity_status/connectivity_status.dart';
import 'package:flutter/material.dart';

void main() {
  // Required before touching any platform channel — building the
  // repository below seeds itself from the connectivity and metered
  // adapters immediately, so this must come first, not after runApp(),
  // which would otherwise initialize the binding one line too late.
  WidgetsFlutterBinding.ensureInitialized();

  // This example has no DI framework of its own — build the repository
  // once here and pass it into both use cases. A consumer using get_it or
  // Riverpod would register this same construction with its container
  // instead and inject the result via the plain constructors.
  final ConnectivityRepository connectivity = ConnectivityRepository();

  // This package has no logging dependency of its own — errors are just a
  // stream. debugPrint here stands in for whatever an app already uses
  // (log_system, Crashlytics, ...).
  connectivity.exceptions.listen(
    (ConnectivityException exception) => debugPrint(exception.toString()),
  );

  runApp(
    MyApp(
      getConnectivity: GetConnectivityUseCase(connectivity),
      observeConnectivity: ObserveConnectivityUseCase(connectivity),
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
