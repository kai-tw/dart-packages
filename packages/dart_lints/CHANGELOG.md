## 0.2.1

- `avoid_hardcoded_color` no longer reports a `Color` built from a value the
  code did not write down — `Color(row.colour)`, `Color(int.parse(hex, radix:
  16))`, `Color.fromARGB(alpha, 0, 0, 0)`. Only a colour stated in the source is
  hardcoded, which is what the rule is named after and what every example in its
  own documentation shows.

  The rule matched on the constructor rather than on its arguments, so it also
  caught the one shape that has no fix: a colour the user picked and the app
  stored. `Theme.of(context).colorScheme.*` is not an alternative to reading a
  value out of a database, and a consuming project could only silence it by
  exempting the file — which then silences the real violations there too.

  An argument list built out of literals but computed (`Color(base + 1)`) counts
  as not-written-down. The rule cannot evaluate arithmetic, and the lenient
  direction is the right one: the miss is a colour someone obscured on purpose,
  while a false report names a fix that does not exist.

  Expect the count to fall in any project that stores colours. `Colors.X` and
  `.withOpacity()` are unaffected.

- The rule gains a test. It had none, and the fixture has to be a **resolved**
  unit — parsed, `Color(0xff112233)` is indistinguishable from a function call,
  so a parse-only fixture reports nothing and passes whatever the rule does.

## 0.2.0

- **Breaking.** `novelglide_avoid_shared_preferences_outside_preference` is
  replaced by `avoid_shared_preferences_outside_owner` in the `clean_arch`
  bundle, with the allowed paths moved from a hardcoded regex into an
  `ownerPaths` option.

  The rule was general all along — one owner for the key-value store, everyone
  else takes a typed repository — but its four owner paths were compiled in
  (`features/preference/`, `features/migration/processes/`,
  `core/setup_dependencies.dart`, `lib/main.dart`) and its registry entry
  ignored the options map entirely. A second app whose preference layer sits at
  `core/preferences/` could not use it: enabling it would report the new owner
  as the violation. The `novelglide_` prefix said "this encodes one
  application", and for the paths that was true; for the idea it never was.

  Migrating: rename the rule in `dart_lints.yaml`, move it out of the
  `novelglide` bundle list, and name your owner paths. NovelGlide's four
  hardcoded paths spell out as:

  ```yaml
  bundles: [core, flutter, clean_arch, bloc, getit, log_system, novelglide]

  options:
    avoid_shared_preferences_outside_owner:
      ownerPaths:
        - features/preference/
        - features/migration/processes/
        - core/setup_dependencies.dart
        - lib/main.dart
  ```

  Those four are the old rule's own list, and they still hold: at NovelGlide's
  `main` (`5b6c472a`) every Dart file importing the package sits under one of
  them — `core/setup_dependencies.dart`, four files in
  `features/migration/processes/`, and `features/preference/setup_dependencies.dart`.
  `lib/main.dart` no longer imports it at all, and is listed only for fidelity
  to what the rule used to allow.

  ⚠️ **This reaches every repository that enables `clean_arch`, not only the one
  that used the old rule.** `ownerPaths` defaults to empty, and empty means no
  file is an owner — so every `shared_preferences` import is reported until the
  option is set. That follows `avoid_hardcoded_color`'s reading of the same
  choice: a default that quietly excused the unconfigured case would let an
  enabled rule report success while doing nothing, which is the one failure a
  linter cannot report about itself. A repository with no preference layer to
  name disables the rule in its area rather than configuring it.

  `clean_arch` is the bundle because that is where the other import-against-
  directory rules already live (`domain_pure_dart_imports`,
  `avoid_layer_violation`, `avoid_tool_imports_in_lib`) — the detection looks up
  a layout, not a Flutter type.

## 0.1.1

- Widen the `analyzer` lower bound to `>=9.0.0` (was `>=10.0.0`).

  `riverpod_generator` skips the 10/11 line entirely — `<=4.0.3` wants
  `analyzer ^9`, `4.0.4-dev.1`+ wants `^12`, `4.0.6`+ wants `^13` — so a `>=10`
  floor made this package uninstallable in any Riverpod app. The floor was never
  this package's own requirement: it came from a comment citing `dart_style`,
  which is not a dependency here, so a consuming app's lockfile number had been
  written down as if it bound the package.

  Verified at 9.0.0: 131 tests, plus an end-to-end run whose resolved-AST rules
  resolved supertype chains and reported correctly.

## 0.1.0

- Initial release. 44 rules in seven bundles (`core`, `flutter`, `clean_arch`,
  `bloc`, `getit`, `log_system`, `novelglide`), selected and parameterised per
  repository through a root `dart_lints.yaml`.
