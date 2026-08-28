/// Unit tests for [GetConnectivityUseCase] — a thin one-shot delegation to
/// `ConnectivityRepository.getStatus()`.
library;

import 'package:connectivity_status/connectivity_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/connectivity_mocks.dart';

void main() {
  late FakeConnectivityRepository fakeRepository;
  late GetConnectivityUseCase useCase;

  setUp(() {
    fakeRepository = FakeConnectivityRepository();
    useCase = GetConnectivityUseCase(fakeRepository);
  });

  test('[delegation] returns exactly what the repository resolves', () async {
    fakeRepository.response = ConnectivityStatus.unmetered;

    final ConnectivityStatus status = await useCase();

    expect(status, equals(ConnectivityStatus.unmetered));
    expect(fakeRepository.getStatusCallCount, equals(1));
  });

  test(
    '[FMEA-lite] a repository failure propagates, is not swallowed',
    () async {
      final Exception err = Exception('getStatus failed');
      fakeRepository.throwWith = err;

      await expectLater(useCase(), throwsA(same(err)));
    },
  );
}
