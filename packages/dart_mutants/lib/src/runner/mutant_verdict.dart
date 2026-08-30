/// What happened when one [Mutant] was run.
enum MutantVerdict {
  /// The compile-safety gate rejected it before the test command ever saw
  /// it. Excluded from both the numerator and denominator of a score — an
  /// invalid mutant is not evidence of anything, in either direction.
  invalid,

  /// The test command exited non-zero against a mutant that compiled: some
  /// test noticed. Counts toward the denominator and is good news.
  detected,

  /// The test command exited zero against a mutant that compiled: nothing
  /// noticed. Counts toward the denominator and is the number a mutation
  /// score exists to surface — some of these are real gaps, some are
  /// equivalent mutants no test suite could ever kill, and telling the two
  /// apart is a judgment call for whoever reads the report, not this tool.
  undetected,
}
