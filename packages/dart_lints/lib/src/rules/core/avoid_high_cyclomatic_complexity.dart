import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when a function, method, or constructor's cyclomatic complexity
/// exceeds [maxComplexity].
///
/// Cyclomatic complexity (McCabe, 1976) counts the independent paths through
/// a unit of code: start at 1 for the unit itself, add 1 for every branch
/// point. It is the structural half of Savoia & Evans's CRAP metric
/// (`CC² × (1 − cov)³ + CC`) — at 100% coverage the coverage term vanishes
/// and CRAP degenerates to plain CC, which is exactly the number this rule
/// computes. The other half, per-function coverage, needs a coverage format
/// this rule does not consume; that stays a separate concern until a
/// coverage strategy is chosen. A high number here does not by itself mean
/// untested code, but it does mean an expensive one to test completely: each
/// added path is one more a test suite has to actually exercise, not just
/// import.
///
/// **Branch points counted**, each worth 1: `if` (statement or collection
/// element), `for` (statement or collection element, C-style or `for-in`),
/// `while`, `do-while`, `catch` (each clause on a `try`), a `switch` `case`
/// with a value or pattern, `&&`, `||`, `??`, the `?:` ternary, and a
/// null-aware access (`?.` / `?[]`). A pattern-match guard (`case ... when
/// ...`) — on an `if`, a `switch` case, or a `switch` expression arm — adds
/// one more on top of the case or `if` it guards, since the guard is a
/// second condition gating the same branch. A `switch` statement's `default`
/// and a `switch` expression's wildcard (`_ =>`) arm are not counted: unlike
/// every case before them, they test nothing new, the same reasoning that
/// excludes an `if` with no `else` from needing a phantom second branch.
///
/// **`??` has one exemption: `field ?? this.field`.** When both sides are a
/// bare name or one level of property access — no call, no further
/// chaining — it does not count. This is `copyWith`'s entire body for a
/// data class: N fields, N copies of the exact same idiom, and unlike N
/// genuinely different conditions, those branches are not independent
/// evidence a test suite has to earn one at a time. One call with every
/// field provided covers every site's "use the new value" side at once;
/// one bare `copyWith()` covers every site's "keep the old value" side at
/// once — the branches are perfectly correlated because they are the same
/// idiom repeated, not N different behaviours, and there is no extract-
/// method split available either (moving `field ?? this.field` into its
/// own one-line helper per field relocates the same total count, it does
/// not reduce it). The moment either side is a call or two levels deep
/// (`title.hashCode`, `this.title.abs()`), this is no longer "keep the
/// field unchanged" — it goes back to counting normally. A `T? Function()?`
/// "thunk" used to distinguish "not provided" from "explicitly cleared"
/// (`field != null ? field() : this.field`) is a ternary, not a `??`, and
/// this exemption never touches it — that third state is real, field-
/// specific behaviour a plain `??` cannot even express, so it keeps its own
/// branch point same as before.
///
/// **Each function, method, constructor, and closure is its own unit.** A
/// closure passed to `.map` or a `builder:` callback is not folded into its
/// enclosing method's count — Dart's heavy use of inline closures (widget
/// builders especially) means doing that would let the actual complexity
/// hide behind a method that reads as simple, and would also let a method
/// duck the rule entirely by moving its branching into an argument. A local
/// function or a closure nested inside another one is, in turn, not folded
/// into *its* enclosing unit — every function-shaped node reports for
/// itself, independently, at its own location.
///
/// **[maxComplexity] has no default — it is a required option.** The
/// threshold is a judgment call: Uncle Bob's own numbers (4 for a human
/// review, 6 relaxed for a generated function) assume the coverage term is
/// actually zero, i.e. 100% coverage, which a Flutter UI layer often cannot
/// reach. A single number for a whole project bakes in one answer to that
/// tension; `dart_lints.yaml`'s per-`areas` `optionOverrides` already lets
/// `domain/` and `presentation/` carry different values without any change
/// to this rule, so the deliberate choice here is to force that decision
/// into config rather than pick a number this rule ships opinions about.
///
/// **Bad — five independent paths hiding behind one method:**
/// ```dart
/// String describe(User? user) {
///   if (user == null) return 'unknown';
///   final String name = user.nickname ?? user.legalName ?? 'anonymous';
///   return user.isVerified && user.age >= 18 ? '$name (adult)' : name;
/// }
/// ```
///
/// **Good — the branching splits along its own seams:**
/// ```dart
/// String describe(User? user) {
///   if (user == null) return 'unknown';
///   return _label(user);
/// }
///
/// String _label(User user) {
///   final String name = user.nickname ?? user.legalName ?? 'anonymous';
///   return user.isVerified && user.age >= 18 ? '$name (adult)' : name;
/// }
/// ```
class AvoidHighCyclomaticComplexity extends LintRule {
  AvoidHighCyclomaticComplexity({required this.maxComplexity});

