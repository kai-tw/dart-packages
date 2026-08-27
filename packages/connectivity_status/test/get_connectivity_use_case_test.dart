/// Unit tests for [GetConnectivityUseCase] — a thin one-shot delegation to
/// `ConnectivityRepository.getStatus()`.
library;

import 'package:connectivity_status/connectivity_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers/connectivity_mocks.dart';

void main() {
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
