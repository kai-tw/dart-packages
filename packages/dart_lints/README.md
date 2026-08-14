# dart_lints

Custom Dart lint rules, configured per repository.

Every rule lives in this package. A project decides — in one YAML file — which
areas of its tree exist, which rules govern each, and what those rules should be
told about its conventions. Adding or removing a rule in a project is a line of
configuration, not a change here.

```bash
dart run dart_lints                    # every area declared in dart_lints.yaml
dart run dart_lints --area=test        # one area
dart run dart_lints lib --fix          # a path, applying auto-fixes
dart run dart_lints --skip-analyze     # custom rules only
```

## Configuration

`dart_lints.yaml`, at the repository root. Every glob resolves relative to that
file's directory.

```yaml
analyzer:
  command: dart            # dart | flutter | none
  args: [--fatal-infos]    # see "Why args is its own key" below
  paths: []                # empty = the areas' paths

exclude:
  - "**/*.freezed.dart"
  - "**/*.g.dart"

# Dart files that belong to no area. Anything else uncovered is an error.
coverageIgnore: []

bundles: [core, flutter, clean_arch, bloc, getit, log_system]
enable: []                 # individual rules outside the enabled bundles

areas:
  production:
    paths: ["lib/**"]
  test:
    paths: ["test/**", "integration_test/**"]
    disable: [avoid_record_types]
    # enable / options / analyzer may also be overridden per area

options:
  avoid_layer_violation:
    featureRoots: [lib/features, lib/modules]
    layers: [domain, data, presentation]
```

### Bundles

A bundle names **the framework family a rule's detection looks up** — not the
concern it enforces. That is what lets one rule set serve an application and a
pure-Dart library without either inheriting the other's assumptions.

| Bundle | Rules | Looks up |
|---|---|---|
| `core` | 16 | nothing but Dart |
| `flutter` | 8 | Flutter / Material types |
| `clean_arch` | 5 | a layered directory layout |
| `bloc` | 6 | `Cubit` / `BlocBase` |
| `getit` | 2 | a service locator |
| `log_system` | 2 | the `log_system` package |
| `novelglide` | 5 | one specific application — **do not enable elsewhere** |

A Riverpod project enables neither `bloc` nor `getit`: those rules resolve types
it does not have, so they are dead weight rather than silent gaps.

### Validation fails closed

A configuration fault stops the run with exit 2 before anything is analyzed.
There is no warning level, because a mistyped rule name that merely warned would
leave the rule disabled while the run still reported success — the one failure a
linter cannot detect about itself.

Checked: every rule, bundle and area name against the registry; every option key
against the rule that accepts it; every option value against the type that key
declares; and **every Dart file against the areas** — a file that no area claims
and `coverageIgnore` does not list is an error, not a silent skip.

That last check is per **file**, not per directory. A directory-level check
passes on `packages/*/lib/**` while `packages/x/bin/main.dart` matches nothing
and goes unlinted, which is exactly the shape that escapes notice.

Files git ignores are not scanned. In-repo worktrees are common enough that the
naive walk finds thousands of checked-out copies no area could sensibly claim —
on one repository, 5535 Dart files versus 2217 real ones.

### Why `args` is its own key

Linter diagnostics are INFO severity. Without `--fatal-infos`, `dart analyze`
prints every lint and still exits 0 — the rules become decoration. Keeping the
flags separate from the command is what stops that guarantee disappearing when a
project's analyzer step is edited.

`paths` is separate for the mirror-image reason: a project may want its custom
rules over a directory whose stock-analyzer errors it has not triaged yet, and
collapsing the two keys would force it to choose.

## The analyzer version pin

`analyzer: ">=10.0.0 <11.0.0"`. **Three independent constraints hold it there.**
Lifting one does not lift the pin:

1. **This package.** analyzer 12.0.0 removed `ClassDeclaration.name` and
   `.members`, which several rules use directly.
2. **A consuming app's codegen stack.** `build`, `freezed`, `json_serializable`,
   `source_gen` and `build_runner` all declare `analyzer <11.0.0`.
3. **`dart_style` 3.1.7** declares `analyzer >=10.0.0 <12.0.0`.

The rules that use the removed APIs have tests, so lifting the pin fails loudly
rather than silently changing behaviour.

One consequence worth knowing: a pinned older analyzer cannot parse syntax added
later. Rather than skip such a file quietly, the runner lists every file it could
not resolve and exits non-zero — an unlinted file otherwise reports no violations
and reads exactly like a clean one.

## Developing a rule

Local iteration does not need a tag:

```yaml
dev_dependencies:
  dart_lints:
    git: { url: …/dart-packages.git, path: packages/dart_lints, ref: dart_lints-v0.1.0 }

dependency_overrides:
  dart_lints: { path: ../dart-packages/packages/dart_lints }
```

Verified working: pub accepts a path override onto a workspace member from
outside that workspace. Drop the override and bump `ref` when the change lands.

Run `dart format` after `--fix`; save your open files first, since fixes are
written from the buffer the offsets were computed against.

## Adopting it

**Order matters when a repository already has a lint package.** Coverage
validation is fail-closed and per file, so an old `packages/<x>_lints/` still on
disk is dozens of Dart files that the new configuration does not claim — placing
`dart_lints.yaml` before deleting the old package fails immediately. Delete
first, or give the old tree a transitional area.

**Expect the violation count to rise, and read it carefully.** Rules whose scope
was hardcoded now take it from configuration, which usually means they cover
more than before. On one repository `avoid_hardcoded_color` went from 14 to 25 —
and 25 was exactly the number its own design documentation had recorded as
outstanding debt. Those 11 were never examined by the rule; they are not a
regression the migration introduced. Separate the two before triaging:

- **New coverage** — code this rule never looked at. Real findings.
- **Behaviour change** — the same code judged differently. Rare, and worth
  understanding before fixing.

**Some exemptions are the configuration's job, not the rule's.** Rules no longer
carry their own "is this a test file?" predicates: a second definition of that,
living beside the one a project already declares as an area, is free to drift
with nothing to catch the disagreement. Disable a rule in the area where it does
not apply.

Prefer disabling for a reason you can state. An exemption that exists because a
tool cannot express something is a different kind of debt from one that exists
because you decided — and only the second stays true a year later.
