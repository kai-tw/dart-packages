import 'lint_rule_base.dart';

/// The rules in force for one area, split by the pass that runs them.
class BuiltRules {
  const BuiltRules({
    required this.syntax,
    required this.resolved,
    required this.project,
  });

  final List<LintRule> syntax;
  final List<ResolvedLintRule> resolved;
  final List<ProjectLintRule> project;
}
