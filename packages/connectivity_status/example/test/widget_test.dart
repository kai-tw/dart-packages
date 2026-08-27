import 'package:connectivity_status/connectivity_status.dart';
import 'package:connectivity_status_example/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';

void main() {
  testWidgets('renders the live status once the stream emits', (
    WidgetTester tester,
  ) async {
    final BehaviorSubject<ConnectivityStatus> subject =
        BehaviorSubject<ConnectivityStatus>.seeded(
          ConnectivityStatus.unmetered,
        );
    addTearDown(subject.close);

    await tester.pumpWidget(
      MyApp(
        getConnectivity: GetConnectivityUseCase(_FakeRepository(subject)),
        observeConnectivity: ObserveConnectivityUseCase(
          _FakeRepository(subject),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Status: unmetered'), findsOneWidget);
  });
}

class _FakeRepository implements ConnectivityRepository {
  _FakeRepository(this._subject);

  final BehaviorSubject<ConnectivityStatus> _subject;

  @override
  Future<ConnectivityStatus> getStatus() async => _subject.value;

  @override
  ValueStream<ConnectivityStatus> observeStatus() => _subject.stream;
}
