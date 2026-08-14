import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when a catch clause has an empty body.
///
/// An empty catch block silently swallows failures. Always log at minimum.
///
/// **Bad:**
/// ```dart
/// try { await service.run(); } on ServiceException catch (_) {}
/// ```
///
/// **Good:**
/// ```dart
/// try { await service.run(); } on ServiceException catch (e, s) {
///   LogSystem.error('Service failed', error: e, stackTrace: s);
/// }
/// ```
class AvoidEmptyCatch extends LintRule {
  @override
  String get name => 'avoid_empty_catch';

  @override
  String get description => 'Avoid empty catch blocks. Always log at minimum.';

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
    if (node.body.statements.isEmpty) {
      report(
        ruleName: 'avoid_empty_catch',
        message:
            'Empty catch block silently swallows failures. '
            'Always log at minimum.',
        offset: node.catchKeyword?.charOffset ?? node.offset,
      );
    }
    super.visitCatchClause(node);
  }
}
