import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Inside a catch clause, `LogSystem.warning` / `.error` / `.fatal`
/// must be called with both `error:` and `stackTrace:` named
/// arguments. The catch already has the exception and the trace —
/// dropping them on the floor turns a diagnosable event into
/// "something happened, somewhere." `info` is exempt: it is the
/// documented shape for expected, non-exceptional conditions.
///
/// **Bad:**
/// ```dart
/// } on FileSystemException catch (e) {
///   LogSystem.warning('Read failed: $e');  // missing stackTrace
/// }
/// ```
///
/// **Good:**
/// ```dart
/// } on FileSystemException catch (e, s) {
///   LogSystem.warning('Read failed', error: e, stackTrace: s);
/// }
/// ```
class LogErrorRequiresStacktrace extends LintRule {
  LogErrorRequiresStacktrace({String? logger, List<String>? levels})
    : logger = logger ?? 'LogSystem',
      levels = levels ?? const <String>['warning', 'error', 'fatal'];

  /// The logging facade's type name.
  final String logger;

  /// Levels that report a fault and therefore need the stack trace. A level
  /// used for expected conditions is deliberately absent.
  final List<String> levels;

  @override
  String get name => 'log_error_requires_stacktrace';

  @override
  String get description =>
      '$logger calls at ${levels.join(" / ")} inside a catch clause must '
      'include both error: and stackTrace: named arguments.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source, logger, levels);
}

class _Visitor extends LintVisitor {
  _Visitor(
    super.filePath,
    super.lineInfo,
    super.source,
    this.logger,
    this.levels,
  );

  final String logger;
  final List<String> levels;

  int _catchDepth = 0;

  @override
  void visitCatchClause(CatchClause node) {
    _catchDepth++;
    super.visitCatchClause(node);
    _catchDepth--;
  }

  // Treat nested function bodies as a new scope — a `LogSystem.error`
  // inside a stream listener defined within a catch is not "directly"
  // in the catch body and the catch's `e, s` may not even be the
  // intended attribution.
  @override
  void visitFunctionExpression(FunctionExpression node) {
    final int saved = _catchDepth;
    _catchDepth = 0;
    super.visitFunctionExpression(node);
    _catchDepth = saved;
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final int saved = _catchDepth;
    _catchDepth = 0;
    super.visitMethodDeclaration(node);
    _catchDepth = saved;
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_catchDepth > 0 && _isAttributedLog(node)) {
      final bool hasError = _hasNamedArg(node, 'error');
      final bool hasStackTrace = _hasNamedArg(node, 'stackTrace');
      if (!hasError || !hasStackTrace) {
        final List<String> missing = <String>[
          if (!hasError) 'error:',
          if (!hasStackTrace) 'stackTrace:',
        ];
        report(
          ruleName: 'log_error_requires_stacktrace',
          message:
              '$logger.${node.methodName.name} inside a catch clause '
              'must include ${missing.join(' and ')}.',
          offset: node.methodName.offset,
        );
      }
    }
    super.visitMethodInvocation(node);
  }

  bool _isAttributedLog(MethodInvocation node) {
    final Expression? target = node.target;
    if (target is! SimpleIdentifier || target.name != logger) {
      return false;
    }
    return levels.contains(node.methodName.name);
  }

  bool _hasNamedArg(MethodInvocation node, String name) {
    for (final Expression arg in node.argumentList.arguments) {
      if (arg is NamedExpression && arg.name.label.name == name) {
        return true;
      }
    }
    return false;
  }
}
