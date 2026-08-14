import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when code catches the base `Exception` type directly.
///
/// Catching `Exception` is too broad — catch specific subclasses instead.
class AvoidCatchingBaseException extends LintRule {
  @override
  String get name => 'avoid_catching_base_exception';

  @override
  String get description =>
      'Avoid catching the base Exception type. '
      'Catch specific exception subclasses instead.';

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
  void visitCatchClause(CatchClause node) {
    final TypeAnnotation? exceptionType = node.exceptionType;
    if (exceptionType is NamedType &&
        exceptionType.name.lexeme == 'Exception') {
      report(
        ruleName: 'avoid_catching_base_exception',
        message:
            'Avoid catching the base Exception type. '
            'Catch specific exception subclasses instead.',
        offset: exceptionType.name.charOffset,
      );
    }
    super.visitCatchClause(node);
  }
}