  /// The highest complexity a unit may have without being reported. Not
  /// optional — see the class doc for why this rule ships no default.
  final int maxComplexity;

  @override
  String get name => 'avoid_high_cyclomatic_complexity';

  @override
  String get description =>
      "Avoid a function whose cyclomatic complexity exceeds the project's "
      'configured max — each independent path through it is one more a '
      'test suite has to actually exercise.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source, maxComplexity);
}

class _Visitor extends LintVisitor {
  _Visitor(super.filePath, super.lineInfo, super.source, this.maxComplexity);

  final int maxComplexity;

  /// The nearest enclosing named unit, for labelling a closure's report —
  /// `null` at the top level, where a closure has no better description.
  String? _enclosingLabel;

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _measure(
      node.functionExpression.body,
      "'${node.name.lexeme}'",
      node.name.offset,
    );
    final String? outer = _enclosingLabel;
    _enclosingLabel = node.name.lexeme;
    super.visitFunctionDeclaration(node);
    _enclosingLabel = outer;
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _measure(node.body, "'${node.name.lexeme}'", node.name.offset);
    final String? outer = _enclosingLabel;
    _enclosingLabel = node.name.lexeme;
    super.visitMethodDeclaration(node);
    _enclosingLabel = outer;
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final String label = _constructorLabel(node);
    _measure(node.body, "'$label'", _constructorOffset(node));
    final String? outer = _enclosingLabel;
    _enclosingLabel = label;
    super.visitConstructorDeclaration(node);
    _enclosingLabel = outer;
  }

  /// `C` for an unnamed constructor, `C.named` for a named one.
  ///
  /// Reads `returnType`, not the newer `typeName` — `ConstructorDeclaration`
  /// only grew `typeName` in a later analyzer release, and this package's own
  /// `pubspec.yaml` still supports analyzer 9. `returnType` is deprecated in
  /// favor of `typeName` on the versions that have both, but it is the only
  /// name that resolves across the whole supported range, and it is
  /// non-nullable on every version — this rule already found this exact
  /// method too complex once; do not reintroduce a null-fallback chain here
  /// to "modernize" it without checking the floor of the range again.
  String _constructorLabel(ConstructorDeclaration node) {
    final String? ctorName = node.name?.lexeme;
    final String typeName = node.returnType.name;
    return ctorName == null ? typeName : '$typeName.$ctorName';
  }

  /// The constructor's own name token when present, else its return-type
  /// identifier — an unnamed constructor still has to anchor its report
  /// somewhere.
  int _constructorOffset(ConstructorDeclaration node) =>
      node.name?.offset ?? node.returnType.offset;

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // The wrapper FunctionExpression every FunctionDeclaration carries is
    // already measured via visitFunctionDeclaration above — only a genuine
    // closure literal is its own unit here.
    if (node.parent is! FunctionDeclaration) {
      final String label = _enclosingLabel == null
          ? 'this closure'
          : "the closure in '$_enclosingLabel'";
      _measure(node.body, label, node.offset);
    }
    super.visitFunctionExpression(node);
  }

  void _measure(FunctionBody body, String label, int offset) {
    if (body is EmptyFunctionBody) {
      return;
    }
    final _ComplexityCounter counter = _ComplexityCounter();
    body.accept(counter);
    if (counter.complexity > maxComplexity) {
      report(
        ruleName: 'avoid_high_cyclomatic_complexity',
        message:
            '$label has cyclomatic complexity ${counter.complexity}, over '
            'the configured max of $maxComplexity. Each independent path '
            'needs its own test — split it, or extract a piece with its '
            'own name and its own tests.',
        offset: offset,
      );
    }
  }
}

