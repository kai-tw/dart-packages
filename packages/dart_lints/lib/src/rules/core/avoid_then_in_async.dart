import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when `.then()` is called inside an `async` function body.
///
/// In async scope, `await` is clearer and lets try/catch handle errors
/// naturally. `.then()` bypasses this and often leads to unhandled
/// futures.
///
/// **Bad:**
/// ```dart
/// Future<void> load() async {
///   fetchData().then((data) => process(data));
/// }
/// ```
///
/// **Good:**
/// ```dart
/// Future<void> load() async {
///   final data = await fetchData();
///   process(data);
/// }
/// ```
class AvoidThenInAsync extends LintRule {
  @override
  String get name => 'avoid_then_in_async';

  @override
  String get description =>
      'Avoid .then() inside async functions. Use await instead.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source);
}

class _Visitor extends LintVisitor {
  _Visitor(super.filePath, super.lineInfo, super.source);

  bool _inAsync = false;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final bool wasAsync = _inAsync;
    _inAsync = node.body.isAsynchronous;
    super.visitMethodDeclaration(node);
    _inAsync = wasAsync;
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    final bool wasAsync = _inAsync;
    _inAsync = node.body.isAsynchronous;
    super.visitFunctionExpression(node);
    _inAsync = wasAsync;
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_inAsync &&
        node.methodName.name == 'then' &&
        node.target != null &&
        !_isInsideFutureWait(node)) {
      report(
        ruleName: 'avoid_then_in_async',
        message:
            'Avoid .then() in async scope. Use await instead for '
            'clearer control flow and error handling.',
        offset: node.methodName.offset,
      );
    }
    super.visitMethodInvocation(node);
  }

  /// Returns true if [node] appears inside a `Future.wait([ ... ])` list.
  bool _isInsideFutureWait(MethodInvocation node) {
    AstNode? current = node.parent;
    while (current != null) {
      if (current is ListLiteral && _isFutureWaitArgument(current)) {
        return true;
      }
      if (_isFunctionBoundary(current)) {
        break;
      }
      current = current.parent;
    }
    return false;
  }

  /// Returns true if [list] is the argument list of a `Future.wait([ ... ])`
  /// call.
  bool _isFutureWaitArgument(ListLiteral list) {
    if (list.parent is ArgumentList) {
      final AstNode? call = list.parent?.parent;
      if (call is MethodInvocation &&
          call.methodName.name == 'wait' &&
          call.target is SimpleIdentifier &&
          (call.target as SimpleIdentifier).name == 'Future') {
        return true;
      }
    }
    return false;
  }

  /// Whether [node] is a function boundary the upward walk shouldn't cross.
  bool _isFunctionBoundary(AstNode node) =>
      node is FunctionExpression || node is MethodDeclaration;
}
