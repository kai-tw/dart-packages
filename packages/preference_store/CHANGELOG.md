# Changelog

## 0.1.1

**Fixes a defect that made every stored `List<String>` preference read back
as null after an app restart.**

`tryGetStringList` tested the value with `is List<String>`. `SharedPreferences.get`
returns the plugin's cache verbatim, and that cache is filled from the platform
channel, whose codec decodes a list as `List<Object?>` — so a list written in an
earlier session came back untyped and was dropped. Within one session the cache
still holds the exact list that was written, which is why the round-trip tests
passed and the bug only showed on the next launch: the preference silently
reverted to its default, every time. `SharedPreferences.getStringList` casts for
exactly this reason.

The check is now `is List` plus a per-element check. Element-checked rather than
`cast<String>()`, because a list of the wrong element type has to return null
like every other wrong-type read, and `cast` would satisfy the type system and
then throw on first access. The list handed back is a copy, so a caller cannot
mutate the plugin's cache.

No API change. Consumers storing string-list preferences will see values that
were being lost start being read again — including any written before this fix,
since nothing about the storage format changed.

Tests went from 10 to 34, with the regression group written so it fails on the
old implementation: it seeds the store the way a restart does, rather than
writing and reading in one session, which is the property that hid this.

## 0.1.0

Initial extraction, from NovelGlide's preference feature.

- `PreferenceRepository<T>` — the observable, typed seam a feature-level
  preference repository implements.
- `PreferenceLocalDataSource<K>` / `PreferenceLocalDataSourceImpl<K>` — the
  generic `SharedPreferences` engine underneath, keyed by an app-owned enum.

Differences from the code it was extracted from:

- The key type is generic (`K extends Enum`) instead of hard-coded to one
  app's key enum. Storage is still `key.toString()`, so nothing already
  persisted on a device changes shape.
- Domain entities, per-domain repository implementations, the key enum
  itself, and DI wiring all stayed behind — this package owns only the part
  that was identical across every one of them.
