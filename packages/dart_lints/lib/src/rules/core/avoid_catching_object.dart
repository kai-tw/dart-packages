import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when code catches the root `Object` type.
///
/// `on Object catch (...)` collapses every possible failure into one
/// arm — environmental conditions (the kind catch is for) AND
/// programming bugs (the kind that must propagate to the zone error
/// handler so Crashlytics surfaces them). The catch-Object pattern
/// silently swallows the bug class and reduces every unexpected
/// failure to a generic `unknown` result, hiding real defects.
///
/// Enumerate the concrete environmental exceptions each `try` body
/// can actually throw. Let `Error` subclasses (and anything else not
/// listed) propagate.
///
/// **Bad:**
/// ```dart
/// try {
///   await operation();
/// } on Object catch (e, s) {
///   LogSystem.error('Unexpected', error: e, stackTrace: s);
///   return OperationResult.unknown;
/// }
/// ```
///
/// **Good:**
/// ```dart
/// try {
///   await operation();
/// } on FileSystemException catch (e, s) {
///   LogSystem.warning('Disk failure', error: e, stackTrace: s);
///   return OperationResult.diskError;
/// } on NetworkException catch (e, s) {
///   LogSystem.warning('Network failure', error: e, stackTrace: s);
///   return OperationResult.networkError;
/// }
/// // Programming bugs propagate to the zone handler.
/// ```
class AvoidCatchingObject extends LintRule {
  @override
  String get name => 'avoid_catching_object';

  @override
  String get description =>
      'Avoid catching the root Object type. '
      'Enumerate concrete environmental exceptions; let program '
      'bugs propagate to the zone error handler.';

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
    if (exceptionType is NamedType && exceptionType.name.lexeme == 'Object') {
      report(
        ruleName: 'avoid_catching_object',
        message:
            'Avoid catching the root Object type. '
            'Enumerate concrete environmental exceptions; let program '
            'bugs propagate to the zone error handler.',
        offset: exceptionType.name.charOffset,
      );
    }
    super.visitCatchClause(node);
  }
}
