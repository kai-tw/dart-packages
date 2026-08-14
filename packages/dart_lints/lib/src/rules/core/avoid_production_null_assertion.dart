import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when a value is returned with a `!` null-assertion applied
/// (`return x!;` or `=> x!`).
///
/// A `!` crashes as a raw `TypeError`, outside whatever exception hierarchy
/// and redaction a project routes its failures through. Returning one is the
/// worst shape: the
/// non-null guarantee is *asserted rather than proven* — usually borrowed
/// from a third-party contract that drifts across plugin versions — and the
/// crash fires at the callee's line carrying no domain context for the
/// caller that relied on it. An explicit guard is loud, graceful, and
/// project-scoped, so it strictly dominates `!`.
///
/// Two ways to prove instead of assert — pick by whether `null` is a legal
/// outcome for this function:
///
/// 1. **Hoist to a local** when the function already returns a nullable and
///    `null` is a legitimate path. Flow analysis promotes the local, so the
///    `!` simply disappears — this also collapses the double read of a
///    third-party property.
/// 2. **Throw a domain exception from an if-null guard** when `null` means
///    the contract broke. Raise it even when the branch is provably
///    unreachable today: defence-in-depth against contract drift, and it is
///    fine for the branch to stay unreachable and untestable.
///
/// **Bad:**
/// ```dart
/// Bitmap? findCover() {
///   if (document.coverImage != null) {
///     return document.coverImage!;
///   }
///   return searchManifest();
/// }
/// ```
///
/// **Good — form 1, the value is legitimately optional:**
/// ```dart
/// Bitmap? findCover() {
///   final Bitmap? cover = document.coverImage;
///   if (cover != null) {
///     return cover;
///   }
///   return searchManifest();
/// }
/// ```
///
/// **Good — form 2, `null` means the contract broke:**
/// ```dart
/// Map<String, String> getAuthHeaders() {
///   final Map<String, String>? header = _plugin.authHeaders;
///   if (header == null) {
///     throw const AuthHeaderUnavailableException();
///   }
///   return header;
/// }
/// ```
class AvoidProductionNullAssertion extends LintRule {
  @override
  String get name => 'avoid_production_null_assertion';

  @override
  String get description =>
      'Avoid returning a null-asserted value. Hoist it to a local so flow '
      'analysis promotes it, or throw a domain exception from an if-null '
      'guard.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source);
}

// Which files this rule applies to is the config's answer, not the rule's: a
// project declares its test paths once as an area and disables the rule there.
// The predicate that used to live here was a second, silent definition of "test
// file" that could disagree with the first.
class _Visitor extends LintVisitor {
  _Visitor(super.filePath, super.lineInfo, super.source);

  @override
  void visitReturnStatement(ReturnStatement node) {
    _reportIfNullAsserted(node.expression);
    super.visitReturnStatement(node);
  }

  @override
  void visitExpressionFunctionBody(ExpressionFunctionBody node) {
    _reportIfNullAsserted(node.expression);
    super.visitExpressionFunctionBody(node);
  }

  void _reportIfNullAsserted(Expression? expression) {
    // Shape guard: PostfixExpression also covers `++` / `--`.
    if (expression is! PostfixExpression || expression.operator.lexeme != '!') {
      return;
    }

    report(
      ruleName: 'avoid_production_null_assertion',
      message:
          'Avoid returning a null-asserted value. Hoist it to a local so '
          'flow analysis promotes it, or throw a domain exception from an '
          'if-null guard.',
      offset: expression.operator.offset,
    );
  }
}
