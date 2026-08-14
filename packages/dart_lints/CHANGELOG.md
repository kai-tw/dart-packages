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
