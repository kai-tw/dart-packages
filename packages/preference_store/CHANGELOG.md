# Changelog

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
