import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when an async function returns `void` instead of `Future<void>`.
///
/// `async` functions that return `void` swallow errors silently. Return
/// `Future<void>` so callers can handle errors properly.
///
/// **Bad:**
/// ```dart
/// void run(String input) async {
///   await _service.run(input);
/// }
/// ```
///
/// **Good:**
/// ```dart
/// Future<void> run(String input) async {
///   await _service.run(input);
/// }
/// ```
class AvoidVoidAsync extends LintRule {
  @override
  String get name => 'avoid_void_async';

  @override
  String get description =>
      'Avoid async functions that return void. '
      'Use Future<void> instead.';

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
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _check(node.functionExpression, node.returnType, node.name.offset);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _check(node.body, node.returnType, node.name.offset);
    super.visitMethodDeclaration(node);
  }

  void _check(
    AstNode bodyOrExpression,
    TypeAnnotation? returnType,
    int nameOffset,
  ) {
    final bool isAsync = switch (bodyOrExpression) {
      FunctionExpression(:final FunctionBody body) => body.isAsynchronous,
      final FunctionBody body => body.isAsynchronous,
      _ => false,
    };

    if (!isAsync) {
      return;
    }

    if (returnType == null) {
      return;
    }

    // Check if the return type is literally `void`.
    if (returnType is NamedType && returnType.name.lexeme == 'void') {
      report(
        ruleName: 'avoid_void_async',
        message:
            'Async function returns void — errors will be silently '
            'swallowed. Use Future<void> instead.',
        offset: returnType.name.charOffset,
        fix: LintFix(
          description: 'Replace void with Future<void>',
          edits: <SourceEdit>[
            SourceEdit(
              offset: returnType.offset,
              length: returnType.length,
              replacement: 'Future<void>',
            ),
          ],
        ),
      );
    }
  }
}
