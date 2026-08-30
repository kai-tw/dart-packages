import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../mutation_operator.dart';
import '../mutation_visitor.dart';

/// Replaces a relational operator with a boundary-adjacent one: `<` and
/// `<=`/`>=` swap with each other, `==` and `!=` swap with each other.
///
/// This is exactly what the regex-based mutator this package supersedes
/// deliberately gave up on — its comparison-operator rule scored 2 mutations
/// generated, 0 caught, in this project's own single-construct probe files,
/// and the tool's own operator set never re-added `<`/`<=`/`>`/`>=` for a
/// documented reason: `<` inside `List<int>` is a generic type parameter,
/// not a comparison, and a text pattern cannot tell the two apart without
/// parsing. An AST walk never has this problem — a [BinaryExpression]'s
/// `operator` token IS an operator, by construction; there is no generic
/// bracket to confuse it with.
///
/// Only the boundary-adjacent replacement is offered per operator (`<` gets
/// `<=` and `>=`, not all four of the other relational operators) — this is
/// the standard reduced Relational Operator Replacement set: boundary-off-
/// by-one is the mutation that actually catches real bugs (a loop or range
/// check one element short or long), and the omitted alternatives mostly
/// produce either an equivalent mutant or one so behaviourally distant that
/// almost anything catches it, adding cost without adding signal.
class RelationalOperatorReplacement extends MutationOperator {
  @override
  String get name => 'relational_operator_replacement';

  @override
  String get description =>
      'Replaces a comparison with a boundary-adjacent one: `<` <-> `<=`/`>=`, '
      '`==` <-> `!=`.';

  @override
  MutationVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source);
}

/// Which operators [_Visitor] proposes in place of each relational operator
/// it finds — deliberately not every other member of the family, see the
/// class doc on [RelationalOperatorReplacement].
const Map<String, List<String>> _replacements = <String, List<String>>{
  '<': <String>['<=', '>='],
  '<=': <String>['<', '>'],
  '>': <String>['>=', '<='],
  '>=': <String>['>', '<'],
  '==': <String>['!='],
  '!=': <String>['=='],
};

class _Visitor extends MutationVisitor {
  _Visitor(super.filePath, super.lineInfo, super.source);

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final String original = node.operator.lexeme;
    final List<String>? replacements = _replacements[original];
    if (replacements != null) {
      for (final String replacement in replacements) {
        propose(
          offset: node.operator.offset,
          length: node.operator.length,
          original: original,
          replacement: replacement,
          operatorName: 'relational_operator_replacement',
          description: "'$original' -> '$replacement'",
        );
      }
    }
    super.visitBinaryExpression(node);
  }
}
