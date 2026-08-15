import 'package:flutter_test/flutter_test.dart';
import 'package:preference_store/preference_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _AppKeys { fontSize, isEnabled, volume, userName, tagQueue }

enum _OtherAppKeys { fontSize }

void main() {
  late PreferenceLocalDataSource<_AppKeys> dataSource;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    dataSource = PreferenceLocalDataSourceImpl<_AppKeys>(prefs);
  });

  group('round trip per primitive type', () {
    test('int', () async {
      await dataSource.setInt(_AppKeys.fontSize, 16);
      expect(await dataSource.tryGetInt(_AppKeys.fontSize), 16);
    });

    test('double', () async {
      await dataSource.setDouble(_AppKeys.volume, 0.5);
      expect(await dataSource.tryGetDouble(_AppKeys.volume), 0.5);
    });

    test('bool', () async {
      await dataSource.setBool(_AppKeys.isEnabled, true);
      expect(await dataSource.tryGetBool(_AppKeys.isEnabled), true);
    });

    test('String', () async {
      await dataSource.setString(_AppKeys.userName, 'kai');
      expect(await dataSource.tryGetString(_AppKeys.userName), 'kai');
    });

    test('List<String>', () async {
      await dataSource.setStringList(_AppKeys.tagQueue, <String>['a', 'b']);
      expect(await dataSource.tryGetStringList(_AppKeys.tagQueue), <String>[
        'a',
        'b',
      ]);
    });
  });

  group('missing and mismatched reads both return null', () {
    test('never-written key reads as null for every type', () async {
      expect(await dataSource.tryGetInt(_AppKeys.fontSize), isNull);
      expect(await dataSource.tryGetDouble(_AppKeys.fontSize), isNull);
      expect(await dataSource.tryGetBool(_AppKeys.fontSize), isNull);
      expect(await dataSource.tryGetString(_AppKeys.fontSize), isNull);
      expect(await dataSource.tryGetStringList(_AppKeys.fontSize), isNull);
    });

    test(
      'stored as one type, read as another → null, not a cast error',
      () async {
        await dataSource.setInt(_AppKeys.fontSize, 16);
        expect(await dataSource.tryGetString(_AppKeys.fontSize), isNull);
        expect(await dataSource.tryGetBool(_AppKeys.fontSize), isNull);
      },
    );
  });

  test('remove clears the value back to null', () async {
    await dataSource.setInt(_AppKeys.fontSize, 16);
    await dataSource.remove(_AppKeys.fontSize);
    expect(await dataSource.tryGetInt(_AppKeys.fontSize), isNull);
  });

  group('storage key format — load-bearing, do not change casually', () {
    test(
      'key is stored under EnumName.memberName, not the bare member name',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          '_AppKeys.fontSize': 20,
        });
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        dataSource = PreferenceLocalDataSourceImpl<_AppKeys>(prefs);

        expect(await dataSource.tryGetInt(_AppKeys.fontSize), 20);
      },
    );

    test(
      'two different key enums with the same member name never collide',
      () async {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final PreferenceLocalDataSource<_OtherAppKeys> otherDataSource =
            PreferenceLocalDataSourceImpl<_OtherAppKeys>(prefs);

        await dataSource.setInt(_AppKeys.fontSize, 16);
        await otherDataSource.setInt(_OtherAppKeys.fontSize, 24);

        expect(await dataSource.tryGetInt(_AppKeys.fontSize), 16);
        expect(await otherDataSource.tryGetInt(_OtherAppKeys.fontSize), 24);
      },
    );
  });
}
