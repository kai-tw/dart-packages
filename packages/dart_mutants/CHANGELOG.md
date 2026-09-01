## 0.2.3

**A timed-out mutant no longer leaks a runaway test process.** This is the
release to take if you run mutation testing on a machine you also work on.

`flutter test` is three processes, not one: the `flutter` wrapper spawns
`dartaotruntime`, which spawns the `flutter_tester` engine that actually runs
the test. The timeout gate SIGKILLed the direct child, and a signal does not
propagate downward — POSIX reparents an orphan to init rather than killing it.
So the engine survived, went on executing the mutant's infinite loop, and
nothing would ever reap it.

Measured, on the real `flutter test` shape rather than argued from POSIX: one
orphan sat at **1.86 GB at the moment of the kill and 2.25 GB three seconds
later** — roughly 130 MB/s, indefinitely, from a **single** timed-out mutant.
It outlives the run that created it, so the cost accumulates across runs and
does not come back when this binary exits. Two runs exhausted a workstation's
memory, which is how it was found.

The kill now takes the whole process tree. Three details are load-bearing:

- **The tree is snapshotted before anything is killed.** The parent link is
  the only thing connecting the descendants, and killing the root destroys it.
- **They are killed top-down, root first.** Leaves-first was tried and
  measured *worse*: `flutter_tools` is a supervisor, so killing the tester
  while its parent is still alive makes the parent do its job and spawn a
  replacement, which the arriving kill then orphans. The leak survived that
  first attempt, one process smaller — the survivor check below is what caught
  it, on the first real run.
- **Any process that still survives is named on stderr.** A descendant started
  between the snapshot and the kill is missed by construction, and the whole
  point of this release is that such a leak must not be silent. The check
  polls rather than sampling once: a 50 ms sample reported a survivor that was
  in fact already gone, and a warning that cries wolf on every timeout is one
  nobody reads.

**`SIGINT`/`SIGTERM` now kill the in-flight test command too.** Ctrl-C reached
the identical state by a different route — the handler restored files and
called `exit`, leaving the test command it had started running with nobody to
reap it. The signal watch is also armed *before* the baseline run now, which
is the longest single command of a session and was previously outside it.

Both paths are covered against the real CLI binary with real signals, not
simulated. The timeout test carries a deliberate companion assertion that the
fixture genuinely orphans when only the direct child is killed — without it, a
fixture that never spawned a grandchild would pass the real test for the wrong
reason.

Two limits stated rather than hidden: process enumeration is `ps`, so a
platform without it degrades to the old single-process kill and says so on
stderr; and `SIGKILL` to this binary itself still leaks in both directions at
once, because nothing can catch it.

Also documents, in the README, that **`--mutant-timeout` is a memory budget as
well as a time budget**. A mutant that allocates inside its loop allocates for
the whole window, so raising the budget from 30s to 300s to resolve timeouts —
which is the right move for score accuracy — buys that accuracy with peak
memory. Worth knowing before doing it on a machine running other suites.

## 0.2.2

Docs only; no behaviour change.

The 0.2.1 entry below claimed "Measured, on one file, both ends of that" and
then measured one end. The deflating case was real; the inflating one — a
timeout excluded from the denominator raising a score — was reasoning in a
measurement's clothes, in an entry whose whole subject is a defect that hides
by looking measured.

The missing half is now in that entry, from the same consuming PR: a file that
reported PASS 100% at the 30s default with TWO OF ITS THREE mutants timed out,
scoring 1/1 off the one that finished and was killed, and FAIL 33% at 90s once
all three ran. That is the end that ships — nobody questioned the 100%, while
the 71% got reported, which is the asymmetry the entry asserts happening to
the entry itself.

Both ends are now attributed as two files of one PR rather than implied to be
independent runs. The README's output-contract section carries the same
correction, plus the line the second case earns: a percentage computed from
one surviving mutant is not a percentage.

## 0.2.1

`timedOutMutants` — a timed-out mutant is now reported with its identity, not
just counted. Behaviour is unchanged: the timeout fires at the same second,
the mutant is still killed, still scored `timeout`, still excluded from
`total`. Only the report gained something.

The count alone was unactionable, and two consuming sessions hit that in one
day. `timedOut: 1` says something went unmeasured without saying WHICH — so
nobody can see the line, tell whether it is the same mutant every run, or go
and look at it. The failure that motivated it: a file carried a mutant that
timed out on EVERY round, was therefore never scored once, and stayed
invisible behind a number no caller reads per-mutant. Its own file kept
reporting a healthy-looking score.

`FileMutationReport`'s doc used to claim that comparing `timedOut` against
`total` is how that gets caught. That was half true — the comparison finds
THAT, never WHICH — and this list is the other half.

`invalid` deliberately gets no equivalent list, and the asymmetry is the
point: an invalid mutant is not legal code and never needed measuring, while
a timed-out one is real code that went unmeasured. Only the second is a gap.

**A timeout moves the score in EITHER direction, and which one is unknowable
without running the mutant.** It is excluded from the numerator and the
denominator both, so:

- had it been detected, excluding it **lowers** the score;
- had it been undetected, excluding it **raises** it.

Both ends measured, on two different files of one consuming PR:

- **Deflating.** At a 90s budget one file reported FAIL 71% with one timeout;
  at 300s the same file reported FAIL 75% with none, because the mutant
  resolved to *detected* and rejoined the denominator. The reported 71% was an
  under-count of a real 75%.
- **Inflating, and this is the one that ships.** Another file reported
  **PASS 100%** at the 30s default with *two of its three mutants timed out* —
  the single mutant that finished had been killed, so the score was 1/1. At 90s,
  with all three scored, the same file reported FAIL 33%. A gate was passed by
  a file whose tests killed one mutant in three.

That asymmetry is why the defect went unreported for so long: **an under-count
reads as "write more tests" and nobody files it**, while the inflating
direction is the one that silently passes a gate. Same mechanism, and only one
of its two symptoms is uncomfortable enough to chase — which is exactly why the
100%-at-two-timeouts case sat unquestioned and the 71% got reported.

**Raising `--mutant-timeout` is not a substitute for this list.** It works
only when the timeout was a budget problem and disappears — then you can diff
two runs and see which mutant flipped. Against a genuine non-terminating
mutant it tells you nothing at any budget, and that is precisely the case
where knowing which one matters most.

Also fixes a flake in this package's own suite. The integration fixture ran
with a 5s mutant timeout; alone it passed, inside the full suite the BASELINE
run — the cold one, competing with every other test file — exceeded it and
seven tests failed. Raised to 10s. A suite whose job is measuring whether
other suites are trustworthy cannot be the flaky one. Total runtime went DOWN
(52s to 26s): the failures were spending the full timeout before giving up.

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
