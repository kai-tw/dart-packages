/// Unit tests for [ObserveConnectivityUseCase].
///
/// The use case is a thin delegation: `call()` returns
/// `_repository.observeStatus()`. The behavioral contract under test is:
///   1. Stream identity — the use case returns the repository's stream
///      verbatim. Any transformation / re-broadcast would be a behavior
///      change.
///   2. Emission pass-through — values pushed onto the repository's stream
///      reach use-case subscribers in order.
///   3. Error pass-through — errors raised on the repository's stream reach
///      use-case subscribers (the use case must not swallow).
library;

import 'dart:async';

import 'package:connectivity_status/connectivity_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rxdart/rxdart.dart';

import 'helpers/connectivity_mocks.dart';

void main() {
  late MockConnectivityRepository mockRepository;
  late ObserveConnectivityUseCase useCase;

  setUp(() {
    mockRepository = MockConnectivityRepository();
    useCase = ObserveConnectivityUseCase(mockRepository);
  });

  group('ObserveConnectivityUseCase', () {
    test('[mutation pin / delegation] returns the exact stream from '
        'ConnectivityRepository.observeStatus() — no re-wrap', () {
      final BehaviorSubject<ConnectivityStatus> subject =
          BehaviorSubject<ConnectivityStatus>.seeded(
            ConnectivityStatus.offline,
          );
      addTearDown(subject.close);

      when(() => mockRepository.observeStatus()).thenAnswer((_) => subject);

      final ValueStream<ConnectivityStatus> result = useCase();

      // Identity check pins against accidental `.map(...)`,
      // `.asBroadcastStream()`, or `.transform(...)` regressions — those
      // would return a *different* stream object even though the events
      // line up. The contract is "pass through, don't re-shape".
      expect(result, same(subject));
      verify(() => mockRepository.observeStatus()).called(1);
    });

    test('[scenario] consumer of the use-case stream receives every emission '
        'from the repository in order', () async {
      final BehaviorSubject<ConnectivityStatus> subject =
          BehaviorSubject<ConnectivityStatus>.seeded(
            ConnectivityStatus.offline,
          );
      addTearDown(subject.close);
      when(() => mockRepository.observeStatus()).thenAnswer((_) => subject);

      final List<ConnectivityStatus> received = <ConnectivityStatus>[];
      final StreamSubscription<ConnectivityStatus> subscription = useCase()
          .listen(received.add);
      addTearDown(subscription.cancel);

      // BehaviorSubject replays seed immediately; drain it first.
      await Future<void>.delayed(Duration.zero);
      received.clear();

      subject.add(ConnectivityStatus.offline);
      subject.add(ConnectivityStatus.unmetered);
      subject.add(ConnectivityStatus.unmetered);
      await Future<void>.delayed(Duration.zero);

      expect(received, <ConnectivityStatus>[
        ConnectivityStatus.offline,
        ConnectivityStatus.unmetered,
        ConnectivityStatus.unmetered,
      ]);
    });

    test('[FMEA-lite] error raised on the repository stream propagates to '
        'use-case subscribers', () async {
      final BehaviorSubject<ConnectivityStatus> subject =
          BehaviorSubject<ConnectivityStatus>.seeded(
            ConnectivityStatus.offline,
          );
      addTearDown(subject.close);
      when(() => mockRepository.observeStatus()).thenAnswer((_) => subject);

      final List<Object> errors = <Object>[];
      final StreamSubscription<ConnectivityStatus> subscription = useCase()
          .listen((_) {}, onError: errors.add);
      addTearDown(subscription.cancel);

      final Exception err = Exception('connectivity stream failed');
      subject.addError(err);
      await Future<void>.delayed(Duration.zero);

      // Pin against a silent `.handleError((_) {})` wrap in the use case —
      // that would swallow infrastructure failures and starve recovery
      // handlers.
      expect(errors, <Object>[err]);
    });
  });
}
