import 'package:connectivity_status/connectivity_status.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// [createConnectivityRepository] wires the *real* [ConnectivityDataSourceImpl]
/// and [ConnectivityMeteredDataSourceImpl], and the repository probes both
/// eagerly at construction — so exercising it here means standing in for
/// `connectivity_plus`'s own channels, not just calling the factory.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel connectivityChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity',
  );
  const EventChannel connectivityEventChannel = EventChannel(
    'dev.fluttercommunity.plus/connectivity_status',
  );

  setUp(() {
    // An empty result list reads as offline, which settles the
    // construction-time seed without ever reaching this package's own
    // metered probe (the offline short-circuit in ConnectivityRepositoryImpl
    // skips it) — so only connectivity_plus's channels need a mock here.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, (
          MethodCall call,
        ) async {
          return call.method == 'check' ? <String>[] : null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          connectivityEventChannel,
          MockStreamHandler.inline(
            onListen: (Object? arguments, MockStreamHandlerEventSink events) {},
          ),
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(connectivityEventChannel, null);
  });

  test(
    'createConnectivityRepository returns a real, working repository',
    () async {
      final ConnectivityRepository repository = createConnectivityRepository();

      expect(repository, isA<ConnectivityRepositoryImpl>());
      // Let the construction-time seed settle against the mocked channel
      // before reading it — this is the assertion that the factory wired a
      // repository that actually works, not just a type that compiles.
      await Future<void>.delayed(Duration.zero);
      expect(repository.observeStatus().value, ConnectivityStatus.offline);
    },
  );

  test('two calls return independent instances, not a shared singleton', () {
    // A plain constructor call, not a cached/memoized instance — pins that
    // so a future "helpful" cache doesn't silently turn every consumer's
    // registration into one shared repository.
    final ConnectivityRepository a = createConnectivityRepository();
    final ConnectivityRepository b = createConnectivityRepository();

    expect(identical(a, b), isFalse);
  });
}
