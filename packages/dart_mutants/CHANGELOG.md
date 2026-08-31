## 0.2.0

Four new operators, closing the half of the mutation space the initial
release deliberately left to a tool that no longer runs: `statement_deletion`
(one statement replaced with an empty `;`), `condition_negation`
(`if (x)` -> `if (!(x))`, skipping conditions `relational_operator_replacement`
already covers), `logical_operator_replacement` (`&&` <-> `||`), and
`arithmetic_operator_replacement` (`+` <-> `-`, `*` <-> `/`).

The first four operators all ask "is this expression's branch or boundary
pinned?" — they presume a line runs and probe which way it went. None of them
asks whether a line's effect is asserted at all, so a guard like
`if (mounted) { setState(...) }` — no ternary, no `??`, no comparison —
produced zero mutants and reported a clean score for code nothing measured.
Measured one construct per file under 0.1.0: an `if` guard, `&&`/`||`, plain
statements, and `n - 1` each produced ZERO.

This is not a change of mind about scope. 0.1.0 was scoped to complement a
regex-based mutator running alongside it, which is why the README said
`&&`/`||` were "deliberately not reimplemented". That mutator was then
*replaced* by this package rather than joined by it (`plan-mutation`'s own
script records both the replacement and the removal of its flags), so the
coverage it contributed left with it. The scope never changed; the
arrangement it was scoped against did.

**Expect existing scores to drop.** These operators generate mutants current
suites do not kill, so a file's percentage will fall — that is the first
honest measurement of it, not a regression. A caller gating on a per-file
threshold should expect to revisit that threshold, or stage the rollout.

The output contract gains a fourth guarantee: **a path comes back exactly as
it was passed in**, echoed rather than normalised. This was always the
behaviour and was never written down, so a caller had to infer it — and one
inferred it wrong, keying its report lookup on absolute paths against a run
that had passed relative ones, which matched nothing. `files` is keyed by
that path, so the form has to match; it is now documented and covered by a
CLI test asserting both directions.

Two integration fixtures were rewritten rather than having their expected
counts raised: they exist to isolate one mutant each so the gate-mechanics
assertions stay sharp, and bumping counts would make them churn on every
future operator. `test/operators_test.dart` is a new regression guard
asserting that each previously-blind construct is now reachable by some
operator.

## 0.1.0

Initial release. AST-based mutation testing, built to cover exactly what a
regex-based mutator cannot see: the ternary, a switch expression's arms, and
`??` — plus the comparison operators the regex tool gave up on rather than
risk mangling a generic type parameter. Four operators (`ternary_swap`,
`switch_expression_arm_swap`, `null_coalescing_deletion`,
`relational_operator_replacement`), a compile-safety gate that keeps a
mutant that fails to compile from ever being counted as "detected", a
`--mutant-timeout` gate that keeps a hung mutant from being counted as
"detected" either (or from hanging the whole run — `package:test`'s own
timeout cannot preempt a synchronous infinite loop, so this package kills
the subprocess itself), signal-safe restore on `SIGINT`/`SIGTERM` (tested
against the real CLI binary with a real signal, not simulated), a
red-baseline pre-flight check, and a JSON output contract of per-file
detected/undetected/invalid/timeout counts plus the actual undetected
mutants — guaranteed to print in full even when the exit code is non-zero,
and to include a file with zero candidate mutants rather than omit it.
Every one of those output-contract guarantees is covered by a test against
the real CLI binary, following review from the peer session this package
was commissioned by.

Deliberately out of scope for this release: parallel execution (see the
README's "Known limitations"), and any policy about which files to run
against, budget, or pass/fail thresholds — that stays one layer up.
