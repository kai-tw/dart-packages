import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when code throws a generic `Exception(...)` directly.
///
/// Always throw a domain-specific exception class instead.
///
/// **Bad:**
/// ```dart
/// throw Exception('Page not found.');
/// ```
///
/// **Good:**
/// ```dart
/// throw RecordNotFoundException(pageIdentifier: id);
/// ```
class AvoidThrowingGenericException extends LintRule {
  @override
  String get name => 'avoid_throwing_generic_exception';

  @override
  String get description =>
      'Avoid throwing a generic Exception. '
      'Throw a domain-specific exception instead.';

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
  void visitThrowExpression(ThrowExpression node) {
    final Expression expression = node.expression;

    // `Exception('msg')` without `new` is parsed as a MethodInvocation.
    if (expression is MethodInvocation &&
        expression.target == null &&
        expression.methodName.name == 'Exception') {
      report(
        ruleName: 'avoid_throwing_generic_exception',
        message:
            'Avoid throwing a generic Exception. '
            'Throw a domain-specific exception instead.',
        offset: expression.methodName.offset,
      );
    }

    // `new Exception('msg')` is parsed as InstanceCreationExpression.
    if (expression is InstanceCreationExpression) {
      final NamedType type = expression.constructorName.type;
      if (type.name.lexeme == 'Exception' && type.importPrefix == null) {
        report(
          ruleName: 'avoid_throwing_generic_exception',
          message:
              'Avoid throwing a generic Exception. '
              'Throw a domain-specific exception instead.',
          offset: type.name.charOffset,
        );
      }
    }

    super.visitThrowExpression(node);
  }
}
