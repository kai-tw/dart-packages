import 'package:connectivity_status/connectivity_status.dart';
import 'package:connectivity_status/src/data/connectivity_repository_impl.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers [ConnectivityRepository.instance] — the *only* way to get a real
/// repository (there is no separate "build me a fresh one" constructor; a
/// device has exactly one real network state). It wires the real
/// [ConnectivityDataSourceImpl] and probes it eagerly at construction, so
/// exercising it here means standing in for `connectivity_plus`'s own
/// channels, not just reading a getter.
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
    ConnectivityRepository.resetInstance();
  });

  test('is a real, working repository', () async {
    final ConnectivityRepository repository = ConnectivityRepository.instance;

    await Future<void>.delayed(Duration.zero);
    expect(repository.observeStatus().value, ConnectivityStatus.offline);
  });

  test(
    'is backed by the internal impl, not something a consumer could swap',
    () {
      // The one place this package's own test suite pins the concrete
      // class — proving the public accessor actually returns a real,
      // working object rather than, say, an unimplemented stub. No
      // consumer test should ever need to do this.
      expect(
        ConnectivityRepository.instance,
        isA<ConnectivityRepositoryImpl>(),
      );
    },
  );

  test('returns the same instance on every access', () {
    final ConnectivityRepository a = ConnectivityRepository.instance;
    final ConnectivityRepository b = ConnectivityRepository.instance;

    expect(identical(a, b), isTrue);
  });

  test('resetInstance() drops the cache — the next access builds fresh', () {
    final ConnectivityRepository before = ConnectivityRepository.instance;

    ConnectivityRepository.resetInstance();
    final ConnectivityRepository after = ConnectivityRepository.instance;

    expect(
      identical(before, after),
      isFalse,
      reason:
          'A stale reset that no-ops would leave every test after the '
          'first one sharing a repository built (and already '
          'platform-probed) for a prior test.',
    );
  });
}