/// Counts branch points in one function body, stopping at any nested
/// function-shaped node — those are separate units, measured on their own by
/// the outer [_Visitor], and must not be double-counted here.
class _ComplexityCounter extends RecursiveAstVisitor<void> {
  int complexity = 1;

  static const Set<String> _branchingOperators = <String>{'&&', '||'};

  void _guard(GuardedPattern guardedPattern) {
    if (guardedPattern.whenClause != null) {
      complexity++;
    }
  }

  @override
  void visitIfStatement(IfStatement node) {
    complexity++;
    final CaseClause? caseClause = node.caseClause;
    if (caseClause != null) {
      _guard(caseClause.guardedPattern);
    }
    super.visitIfStatement(node);
  }

  @override
  void visitIfElement(IfElement node) {
    complexity++;
    final CaseClause? caseClause = node.caseClause;
    if (caseClause != null) {
      _guard(caseClause.guardedPattern);
    }
    super.visitIfElement(node);
  }

  @override
  void visitForStatement(ForStatement node) {
    complexity++;
    super.visitForStatement(node);
  }

  @override
  void visitForElement(ForElement node) {
    complexity++;
    super.visitForElement(node);
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    complexity++;
    super.visitWhileStatement(node);
  }

  @override
  void visitDoStatement(DoStatement node) {
    complexity++;
    super.visitDoStatement(node);
  }

  @override
  void visitCatchClause(CatchClause node) {
    complexity++;
    super.visitCatchClause(node);
  }

  @override
  void visitSwitchCase(SwitchCase node) {
    complexity++;
    super.visitSwitchCase(node);
  }

  @override
  void visitSwitchPatternCase(SwitchPatternCase node) {
    complexity++;
    _guard(node.guardedPattern);
    super.visitSwitchPatternCase(node);
  }

  @override
  void visitSwitchExpressionCase(SwitchExpressionCase node) {
    if (node.guardedPattern.pattern is! WildcardPattern) {
      complexity++;
    }
    _guard(node.guardedPattern);
    super.visitSwitchExpressionCase(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final String operator = node.operator.lexeme;
    if (operator == '??') {
      if (!_isSimpleAccess(node.leftOperand) ||
          !_isSimpleAccess(node.rightOperand)) {
        complexity++;
      }
    } else if (_branchingOperators.contains(operator)) {
      complexity++;
    }
    super.visitBinaryExpression(node);
  }

  /// A bare name (`title`), `this`, or one level of property access off
  /// either (`this.title`, `other.title`) — no call, no further chaining.
  ///
  /// This is `??`'s one exemption: `field ?? this.field`, repeated once per
  /// field, is `copyWith`'s entire body for a data class with N fields —
  /// and unlike N genuinely different conditions, these branches are not
  /// independent evidence a test suite has to earn one at a time. A test
  /// that passes every field covers every site's "use the new value" side
  /// at once; a bare `copyWith()` covers every site's "keep the old value"
  /// side at once — the branches are perfectly correlated because they are
  /// the same idiom repeated, not N different behaviours. `this.title` (a
  /// bare field) and `title.hashCode` or `this.title.abs()` (a call, or two
  /// levels deep) are different claims — the moment a call or a second
  /// level of chaining appears, this is no longer "keep the field
  /// unchanged," so it goes back to counting normally.
  bool _isSimpleAccess(Expression e) {
    if (e is SimpleIdentifier || e is ThisExpression) {
      return true;
    }
    if (e is PrefixedIdentifier) {
      return _isBareReference(e.prefix);
    }
    if (e is PropertyAccess && e.target != null) {
      return _isBareReference(e.target!);
    }
    return false;
  }

  bool _isBareReference(Expression e) => e is SimpleIdentifier || e is ThisExpression;

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    complexity++;
    super.visitConditionalExpression(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (node.isNullAware) {
      complexity++;
    }
    super.visitPropertyAccess(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.isNullAware) {
      complexity++;
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitIndexExpression(IndexExpression node) {
    if (node.isNullAware) {
      complexity++;
    }
    super.visitIndexExpression(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    // A local function is its own unit — do not descend.
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // A closure literal is its own unit — do not descend.
  }
}
