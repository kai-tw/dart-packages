import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../mutation_operator.dart';
import '../mutation_visitor.dart';

/// Swaps `&&` and `||`.
///
/// A compound condition is where two separate requirements get collapsed into
/// one line, and it is exactly where a suite tends to test the happy path and
/// nothing else: if every test that reaches `if (isReady && hasData)` supplies
/// both, then `||` behaves identically for all of them and nothing goes red.
/// The mutant is the question "is the second requirement actually required,
/// or does no test ever distinguish it?"
///
/// This is one of the operators the regex-based mutator handled adequately,
/// and this package deliberately did not reimplement while that tool still
/// ran alongside. It no longer does — the AST engine replaced it outright
/// rather than joining it — so the coverage it used to contribute went away
/// with it, and the two operators here that duplicated nothing became the
/// only ones running. Reimplementing it is not a change of mind about scope;
/// it is the same scope applied to a set-up that changed underneath it.
///
/// Both operands of `&&` and `||` are already `bool` by the language's own
/// rule, so unlike most operator replacements this one is guaranteed to
/// type-check. Every mutant it proposes reaches the test command.
class LogicalOperatorReplacement extends MutationOperator {
  @override
  String get name => 'logical_operator_replacement';

  @override
  String get description => 'Swaps `&&` and `||`.';

  @override
  MutationVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source);
}

const Map<String, String> _replacements = <String, String>{
  '&&': '||',
  '||': '&&',
};

class _Visitor extends MutationVisitor {
  _Visitor(super.filePath, super.lineInfo, super.source);

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final String original = node.operator.lexeme;
    final String? replacement = _replacements[original];
    if (replacement != null) {
      propose(
        offset: node.operator.offset,
        length: node.operator.length,
        original: original,
        replacement: replacement,
        operatorName: 'logical_operator_replacement',
        description: "'$original' -> '$replacement'",
      );
    }
    super.visitBinaryExpression(node);
  }
}
