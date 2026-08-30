# dart_mutants

AST-based mutation testing for Dart and Flutter.

A regex-based mutator can only see text patterns, which means it is blind to
whatever it cannot tell apart from something else — a ternary's `?`/`:` also
appear in null-aware access and named-parameter syntax, `??` is two
characters that mean nothing on their own, and `<` inside `List<int>` is a
generic bracket, not a comparison. This package walks the real analyzer AST
instead, so it mutates exactly the node it means to and nothing it does not.

```bash
dart run dart_mutants \
  --test-command "flutter test test/foo_test.dart" \
  lib/foo.dart lib/bar.dart
```

```bash
dart run dart_mutants --json --test-command "dart test" lib/foo.dart
```

## What it mutates

- **`ternary_swap`** — `a ? b : c` -> `a ? c : b`.
- **`switch_expression_arm_swap`** — one arm's result replaced with an
  adjacent arm's, patterns and guards untouched.
- **`null_coalescing_deletion`** — `a ?? b` -> `a` alone and, separately,
  `b` alone.
- **`relational_operator_replacement`** — `<`/`<=`/`>`/`>=`/`==`/`!=`
  replaced with a boundary-adjacent operator (not the full family — see the
  class doc on `RelationalOperatorReplacement` for why).

`&&`/`||` are deliberately not reimplemented here — a regex-based mutator
already covers them adequately; this package exists for the constructs one
cannot.

## The compile-safety gate

An AST-legal edit is not a type-legal one. A mutant that fails to compile
still makes the test command exit non-zero, which — read naively — counts
as "detected": a broken mutant would make the score go *up*, not down, for
a file the mutation never actually ran against. Every mutant is checked
against the project's own analyzer before it is ever handed to the test
command; one that fails compiles is `invalid` and excluded from both the
numerator and denominator of the score, not counted as caught.

## What this package does not decide

Which files to run against, how big a mutant budget to spend, what
detection rate is acceptable, and what a surviving mutant's write-up should
look like are policy — that lives one layer up, in whatever calls this. The
contract here is a file list and a test command in, per-file
detected/undetected/invalid counts and the actual undetected mutants out.

## Known limitations

- **Sequential, not parallel.** Runtime is mutant count times one test run.
  Scoping to covered lines and running one file's mutants at a time in
  parallel are both real options for a project that needs it, deliberately
  not attempted here yet — a mutant applied to a shared file while another
  mutant's test run is in flight is a correctness risk this package has not
  solved, and a wrong number is worse than a slow one.
- **`SIGKILL` cannot be caught.** `SIGINT`/`SIGTERM` restore whatever is
  mutated before the process exits (this is tested against the real CLI
  binary, not simulated); no process can catch `SIGKILL`, so a `kill -9` or
  a timeout wrapper configured to skip straight to it is still a real gap.
- **Command splitting is whitespace-only.** `--test-command`/
  `--analyze-command` are split on whitespace; an argument that itself needs
  a literal space is not supported yet.
