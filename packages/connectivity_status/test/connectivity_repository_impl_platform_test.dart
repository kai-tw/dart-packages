import 'package:connectivity_status/connectivity_status.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers [ConnectivityRepositoryImpl.platform] and the shared
/// [ConnectivityRepositoryImpl.instance] — both wire the *real*
/// [ConnectivityDataSourceImpl], and the repository probes it eagerly at
/// construction, so exercising either here means standing in for
/// `connectivity_plus`'s own channels, not just calling a constructor.
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
    ConnectivityRepositoryImpl.resetInstance();
  });

  group('ConnectivityRepositoryImpl.platform', () {
    test('returns a real, working repository', () async {
      final ConnectivityRepository repository =
          ConnectivityRepositoryImpl.platform();

      expect(repository, isA<ConnectivityRepositoryImpl>());
      await Future<void>.delayed(Duration.zero);
      expect(repository.observeStatus().value, ConnectivityStatus.offline);
    });

    test('each call builds an independent instance, not a shared one', () {
      final ConnectivityRepository a = ConnectivityRepositoryImpl.platform();
      final ConnectivityRepository b = ConnectivityRepositoryImpl.platform();

      expect(identical(a, b), isFalse);
    });
  });

  group('ConnectivityRepositoryImpl.instance', () {
    test('returns the same instance on every access', () {
      final ConnectivityRepository a = ConnectivityRepositoryImpl.instance;
      final ConnectivityRepository b = ConnectivityRepositoryImpl.instance;

      expect(identical(a, b), isTrue);
    });

    test('resetInstance() drops the cache — the next access builds fresh', () {
      final ConnectivityRepository before = ConnectivityRepositoryImpl.instance;

      ConnectivityRepositoryImpl.resetInstance();
      final ConnectivityRepository after = ConnectivityRepositoryImpl.instance;

      expect(
        identical(before, after),
        isFalse,
        reason:
            'A stale reset that no-ops would leave every test after the '
            'first one sharing a repository built (and already '
            'platform-probed) for a prior test.',
      );
    });
  });
}
