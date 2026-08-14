import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when code catches `Error` or known `Error` subclasses.
///
/// `Error` and its subclasses signal programming mistakes. They should
/// crash loudly during development, not be caught and logged.
///
/// **Bad:**
/// ```dart
/// try { parse(input); } on Error catch (e) { log(e); }
/// try { cast(value); } on TypeError catch (e) { log(e); }
/// ```
///
/// **Good:**
/// Let `Error` subclasses propagate and crash.
class AvoidCatchingError extends LintRule {
  @override
  String get name => 'avoid_catching_error';

  @override
  String get description =>
      'Avoid catching Error subclasses. '
      'They signal programming mistakes and should crash loudly.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source);
}

class _Visitor extends LintVisitor {
  _Visitor(super.filePath, super.lineInfo, super.source);

  static const Set<String> _errorTypes = <String>{
    'Error',
    'AssertionError',
    'TypeError',
    'StateError',
    'RangeError',
    'ArgumentError',
    'ConcurrentModificationError',
    'CyclicInitializationError',
    'FallThroughError',
    'NoSuchMethodError',
    'OutOfMemoryError',
    'StackOverflowError',
    'UnimplementedError',
    'UnsupportedError',
  };

  @override
  void visitCatchClause(CatchClause node) {
    final TypeAnnotation? exceptionType = node.exceptionType;
    if (exceptionType is NamedType &&
        _errorTypes.contains(exceptionType.name.lexeme)) {
      report(
        ruleName: 'avoid_catching_error',
        message:
            'Avoid catching ${exceptionType.name.lexeme}. '
            'Error subclasses signal programming mistakes '
            'and should crash loudly.',
        offset: exceptionType.name.charOffset,
      );
    }
    super.visitCatchClause(node);
  }
}
