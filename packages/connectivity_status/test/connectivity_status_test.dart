import 'package:connectivity_status/connectivity_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConnectivityStatus entity', () {
    test(
      'ConnectivityStatus.offline is isOnline=false and is not cellular',
      () {
        expect(ConnectivityStatus.offline.isOnline, isFalse);
        expect(
          ConnectivityStatus.offline,
          isNot(equals(ConnectivityStatus.cellular)),
        );
      },
    );

    test('cellular and unmetered are both online', () {
      expect(ConnectivityStatus.cellular.isOnline, isTrue);
      expect(ConnectivityStatus.unmetered.isOnline, isTrue);
    });

    test('enum values have stable equality and hashCode', () {
      const ConnectivityStatus a = ConnectivityStatus.unmetered;
      const ConnectivityStatus b = ConnectivityStatus.unmetered;
      const ConnectivityStatus c = ConnectivityStatus.cellular;

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}
