## 0.3.0

- New `avoid_multi_document_dartdoc` in the `core` bundle: flags a dartdoc
  block (a run of consecutive `///` lines) that contains a markdown heading
  (`##` or deeper).

  A heading inside a dartdoc is the author's own admission that the block
  carries more than one document. The fix is not to shorten it — it is to
  split each section onto the declaration it actually constrains: a class's
  contract stays on the class, one method's behavior goes on that method, a
  field's reason for existing goes on the field, and — for a method with
  several independent optional parameters — Dart supports a doc comment on
  each individual parameter, which IDE signature help then surfaces exactly
  at the call site.

  This is a narrow, high-precision smoke detector, not a length check. A
  length threshold was tried first (measured against NovelGlide's `lib/`:
  4494 comment blocks, 22870 lines) and rejected — some genuinely
  single-purpose contracts run long by nature, and a length rule cannot tell
  those apart from a real multi-document block. The heading signal is far
  rarer (17 of the 4494 blocks, all true positives on inspection) but much
  more deliberate: an author reaches for `##` specifically to separate
  sections. Lower recall, high precision.

  Enabling `core` in a project already running it turns this on immediately,
  with no separate opt-in — this repo's own `log_system` package had three
  hits once the rule went live here, all real: `LogSystem`'s class doc and
  `init`'s doc each had a `##`-headed section explaining one specific
  concern, and `LoggableException`'s class doc had one explaining a single
  field. All three are split onto the declaration they actually describe in
  this same release, so the rule ships with this repo already clean under it.

## 0.2.1

- `avoid_catching_abstract_exception` gains a `sanctionedBases` option: abstract
  exception types this configuration accepts, by name.

  Some libraries export only the abstract base and keep the concrete subclass in
  an unexported `src/` — `sqflite`'s `DatabaseException` is one — which leaves a
  consumer nothing narrower to name. Until now the only way through was to
  disable the rule for the file, which also excused every other abstract catch
  in it. Naming the type instead keeps the rest of the file governed.

  Pair it with an area whose paths name the one boundary that needs it. Set
  globally it excuses the type across the whole tree, which is a much weaker
  claim than "this file has no alternative":

  ```yaml
  areas:
    database_boundary:
      paths: ["lib/core/database/app_database.dart"]
      options:
        avoid_catching_abstract_exception:
          sanctionedBases: [DatabaseException]
  ```

  The rule also gains its first tests, covering the option and the two things
  it must not do: sanctioning one base leaves its siblings reported, and a
  typo in the list changes nothing in either direction.

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
