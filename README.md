# dart-packages

Dart packages shared across my apps. One repo, one lockfile, one CI run — a
[pub workspace](https://dart.dev/tools/pub/workspaces), so two packages here can
never disagree about a dependency version.

| Package | |
|---|---|
| [`hlc_sync`](packages/hlc_sync) | Field-level, last-writer-wins sync over any passive blob store, ordered by hybrid logical clocks. |
| [`ui_kit`](packages/ui_kit) | A UI kit that shares Flutter components through my projects. |

## Working on it

```bash
flutter pub get   # resolves every member together, from the root
                   # (the Flutter SDK is required now that ui_kit is a member)
dart analyze
dart test
```

## What belongs here

Something lands here when a **second** app needs it and the boundary is clean
enough that neither app's framework leaks across. Two rules follow from that:

- **No Flutter dependency unless the package genuinely needs one.** A pure Dart
  package runs on servers, in CLIs and in tests without a device. Adding
  `flutter` is not reversible without a breaking change, so it is not added to
  make a name look consistent.
- **The binding stays in the app.** `hlc_sync` defines a `MirrorStore`; the
  drift implementation of it lives in the app that uses drift. What is shared is
  the algorithm, not the storage.
