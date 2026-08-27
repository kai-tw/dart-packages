// Since integration tests run in a full Flutter application, they exercise
// the real native metered-probe channel, unlike the package's Dart unit
// tests (which mock ConnectivityMeteredDataSource). See
// https://flutter.dev/to/integration-testing.

import 'package:connectivity_status/connectivity_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'the metered channel answers true, false, or MissingPluginException — '
    'never a stale wrapper exception',
    (WidgetTester tester) async {
      // .platform() isolates the native channel itself, same principle as
      // ConnectivityRepository.platform — this test never names the
      // implementation class.
      final ConnectivityMeteredDataSource source =
          ConnectivityMeteredDataSource.platform();

      // On a real iOS/Android device or simulator this resolves via the
      // native handler this package ships; MissingPluginException would mean
      // GeneratedPluginRegistrant never wired ConnectivityStatusPlugin in
      // for this build.
      final bool? metered = await source.isActiveNetworkMetered();

      expect(metered, anyOf(isTrue, isFalse, isNull));
    },
  );

  testWidgets(
    'GetConnectivityUseCase.shared() resolves a real status against the '
    'real adapters',
    (WidgetTester tester) async {
      // The same zero-config path a real consumer with no DI framework
      // would use — not a hand-assembled repository.
      final ConnectivityStatus status = await GetConnectivityUseCase.shared()();

      expect(ConnectivityStatus.values, contains(status));
    },
  );
}
