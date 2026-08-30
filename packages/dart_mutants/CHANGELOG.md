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
