## 0.1.0

Initial release. AST-based mutation testing, built to cover exactly what a
regex-based mutator cannot see: the ternary, a switch expression's arms, and
`??` — plus the comparison operators the regex tool gave up on rather than
risk mangling a generic type parameter. Four operators (`ternary_swap`,
`switch_expression_arm_swap`, `null_coalescing_deletion`,
`relational_operator_replacement`), a compile-safety gate that keeps a
mutant that fails to compile from ever being counted as "detected", signal-
safe restore on `SIGINT`/`SIGTERM` (tested against the real CLI binary, not
simulated), a red-baseline pre-flight check, and a JSON output contract of
per-file detected/undetected/invalid counts plus the actual undetected
mutants.

Deliberately out of scope for this release: parallel execution (see the
README's "Known limitations"), and any policy about which files to run
against, budget, or pass/fail thresholds — that stays one layer up.
