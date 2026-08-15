import 'package:shared_preferences/shared_preferences.dart';

import 'preference_local_data_source.dart';

class PreferenceLocalDataSourceImpl<K extends Enum>
    implements PreferenceLocalDataSource<K> {
  PreferenceLocalDataSourceImpl(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<void> setBool(K key, bool value) {
    return _prefs.setBool(key.toString(), value);
  }

  @override
  Future<void> setDouble(K key, double value) {
    return _prefs.setDouble(key.toString(), value);
  }

  @override
  Future<void> setInt(K key, int value) {
    return _prefs.setInt(key.toString(), value);
  }

  @override
  Future<void> setString(K key, String value) {
    return _prefs.setString(key.toString(), value);
  }

  @override
  Future<void> setStringList(K key, List<String> value) {
    return _prefs.setStringList(key.toString(), value);
  }

  @override
  Future<bool?> tryGetBool(K key) async {
    final Object? value = _prefs.get(key.toString());
    return value is bool ? value : null;
  }

  @override
  Future<double?> tryGetDouble(K key) async {
    final Object? value = _prefs.get(key.toString());
    return value is double ? value : null;
  }

  @override
  Future<int?> tryGetInt(K key) async {
    final Object? value = _prefs.get(key.toString());
    return value is int ? value : null;
  }

  @override
  Future<String?> tryGetString(K key) async {
    final Object? value = _prefs.get(key.toString());
    return value is String ? value : null;
  }

  @override
  Future<List<String>?> tryGetStringList(K key) async {
    final Object? value = _prefs.get(key.toString());
    return value is List<String> ? value : null;
  }

  @override
  Future<void> remove(K key) {
    return _prefs.remove(key.toString());
  }
}
