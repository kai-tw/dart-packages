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

The operators fall into two groups that ask different questions, and a pool
holding only one group has a blind half rather than a smaller sample.

**"Is this expression's branch or boundary pinned?"** — these presume the
line runs and probe which way it went:

- **`ternary_swap`** — `a ? b : c` -> `a ? c : b`.
- **`switch_expression_arm_swap`** — one arm's result replaced with an
  adjacent arm's, patterns and guards untouched.
- **`null_coalescing_deletion`** — `a ?? b` -> `a` alone and, separately,
  `b` alone.
- **`relational_operator_replacement`** — `<`/`<=`/`>`/`>=`/`==`/`!=`
  replaced with a boundary-adjacent operator (not the full family — see the
  class doc on `RelationalOperatorReplacement` for why).
- **`logical_operator_replacement`** — `&&` <-> `||`.
- **`arithmetic_operator_replacement`** — `+` <-> `-`, `*` <-> `/`.

**"Does any test assert this line's effect happened at all?"** — these ask
the prior question, and are the only ones that reach code containing no
operator to mutate:

- **`statement_deletion`** — one statement replaced with an empty `;`.
- **`condition_negation`** — `if (x)` -> `if (!(x))`, for `if`/`while`/
  `do-while` and collection-`if`. Skipped when the condition is already a
  comparison, which `relational_operator_replacement` covers better.

A guard like `if (mounted) { setState(...) }` contains no ternary, no `??`
and no comparison, so only the second group reaches it at all. Without those,
a file's whole conditional structure can go unmeasured while the score reads
clean.

## The compile-safety gate

An AST-legal edit is not a type-legal one. A mutant that fails to compile
still makes the test command exit non-zero, which — read naively — counts
as "detected": a broken mutant would make the score go *up*, not down, for
a file the mutation never actually ran against. Every mutant is checked
against the project's own analyzer before it is ever handed to the test
command; one that fails compiles is `invalid` and excluded from both the
numerator and denominator of the score, not counted as caught.

## The timeout gate

A mutant can turn a normal loop into an infinite one — sometimes the most
real signal a mutation testing tool can produce. But `package:test`'s own
per-test timeout is cooperative, built on the event loop, and cannot
preempt a synchronous `while (true) {}` that never yields to it; this
package's own subprocess would then wait on the test command forever. Every
mutant's test run is bounded by `--mutant-timeout` (default 30s, applied to
the baseline check too) and killed with `SIGKILL` — which cannot be
ignored — if it does not finish in time. A timed-out mutant is scored
`timeout`, not `detected`: a hang is not the same evidence as an assertion
actually catching the wrong output, and counting it as caught would inflate
the score the same way an uncompilable mutant would.

## What this package does not decide

Which files to run against, how big a mutant budget to spend, what
detection rate is acceptable, and what a surviving mutant's write-up should
look like are policy — that lives one layer up, in whatever calls this. The
contract here is a file list and a test command in, per-file
detected/undetected/invalid/timeout counts and the actual undetected
mutants out.

## The output contract

These four are guaranteed, not incidental — a caller with its own
pass/fail policy (a per-file threshold other than "zero undetected", for
instance) depends on all four, and each is covered by a test against the
real CLI binary, not just the internal report types:

- **`--json` always prints a complete report to stdout, even when the exit
  code is non-zero** — an aborted run, or any file with undetected mutants.
  Nothing about this binary's own exit-code opinion suppresses the report a
  caller needs to read to form its own.
- **A file with zero candidate mutants still appears in `files`**, at
  `total: 0`. "This file had no mutants" and "this file was never passed
  in" are different facts; only the JSON, not the exit code or the absence
  of a key, can tell a caller which one happened.
- **`invalid` and `timeout` stay in the per-file output**, not folded into
  `total` or summed away. A file where most candidates ended up `invalid`
  or `timeout` has a hollow-looking 100% the same way a file with only one
  real mutant does — comparing either against `total` is how a policy layer
  catches that, so both are reported, not just counted internally.
- **A path comes back exactly as it was passed in.** Paths are echoed, never
  normalised — pass `lib/foo.dart` and the report says `lib/foo.dart`; pass
  it absolute and the report says it absolute. This matters more than it
  looks, because `files` is *keyed* by that path: a caller checking that
  every file it asked for came back has to compare the same form it sent, and
  one that assumes either form will silently match nothing. Echoing is the
  only behaviour that lets a caller use its own paths as lookup keys without
  this package deciding what a path should look like.

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
- **Equivalent mutants are not detected.** `statement_deletion` can delete a
  statement that provably changes nothing — a trailing bare `return;` in a
  void function is the common one. Recognising those needs flow analysis this
  package does not do, so they surface as survivors for a person to dismiss
  rather than being filtered out on a guess. A caller gating on a percentage
  should expect a small floor of these.
- **A green baseline is not proof that tests ran.** The pre-flight check
  confirms the test command exits 0 against unmodified code. It cannot
  confirm the command actually *executed* anything — that would mean parsing
  one specific runner's output, and this package deliberately accepts any
  `--test-command`. The case is contained rather than prevented: a baseline
  that runs nothing makes every mutant undetected, so the file scores 0% and
  this binary exits 1. Wrong for the wrong reason, but it stops rather than
  waving through. Reaching it takes a custom wrapper command, since `dart
  test` (exit 79) and `flutter test` both refuse loudly on no tests.
  A caller that wants this *named* rather than merely blocked should treat
  "zero detected across every file" as ambiguous between "the suite asserts
  nothing" and "the suite never ran". Those are indistinguishable from this
  report, and this package does not guess between them.
- **No per-project operator selection.** `defaultOperators()` is a flat list;
  every operator runs on every file. A caller wanting to stage the deletion
  and negation operators in gradually would be the reason to build a config
  layer, which does not exist yet.
