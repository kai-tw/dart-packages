import 'lint_rule_base.dart';
import 'violation_reporter.dart';

/// The outcome of one run: what to report, and what never got looked at.
class LintRunResult {
  const LintRunResult({
    required this.violations,
    required this.unresolvedPaths,
    required this.fixedCount,
    required this.analyzerIssues,
  });

  final List<LintViolation> violations;

  /// Files the analyzer could not resolve — see [ViolationReporter.reportUnresolved].
  final List<String> unresolvedPaths;

  final int fixedCount;
  final int analyzerIssues;

  bool get isClean =>
      violations.isEmpty && unresolvedPaths.isEmpty && analyzerIssues == 0;
}
