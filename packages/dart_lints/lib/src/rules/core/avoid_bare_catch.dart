import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when a catch clause has no `on ExceptionType` specifier.
///
/// A bare `catch (e)` intercepts everything — including framework and
/// platform errors that should crash loudly.
///
/// **Bad:**
/// ```dart
/// try { await fetch(); } catch (e) { print(e); }
/// ```
///
/// **Good:**
/// ```dart
/// try { await fetch(); } on NetworkException catch (e, s) {
///   LogSystem.error('Fetch failed', error: e, stackTrace: s);
/// }
/// ```
class AvoidBareCatch extends LintRule {
  @override
  String get name => 'avoid_bare_catch';

  @override
  String get description =>
      'Avoid bare catch clauses without an on-type specifier. '
      'Always catch specific exception types.';

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
    if (node.exceptionType == null) {
      report(
        ruleName: 'avoid_bare_catch',
        message:
            'Bare catch clause without an on-type specifier. '
            'Always use on ExceptionType catch (e, s).',
        offset: node.catchKeyword?.charOffset ?? node.offset,
      );
    }
    super.visitCatchClause(node);
  }
}
