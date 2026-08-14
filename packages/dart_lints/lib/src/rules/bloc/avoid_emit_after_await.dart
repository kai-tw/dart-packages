import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../lint_rule_base.dart';

/// Detects `emit()` calls after `await` expressions in Cubit subclasses
/// without an `isClosed` guard.
///
/// ### Bad
/// ```dart
/// Future<void> load() async {
///   emit(Loading());
///   final data = await fetchData();
///   emit(Loaded(data)); // lint: emit after await without isClosed guard
/// }
/// ```
///
/// ### Good
/// ```dart
/// Future<void> load() async {
///   emit(Loading());
///   final data = await fetchData();
///   if (isClosed) return;
///   emit(Loaded(data));
/// }
/// ```
class AvoidEmitAfterAwait extends ResolvedLintRule {
  AvoidEmitAfterAwait({String? stateHolderBase})
    : stateHolderBase = stateHolderBase ?? 'BlocBase';

  /// The state-holder supertype this rule keys on. Named because which base a
  /// project's state holders extend is the project's choice.
  final String stateHolderBase;

  @override
  String get name => 'avoid_emit_after_await';

  @override
  String get description =>
      'Avoid calling emit() after an await without '
      'checking isClosed first.';

  @override
  ResolvedLintVisitor createResolvedVisitor(
    String filePath,
    ResolvedUnitResult resolvedUnit,
  ) => _Visitor(filePath, resolvedUnit, stateHolderBase);
}

class _Visitor extends ResolvedLintVisitor {
  _Visitor(super.filePath, super.resolvedUnit, this.stateHolderBase);

  final String stateHolderBase;

  bool _inCubitClass = false;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final bool wasCubit = _inCubitClass;
    _inCubitClass = _isCubitSubclass(node);
    super.visitClassDeclaration(node);
    _inCubitClass = wasCubit;
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (!_inCubitClass) {
      return;
    }
    final FunctionBody body = node.body;
    if (body is! BlockFunctionBody || !body.isAsynchronous) {
      return;
    }
    _checkBlock(body.block);
  }

  /// Returns `true` if [node] declares a class that extends `BlocBase`
  /// (the common supertype of `Cubit` and `Bloc`).
  bool _isCubitSubclass(ClassDeclaration node) {
    final List<InterfaceType>? supertypes =
        node.declaredFragment?.element.allSupertypes;
    if (supertypes == null) {
      return false;
    }
    return supertypes.any(
      (InterfaceType t) => t.element.name == stateHolderBase,
    );
  }

  // ── Forward-scanning algorithm ──────────────────────────────

  void _checkBlock(Block block) {
    _checkStatements(block.statements);
  }

  void _checkStatements(List<Statement> statements) {
    bool seenAwait = false;

    for (final Statement statement in statements) {
      // An await in this statement means everything after
      // is in an async gap.
      if (!seenAwait && _containsAwait(statement)) {
        seenAwait = true;
        // The await statement itself may contain an emit
        // before the await expression — that's fine. But
        // we still need to flag emits that are AFTER the
        // await within the same expression. For simplicity,
        // skip checking this statement and start from the
        // next one.
        continue;
      }

      if (!seenAwait) {
        continue;
      }

      // Check for isClosed guard patterns that reset the
      // async gap.
      if (_isClosedGuardWithReturn(statement)) {
        seenAwait = false;
        continue;
      }

      // Check for emit inside a negated isClosed block:
      //   if (!isClosed) { emit(...); }
      if (_isEmitInsideNotClosedBlock(statement)) {
        continue;
      }

      // Report any unguarded emit calls.
      final List<MethodInvocation> emits = _findEmitCalls(statement);
      for (final MethodInvocation emit in emits) {
        if (_isEmitGuardedByIsClosed(emit)) {
          continue;
        }
        report(
          ruleName: 'avoid_emit_after_await',
          message:
              'emit() called after await without '
              'isClosed guard. The Cubit may already '
              'be closed.',
          offset: emit.methodName.offset,
        );
      }
    }
  }

  // ── Helpers ─────────────────────────────────────────────────

  /// Returns `true` if [statement] contains any `await` expression.
  bool _containsAwait(Statement statement) {
    final _AwaitFinder finder = _AwaitFinder();
    statement.accept(finder);
    return finder.found;
  }

  /// Returns `true` if [statement] is an `isClosed` guard that
  /// terminates control flow:
  ///   if (isClosed) return;
  ///   if (isClosed) { return; }
  bool _isClosedGuardWithReturn(Statement statement) {
    if (statement is! IfStatement) {
      return false;
    }
    if (!_isClosedExpression(statement.expression)) {
      return false;
    }
    return _containsReturn(statement.thenStatement);
  }

  /// Returns `true` if [statement] wraps emit inside a `!isClosed`
  /// check:
  ///   if (!isClosed) { emit(...); }
  bool _isEmitInsideNotClosedBlock(Statement statement) {
    if (statement is! IfStatement) {
      return false;
    }
    final Expression condition = statement.expression;
    if (condition is PrefixExpression &&
        condition.operator.lexeme == '!' &&
        _isClosedIdentifier(condition.operand)) {
      return true;
    }
    return false;
  }

  /// Checks if [expr] evaluates to `isClosed`.
  bool _isClosedExpression(Expression expr) {
    if (_isClosedIdentifier(expr)) {
      return true;
    }
    // Handle `!isClosed` used as the condition for a
    // negative guard (e.g. `if (!isClosed) return;` is
    // NOT a guard — it returns when NOT closed).
    return false;
  }

  /// Checks if [expr] is the simple identifier `isClosed`.
  bool _isClosedIdentifier(Expression expr) {
    return expr is SimpleIdentifier && expr.name == 'isClosed';
  }

  /// Returns `true` if [statement] contains a `return`.
  bool _containsReturn(Statement statement) {
    if (statement is ReturnStatement) {
      return true;
    }
    if (statement is Block) {
      return statement.statements.any((Statement s) => s is ReturnStatement);
    }
    return false;
  }

  /// Returns `true` if [emit] is inside a `!isClosed` guard block
  /// anywhere in its ancestor chain (up to the method body).
  bool _isEmitGuardedByIsClosed(MethodInvocation emit) {
    AstNode? current = emit.parent;
    while (current != null && current is! MethodDeclaration) {
      if (current is IfStatement) {
        final Expression condition = current.expression;
        // Check if the emit is in the then-branch of
        // `if (!isClosed) { ... emit ... }`
        if (condition is PrefixExpression &&
            condition.operator.lexeme == '!' &&
            _isClosedIdentifier(condition.operand) &&
            _isDescendant(emit, current.thenStatement)) {
          return true;
        }
      }
      current = current.parent;
    }
    return false;
  }

  /// Returns `true` if [node] is a descendant of [ancestor].
  bool _isDescendant(AstNode node, AstNode ancestor) {
    AstNode? current = node.parent;
    while (current != null) {
      if (identical(current, ancestor)) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }

  /// Finds all `emit(...)` calls in [node].
  List<MethodInvocation> _findEmitCalls(AstNode node) {
    final _EmitFinder finder = _EmitFinder();
    node.accept(finder);
    return finder.emits;
  }
}

/// Visitor that checks whether an AST subtree contains an `await`.
class _AwaitFinder extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitAwaitExpression(AwaitExpression node) {
    found = true;
  }
}

/// Visitor that collects `emit(...)` method invocations.
class _EmitFinder extends RecursiveAstVisitor<void> {
  final List<MethodInvocation> emits = <MethodInvocation>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'emit' && node.target == null) {
      emits.add(node);
    }
    super.visitMethodInvocation(node);
  }
}
