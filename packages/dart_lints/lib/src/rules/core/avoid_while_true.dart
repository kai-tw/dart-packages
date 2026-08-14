import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when code uses `while (true)`.
///
/// Always use a bounded loop with a maximum iteration count.
///
/// **Bad:**
/// ```dart
/// while (true) {
///   final response = await callModel(trajectory);
///   if (response.stopReason == 'end_turn') return response.text;
/// }
/// ```
///
/// **Good:**
/// ```dart
/// for (int step = 0; step < maxSteps; step++) {
///   final response = await callModel(trajectory);
///   // ...
/// }
/// throw AgentMaxStepsException('Exceeded maxSteps.');
/// ```
class AvoidWhileTrue extends LintRule {
  @override
  String get name => 'avoid_while_true';

  @override
  String get description =>
      'Avoid while (true). '
      'Use a bounded loop with a maximum iteration count.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source);
}

class _Visitor extends LintVisitor {
  _Visitor(super.filePath, super.lineInfo, super.source);

  @override
  void visitWhileStatement(WhileStatement node) {
    final Expression condition = node.condition;
    if (condition is BooleanLiteral && condition.value) {
      report(
        ruleName: 'avoid_while_true',
        message:
            'Avoid while (true). '
            'Use a bounded loop with a maximum iteration count.',
        offset: node.whileKeyword.charOffset,
      );
    }
    super.visitWhileStatement(node);
  }
}
