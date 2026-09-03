import 'package:flutter_test/flutter_test.dart';
import 'package:preference_store/preference_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _AppKeys { fontSize, isEnabled, volume, userName, tagQueue }

enum _OtherAppKeys { fontSize }

/// A key enum doing the one thing the data source's dartdoc says not to.
enum _OverridingKeys {
  fontSize;

  @override
  String toString() => 'custom.$name';
}

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

  group('the full type matrix — a wrong-type read is null, never a throw', () {
    // The package's single most load-bearing documented rule, and the one a
    // consumer leans on without thinking: "a `tryGetXxx` call returns null
    // both when the key was never written and when the stored value is a
    // different runtime type than requested." Five writers against five
    // readers is twenty-five cells; two of them were pinned before.
    //
    // One test per written type rather than a loop over pairs, so a failure
    // names the type that was stored — which is the half a reader needs to
    // start debugging.

    test('written as int', () async {
      await dataSource.setInt(_AppKeys.fontSize, 16);

      expect(await dataSource.tryGetInt(_AppKeys.fontSize), 16);
      expect(await dataSource.tryGetDouble(_AppKeys.fontSize), isNull);
      expect(await dataSource.tryGetBool(_AppKeys.fontSize), isNull);
      expect(await dataSource.tryGetString(_AppKeys.fontSize), isNull);
      expect(await dataSource.tryGetStringList(_AppKeys.fontSize), isNull);
    });

    test('written as double', () async {
      await dataSource.setDouble(_AppKeys.fontSize, 0.5);

      expect(await dataSource.tryGetDouble(_AppKeys.fontSize), 0.5);
      expect(await dataSource.tryGetInt(_AppKeys.fontSize), isNull);
      expect(await dataSource.tryGetBool(_AppKeys.fontSize), isNull);
      expect(await dataSource.tryGetString(_AppKeys.fontSize), isNull);
      expect(await dataSource.tryGetStringList(_AppKeys.fontSize), isNull);
    });

    test('written as bool', () async {
      await dataSource.setBool(_AppKeys.fontSize, true);

      expect(await dataSource.tryGetBool(_AppKeys.fontSize), true);
      expect(await dataSource.tryGetInt(_AppKeys.fontSize), isNull);
      expect(await dataSource.tryGetDouble(_AppKeys.fontSize), isNull);
      expect(await dataSource.tryGetString(_AppKeys.fontSize), isNull);
      expect(await dataSource.tryGetStringList(_AppKeys.fontSize), isNull);
    });

    test('written as String', () async {
      await dataSource.setString(_AppKeys.fontSize, 'kai');

      expect(await dataSource.tryGetString(_AppKeys.fontSize), 'kai');
      expect(await dataSource.tryGetInt(_AppKeys.fontSize), isNull);
      expect(await dataSource.tryGetDouble(_AppKeys.fontSize), isNull);
      expect(await dataSource.tryGetBool(_AppKeys.fontSize), isNull);
      expect(await dataSource.tryGetStringList(_AppKeys.fontSize), isNull);
    });

    test('written as List<String>', () async {
      await dataSource.setStringList(_AppKeys.fontSize, <String>['a']);

      expect(await dataSource.tryGetStringList(_AppKeys.fontSize), <String>[
        'a',
      ]);
      expect(await dataSource.tryGetInt(_AppKeys.fontSize), isNull);
      expect(await dataSource.tryGetDouble(_AppKeys.fontSize), isNull);
      expect(await dataSource.tryGetBool(_AppKeys.fontSize), isNull);
      expect(await dataSource.tryGetString(_AppKeys.fontSize), isNull);
    });

    test(
      'a bool is not readable as the int some platforms store it as',
      () async {
        // Worth its own case because it is the one mismatch a reader is most
        // likely to assume works: Android's SharedPreferences and iOS's
        // NSUserDefaults both back booleans with integers underneath. The
        // plugin hands Dart a real `bool`, so `tryGetInt` finds no int — and
        // an app that relied on the platform detail would get null forever.
        await dataSource.setBool(_AppKeys.isEnabled, false);

        expect(await dataSource.tryGetBool(_AppKeys.isEnabled), false);
        expect(await dataSource.tryGetInt(_AppKeys.isEnabled), isNull);
      },
    );
  });

  group('written-empty is not never-written', () {
    // The distinction the `tryGetXxx` contract deliberately refuses to make
    // is missing-versus-wrong-type. Missing-versus-empty is a different
    // question, and this one the data source *does* answer: an empty value
    // that was written reads back as itself, not as null.

    test('an empty string round-trips as an empty string', () async {
      await dataSource.setString(_AppKeys.userName, '');

      expect(await dataSource.tryGetString(_AppKeys.userName), '');
      expect(await dataSource.tryGetString(_AppKeys.userName), isNotNull);
    });

    test('an empty list round-trips as an empty list', () async {
      await dataSource.setStringList(_AppKeys.tagQueue, <String>[]);

      expect(await dataSource.tryGetStringList(_AppKeys.tagQueue), <String>[]);
      expect(await dataSource.tryGetStringList(_AppKeys.tagQueue), isNotNull);
    });

    test('zero and false are values, not absences', () async {
      await dataSource.setInt(_AppKeys.fontSize, 0);
      await dataSource.setDouble(_AppKeys.volume, 0);
      await dataSource.setBool(_AppKeys.isEnabled, false);

      expect(await dataSource.tryGetInt(_AppKeys.fontSize), 0);
      expect(await dataSource.tryGetDouble(_AppKeys.volume), 0.0);
      expect(await dataSource.tryGetBool(_AppKeys.isEnabled), false);
    });
  });

  group('values that survive the round trip unchanged', () {
    test('negative and large ints', () async {
      await dataSource.setInt(_AppKeys.fontSize, -1);
      expect(await dataSource.tryGetInt(_AppKeys.fontSize), -1);

      // The largest int the VM holds; platform channels marshal 64-bit
      // integers, so this is the boundary a preference could realistically
      // reach by storing a millisecond timestamp far in the future.
      await dataSource.setInt(_AppKeys.fontSize, 9223372036854775807);
      expect(
        await dataSource.tryGetInt(_AppKeys.fontSize),
        9223372036854775807,
      );
    });

    test('a negative double, and one with a fractional tail', () async {
      await dataSource.setDouble(_AppKeys.volume, -0.125);
      expect(await dataSource.tryGetDouble(_AppKeys.volume), -0.125);
    });

    test('unicode, newlines and the separator the key format uses', () async {
      // The last one matters: keys are `EnumName.memberName`, so a dot in a
      // *value* must not be treated as anything structural.
      const String awkward = '繁體\n中文 · _AppKeys.fontSize';
      await dataSource.setString(_AppKeys.userName, awkward);

      expect(await dataSource.tryGetString(_AppKeys.userName), awkward);
    });

    test('a list keeps its order and its duplicates', () async {
      await dataSource.setStringList(_AppKeys.tagQueue, <String>[
        'b',
        'a',
        'b',
        '',
      ]);

      expect(await dataSource.tryGetStringList(_AppKeys.tagQueue), <String>[
        'b',
        'a',
        'b',
        '',
      ]);
    });
  });

  group('overwriting and removing', () {
    test('the last write wins, including when it changes the type', () async {
      await dataSource.setInt(_AppKeys.fontSize, 16);
      await dataSource.setString(_AppKeys.fontSize, 'sixteen');

      expect(await dataSource.tryGetString(_AppKeys.fontSize), 'sixteen');
      expect(
        await dataSource.tryGetInt(_AppKeys.fontSize),
        isNull,
        reason: 'the int is gone, not shadowed',
      );
    });

    test('removing a key that was never written is a no-op', () async {
      await dataSource.remove(_AppKeys.userName);

      expect(await dataSource.tryGetString(_AppKeys.userName), isNull);
    });

    test('removing one key leaves its neighbours alone', () async {
      await dataSource.setInt(_AppKeys.fontSize, 16);
      await dataSource.setString(_AppKeys.userName, 'kai');

      await dataSource.remove(_AppKeys.fontSize);

      expect(await dataSource.tryGetInt(_AppKeys.fontSize), isNull);
      expect(await dataSource.tryGetString(_AppKeys.userName), 'kai');
    });

    test('a removed key can be written again', () async {
      await dataSource.setInt(_AppKeys.fontSize, 16);
      await dataSource.remove(_AppKeys.fontSize);
      await dataSource.setInt(_AppKeys.fontSize, 20);

      expect(await dataSource.tryGetInt(_AppKeys.fontSize), 20);
    });
  });

  group('the toString hazard the dartdoc warns about', () {
    test('overriding toString changes every stored key in that enum', () async {
      // `PreferenceLocalDataSource`'s dartdoc says not to override
      // `toString()` on a key enum because it changes the storage format.
      // This is that warning as an executable fact rather than prose: a
      // value written under the default format is invisible to an enum that
      // overrides it, which in a real app is every stored preference
      // silently reverting to its default after an upgrade.
      SharedPreferences.setMockInitialValues(<String, Object>{
        '_OverridingKeys.fontSize': 20,
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PreferenceLocalDataSource<_OverridingKeys> overriding =
          PreferenceLocalDataSourceImpl<_OverridingKeys>(prefs);

      expect(await overriding.tryGetInt(_OverridingKeys.fontSize), isNull);

      await overriding.setInt(_OverridingKeys.fontSize, 24);
      expect(prefs.getInt('custom.fontSize'), 24);
      expect(prefs.getInt('_OverridingKeys.fontSize'), 20);
    });
  });

  group('a list that came back from the platform, not from this session', () {
    // The regression group for the defect these tests found. Every other
    // list case here writes and reads inside one session, where the plugin's
    // cache still holds the exact `List<String>` that was handed to it — so
    // they all passed while the real path was broken. The platform channel's
    // codec decodes a list as `List<Object?>`, which is what a preference
    // written before the app was last killed actually looks like on the way
    // back in.

    Future<PreferenceLocalDataSource<_AppKeys>> restoredWith(
      Object stored,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        '_AppKeys.tagQueue': stored,
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return PreferenceLocalDataSourceImpl<_AppKeys>(prefs);
    }

    test('an untyped list of strings reads back as a List<String>', () async {
      final PreferenceLocalDataSource<_AppKeys> restored = await restoredWith(
        <Object?>['a', 'b'],
      );

      expect(await restored.tryGetStringList(_AppKeys.tagQueue), <String>[
        'a',
        'b',
      ]);
    });

    test(
      'an untyped empty list reads back as an empty list, not null',
      () async {
        final PreferenceLocalDataSource<_AppKeys> restored = await restoredWith(
          <Object?>[],
        );

        expect(await restored.tryGetStringList(_AppKeys.tagQueue), <String>[]);
      },
    );

    test('it agrees with the plugin own accessor', () async {
      // The shape of the bug was that these two disagreed: the plugin cast
      // and handed the list over, this package refused it and reported the
      // preference as unset.
      SharedPreferences.setMockInitialValues(<String, Object>{
        '_AppKeys.tagQueue': <Object?>['a', 'b'],
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PreferenceLocalDataSource<_AppKeys> restored =
          PreferenceLocalDataSourceImpl<_AppKeys>(prefs);

      expect(
        await restored.tryGetStringList(_AppKeys.tagQueue),
        prefs.getStringList('_AppKeys.tagQueue'),
      );
    });

    test('a list of the wrong element type is null, not a throw', () async {
      // Still a wrong-type read, so it obeys the same rule as every other
      // cell of the type matrix. `cast<String>()` would satisfy the type
      // system here and then throw on first access.
      final PreferenceLocalDataSource<_AppKeys> restored = await restoredWith(
        <Object?>[1, 2],
      );

      expect(await restored.tryGetStringList(_AppKeys.tagQueue), isNull);
    });

    test(
      'a list that is only partly strings is null, not partial data',
      () async {
        final PreferenceLocalDataSource<_AppKeys> restored = await restoredWith(
          <Object?>['a', 2, 'c'],
        );

        expect(await restored.tryGetStringList(_AppKeys.tagQueue), isNull);
      },
    );

    test(
      'the returned list is a copy, so a caller cannot edit the store',
      () async {
        final PreferenceLocalDataSource<_AppKeys> restored = await restoredWith(
          <Object?>['a'],
        );

        final List<String>? first = await restored.tryGetStringList(
          _AppKeys.tagQueue,
        );
        first?.add('b');

        expect(await restored.tryGetStringList(_AppKeys.tagQueue), <String>[
          'a',
        ]);
      },
    );
  });
}
