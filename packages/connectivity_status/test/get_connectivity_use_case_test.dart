/// Unit tests for [GetConnectivityUseCase] — a thin one-shot delegation to
/// `ConnectivityRepository.getStatus()`.
library;

import 'package:connectivity_status/connectivity_status.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers/connectivity_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GetConnectivityUseCase.shared', () {
    // .shared() wraps the real ConnectivityRepositoryImpl.instance, which
    // probes connectivity_plus's own channel eagerly at construction — the
    // same reason ConnectivityRepositoryImpl.platform's own tests need this
    // mock, not a mocktail double.
    const MethodChannel connectivityChannel = MethodChannel(
      'dev.fluttercommunity.plus/connectivity',
    );
    const EventChannel connectivityEventChannel = EventChannel(
      'dev.fluttercommunity.plus/connectivity_status',
    );

    late int checkCalls;

    setUp(() {
      checkCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(connectivityChannel, (
            MethodCall call,
          ) async {
            if (call.method != 'check') {
              return null;
            }
            checkCalls++;
            return <String>[];
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            connectivityEventChannel,
            MockStreamHandler.inline(
              onListen:
                  (Object? arguments, MockStreamHandlerEventSink events) {},
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

    test(
      'reuses ConnectivityRepositoryImpl.instance, not a fresh repository',
      () async {
        // Force the singleton to exist and its construction-time seed to
        // settle first, so the count below isolates what .shared() itself
        // causes.
        ConnectivityRepositoryImpl.instance;
        await Future<void>.delayed(Duration.zero);
        final int callsBeforeSharedUseCase = checkCalls;

        await GetConnectivityUseCase.shared()();

        expect(
          checkCalls,
          equals(callsBeforeSharedUseCase + 1),
          reason:
              "Exactly one more call: the use case's own getStatus(). If "
              '.shared() built a fresh repository instead of reusing the '
              "singleton, that repository's own construction-time seed would "
              'add a second call here.',
        );
      },
    );
  });
  late MockConnectivityRepository mockRepository;
  late GetConnectivityUseCase useCase;

  setUp(() {
    mockRepository = MockConnectivityRepository();
    useCase = GetConnectivityUseCase(mockRepository);
  });

  test('[delegation] returns exactly what the repository resolves', () async {
    when(
      () => mockRepository.getStatus(),
    ).thenAnswer((_) async => ConnectivityStatus.unmetered);

    final ConnectivityStatus status = await useCase();

    expect(status, equals(ConnectivityStatus.unmetered));
    verify(() => mockRepository.getStatus()).called(1);
  });

  test(
    '[FMEA-lite] a repository failure propagates, is not swallowed',
    () async {
      // `thenAnswer((_) async => throw err)`, not `thenThrow(err)` — the real
      // ConnectivityRepositoryImpl.getStatus() is `async`, so a throw inside it
      // always arrives as a rejected Future. `thenThrow` makes the mocked call
      // throw synchronously instead, which would fail before `useCase()` even
      // returns a Future to assert against.
      final Exception err = Exception('getStatus failed');
      when(() => mockRepository.getStatus()).thenAnswer((_) async => throw err);

      await expectLater(useCase(), throwsA(same(err)));
    },
  );
}
