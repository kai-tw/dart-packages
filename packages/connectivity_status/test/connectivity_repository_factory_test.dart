import 'package:connectivity_status/connectivity_status.dart';
import 'package:connectivity_status/src/data/connectivity_repository_impl.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers [ConnectivityRepository]'s factory constructor — the only way to
/// get a real repository. It wires the real [ConnectivityDataSourceImpl] and
/// probes it eagerly at construction, so exercising it here means standing
/// in for `connectivity_plus`'s own channels, not just calling a
/// constructor.
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

  test('is a real, working repository', () async {
    final ConnectivityRepository repository = ConnectivityRepository();

    await Future<void>.delayed(Duration.zero);
    expect(repository.observeStatus().value, ConnectivityStatus.offline);
  });

  test(
    'is backed by the internal impl, not something a consumer could swap',
    () {
      // The one place this package's own test suite pins the concrete
      // class — proving the public factory actually returns a real,
      // working object rather than, say, an unimplemented stub. No
      // consumer test should ever need to do this.
      expect(ConnectivityRepository(), isA<ConnectivityRepositoryImpl>());
    },
  );

  test('each call builds an independent instance', () {
    // Unlike the removed .instance singleton — a device has one real
    // network state, but nothing about this factory pretends to enforce
    // that. Whether an app treats it as a singleton is its own DI
    // container's call, not this package's.
    final ConnectivityRepository a = ConnectivityRepository();
    final ConnectivityRepository b = ConnectivityRepository();

    expect(identical(a, b), isFalse);
  });
}
