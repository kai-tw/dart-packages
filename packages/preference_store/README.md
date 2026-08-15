# preference_store

Typed, enum-keyed access over `SharedPreferences`.

Extracted from NovelGlide, where fourteen preference domains (reader
settings, TTS, cloud sync, …) all wrapped the same generic engine: a typed
repository seam over a key-value store, keyed by an enum instead of a raw
string. This package is that engine, and nothing else.

```dart
enum AppKeys { themeMode, fontSize }

final SharedPreferences prefs = await SharedPreferences.getInstance();
final PreferenceLocalDataSource<AppKeys> dataSource =
    PreferenceLocalDataSourceImpl<AppKeys>(prefs);

await dataSource.setInt(AppKeys.fontSize, 16);
final int? fontSize = await dataSource.tryGetInt(AppKeys.fontSize);
```

## What this package does not do

- **No entities.** `AppearancePreferenceData`, `ReaderPreferenceData` and
  the rest of NovelGlide's fourteen domain shapes stayed behind — this
  package has no opinion on what your preferences look like.
- **No key enum.** You own `AppKeys` (or however many enums you need); the
  data source only ever calls `.toString()` on whatever you pass it.
- **No DI wiring.** Register `PreferenceLocalDataSourceImpl` with whatever
  service locator (or none) your app already uses.

## The two symbols

### `PreferenceRepository<T>`

```dart
abstract class PreferenceRepository<T> {
  Stream<T> get onChangeStream;
  Future<T> getPreference();
  Future<void> savePreference(T data);
  Future<void> resetPreference();
}
```

The contract every feature-level preference repository implements. This
package ships the interface only — each domain's `getPreference` /
`savePreference` (how `T` maps to primitives) is app-specific and lives in
the app.

A `typedef` per domain is how NovelGlide turns the shared generic type into
a distinct, named DI key:

```dart
typedef ReaderPreferenceRepository = PreferenceRepository<ReaderPreferenceData>;
```

`sl<ReaderPreferenceRepository>()` and `sl<TtsPreferenceRepository>()`
resolve to different singletons even though both extend the same generic
base — the typedef, not the base class, is what a service locator keys on.

### `PreferenceLocalDataSource<K>` / `PreferenceLocalDataSourceImpl<K>`

The engine underneath: `tryGetInt` / `setInt` / … against
`SharedPreferences`, keyed by `key.toString()` where `key` is a value of
your own enum `K`.

**`key.toString()`, not `key.name`, and that is load-bearing.** A plain
Dart enum's default `toString()` is `EnumName.memberName` — the type name
is part of the stored key. That is what makes two unrelated key enums
unable to collide, and it is why an override of `toString()` on a key enum
is not a decoration choice: it changes the storage format for every key
in it. Once an app has real users, that format is the on-device schema —
changing it silently strands their existing data behind a key nothing
reads anymore.

`tryGetXxx` returns `null` for a missing key and for a stored value of the
wrong runtime type alike — a caller cannot and should not tell the two
apart; both mean "there is nothing usable here yet," which is the signal
that lets a repository fall back to its default.
