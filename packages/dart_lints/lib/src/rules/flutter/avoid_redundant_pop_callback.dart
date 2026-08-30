import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when `BackButton` / `CloseButton` is constructed with an
/// `onPressed:` callback that only calls `context.pop()` (or the
/// equivalent `Navigator.maybePop(context)`).
///
/// Both widgets already invoke `Navigator.maybePop(context)` when
/// `onPressed` is null, and go_router intercepts that via the Navigator
/// integration — so the explicit callback is redundant and prevents
/// `const` construction.
///
/// **Bad:**
/// ```dart
/// BackButton(onPressed: () => context.pop())
/// ```
///
/// **Good:**
/// ```dart
/// const BackButton()
/// ```
class AvoidRedundantPopCallback extends LintRule {
  AvoidRedundantPopCallback({List<String>? popExpressions})
    : popExpressions =
          popExpressions ?? const <String>['context.pop', 'Navigator.maybePop'];

  /// Calls that pop the current route, as 'target.method'. A project on a
  /// different router names its own.
  final List<String> popExpressions;

  @override
  String get name => 'avoid_redundant_pop_callback';

  @override
  String get description =>
      'Avoid passing onPressed: () => context.pop() to BackButton / '
      'CloseButton — the default already pops.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source, popExpressions);
}

class _Visitor extends LintVisitor {
  _Visitor(super.filePath, super.lineInfo, super.source, this.popExpressions);

  final List<String> popExpressions;

  /// Whether [call] is one of the configured pop expressions.
  bool _isConfiguredPop(Expression? call) {
    if (call is! MethodInvocation) {
      return false;
    }
    final Expression? target = call.target;
    if (target is! SimpleIdentifier) {
      return false;
    }
    return popExpressions.contains('${target.name}.${call.methodName.name}');
  }

  static const Set<String> _autoPopWidgets = <String>{
    'BackButton',
    'CloseButton',
  };

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final String className = node.constructorName.type.name.lexeme;
    if (!_autoPopWidgets.contains(className)) {
      super.visitInstanceCreationExpression(node);
      return;
    }
    final NamedExpression? onPressed = _findNamedArg(node, 'onPressed');
    if (onPressed == null || !_isJustPop(onPressed.expression)) {
      super.visitInstanceCreationExpression(node);
      return;
    }
    report(
      ruleName: 'avoid_redundant_pop_callback',
      message:
          '$className already pops on tap. Remove the redundant onPressed '
          '— the widget can then be const.',
      offset: onPressed.offset,
      fix: _buildFix(node, onPressed),
    );
    super.visitInstanceCreationExpression(node);
  }

  NamedExpression? _findNamedArg(InstanceCreationExpression node, String name) {
    for (final Expression arg in node.argumentList.arguments) {
      if (arg is NamedExpression && arg.name.label.name == name) {
        return arg;
      }
    }
    return null;
  }

  /// Returns true when [expr] is a lambda whose body is exactly one call
  /// to `context.pop()` or `Navigator.maybePop(context)`.
  bool _isJustPop(Expression expr) {
    if (expr is! FunctionExpression) {
      return false;
    }
    final FunctionBody body = expr.body;
    Expression? call;
    if (body is ExpressionFunctionBody) {
      call = body.expression;
    } else if (body is BlockFunctionBody) {
      final List<Statement> stmts = body.block.statements;
      if (stmts.length != 1) {
        return false;
      }
      final Statement stmt = stmts.first;
      if (stmt is! ExpressionStatement) {
        return false;
      }
      call = stmt.expression;
    } else {
      return false;
    }
    return _isConfiguredPop(call);
  }

  LintFix _buildFix(InstanceCreationExpression node, NamedExpression arg) {
    final int removalEnd = _computeRemovalEnd(arg);
    final List<SourceEdit> edits = <SourceEdit>[
      SourceEdit(
        offset: arg.offset,
        length: removalEnd - arg.offset,
        replacement: '',
      ),
    ];

    _addConstEditIfOnlyArg(node, edits);

    return LintFix(description: 'Remove redundant onPressed', edits: edits);
  }

  /// Returns the offset up to which source should be removed for [arg].
  int _computeRemovalEnd(NamedExpression arg) {
    final Token endToken = arg.endToken;
    final Token? next = endToken.next;
    int removalEnd = arg.end;
    if (next != null && next.lexeme == ',') {
      removalEnd = next.end;
      // Consume one trailing whitespace char so the next argument
      // doesn't end up flush against the previous one.
      if (removalEnd < source.length && source[removalEnd] == ' ') {
        removalEnd++;
      }
    }
    return removalEnd;
  }

  /// If onPressed was the *only* argument, the result is argless and can
  /// be const-constructed. Prepend `const ` (or replace an existing `new`
  /// keyword) so `prefer_const_constructors` doesn't immediately re-fire
  /// on the auto-fix output.
  void _addConstEditIfOnlyArg(
    InstanceCreationExpression node,
    List<SourceEdit> edits,
  ) {
    final bool onlyArg = node.argumentList.arguments.length == 1;
    if (onlyArg && node.keyword == null) {
      edits.add(
        SourceEdit(
          offset: node.constructorName.offset,
          length: 0,
          replacement: 'const ',
        ),
      );
    } else if (onlyArg && node.keyword?.lexeme == 'new') {
      final Token kw = node.keyword!;
      edits.add(
        SourceEdit(offset: kw.offset, length: kw.length, replacement: 'const'),
      );
    }
  }
}
