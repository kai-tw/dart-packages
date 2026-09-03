/// A typed, key-namespaced wrapper over `SharedPreferences`.
///
/// [K] is the app's own preference-key enum — this package never sees its
/// members, only calls `.toString()` on them. That has two consequences
/// worth knowing before choosing a key enum:
///
/// - Storage is keyed by the default `EnumName.memberName` string Dart
///   gives every enum value, so two different key enums can never collide,
///   and reordering members within one enum does not change any stored
///   key.
/// - A key enum that overrides `toString()` changes the storage format for
///   every key in it. Do not override it.
///
/// A `tryGetXxx` call returns `null` both when the key was never written
/// and when the stored value is a different runtime type than requested —
/// callers cannot and should not distinguish the two.
///
/// For [tryGetStringList] the type check is per element rather than on the
/// list itself, because a list restored from the platform arrives untyped:
/// a list of strings is returned however it is typed, and a list holding
/// anything else is `null` like any other wrong-type read.
abstract class PreferenceLocalDataSource<K extends Enum> {
  Future<int?> tryGetInt(K key);

  Future<double?> tryGetDouble(K key);

  Future<bool?> tryGetBool(K key);

  Future<String?> tryGetString(K key);

  Future<List<String>?> tryGetStringList(K key);

  Future<void> setInt(K key, int value);

  Future<void> setDouble(K key, double value);

  Future<void> setBool(K key, bool value);

  Future<void> setString(K key, String value);

  Future<void> setStringList(K key, List<String> value);

  Future<void> remove(K key);
}
