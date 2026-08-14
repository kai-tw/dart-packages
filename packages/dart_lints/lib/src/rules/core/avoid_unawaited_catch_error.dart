import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Forbids the `unawaited(<expr>.catchError(...))` shape.
///
/// `unawaited(...)` says "I do not await this future." `.catchError(...)`
/// says "any error in this future is swallowed by my handler." Combining
/// the two produces a fire-and-forget swallowed-error path:
///
/// - Errors never propagate to the zone error handler, so Crashlytics
///   does not ingest them as faults — a wrong / silent handler removes
///   the only signal a real bug ever existed.
/// - The pattern is hard to test: nothing observes the future's
///   resolution, so the error branch is not visible to the caller's
///   `await` / `expect`, only via stubbing the inner side-effect.
/// - It hides true→false transition / cold-open / single-shot bugs
///   inside the handler closure (see the F-1 mirror-clear regression
///   that motivated this rule).
///
/// **Bad:**
/// ```dart
/// unawaited(
///   _service.doThing().catchError((Object e, StackTrace s) {
///     LogSystem.error('thing failed', error: e, stackTrace: s);
///   }),
/// );
/// ```
///
/// **Good — wrap in an async helper with `try / await`:**
/// ```dart
/// Future<void> _doThingLogging() async {
///   try {
///     await _service.doThing();
///   } on FileSystemException catch (e, s) {
///     LogSystem.error('thing failed', error: e, stackTrace: s);
///   }
/// }
///
/// // Call site:
/// unawaited(_doThingLogging());
/// ```
///
/// The helper makes the error path testable (mock the dependency,
/// drive the throw, verify the log) and lets the rest of the code stay
/// fire-and-forget at the call site. Catching a concrete exception type rather
/// than `Object` keeps a program bug propagating instead of being logged as an
/// expected condition.
///
/// **Good — drop the swallow when no recovery is needed:**
/// ```dart
/// unawaited(_service.doThing());
/// ```
/// Uncaught errors then reach the zone handler / Crashlytics, where a
/// real bug should surface.
class AvoidUnawaitedCatchError extends LintRule {
  @override
  String get name => 'avoid_unawaited_catch_error';

  @override
  String get description =>
      'Avoid unawaited(...catchError(...)). Use a try/catch async '
      'helper or drop the catchError so errors reach the zone handler.';

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
  void visitMethodInvocation(MethodInvocation node) {
    // Match `unawaited(<single positional arg>)`.
    if (node.methodName.name == 'unawaited' &&
        node.argumentList.arguments.length == 1) {
      final Expression arg = _unwrapParens(node.argumentList.arguments.single);
      // The wrapped expression must itself be a `<receiver>.catchError(...)`
      // method invocation. We only flag the **outermost** call shape —
      // chains like `unawaited(foo.catchError(...).then(...))` (outer
      // is `.then`) are a different smell and not in scope.
      if (arg is MethodInvocation && arg.methodName.name == 'catchError') {
        report(
          ruleName: 'avoid_unawaited_catch_error',
          message:
              'Avoid unawaited(...catchError(...)). The combination '
              'silently swallows fire-and-forget errors and hides bugs '
              'from the zone error handler. Extract the future into an '
              'async helper with try/await, or drop the .catchError so '
              'uncaught errors reach Crashlytics.',
          offset: arg.methodName.offset,
        );
      }
    }
    super.visitMethodInvocation(node);
  }

  Expression _unwrapParens(Expression expr) {
    Expression current = expr;
    while (current is ParenthesizedExpression) {
      current = current.expression;
    }
    return current;
  }
}
