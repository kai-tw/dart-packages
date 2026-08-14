import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when a `debug*`-prefixed getter or method is read on an object
/// outside an `assert(...)` block.
///
/// Flutter framework `debug*` APIs (e.g. `debugNeedsPaint`,
/// `debugDoingThisLayout`, `debugDescribeChildren`) are implemented inside
/// `assert(() { ... }())` calls so their bodies only run in debug. In AOT
/// release builds the assert is stripped, the `late` local that holds the
/// result never initializes, and reading the getter throws
/// `LateInitializationError`. Worse, `flutter test` runs JIT with asserts
/// enabled, so unit tests cannot reproduce the crash — every release ships
/// the bug regardless of test coverage.
///
/// **Bad:**
/// ```dart
/// if (boundary.debugNeedsPaint) {
///   return null;
/// }
/// ```
///
/// **Good (debug-only check via `assert`):**
/// ```dart
/// bool needsPaint = false;
/// assert(() {
///   needsPaint = boundary.debugNeedsPaint;
///   return true;
/// }());
/// ```
///
/// **Best (drop the check):**
/// Most call sites that reach for `debugNeedsPaint` are gating an action
/// the framework already gates internally. Drop the read and let the
/// framework's own debug assertion fire if the precondition fails.
class AvoidDebugOnlyApi extends LintRule {
  @override
  String get name => 'avoid_debug_only_api';

  @override
  String get description =>
      'Avoid reading debug-only framework getters/methods outside '
      'assert(...). They throw LateInitializationError in AOT release.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source);
}

class _Visitor extends LintVisitor {
  _Visitor(super.filePath, super.lineInfo, super.source);

  /// Depth counter — incremented on entering an `assert(...)` construct
  /// (statement or constructor initializer), decremented on leaving.
  /// Anything inside is debug-only-evaluated and safe.
  int _assertDepth = 0;

  /// Names matching `debug` followed by an uppercase letter — the
  /// Flutter framework convention for debug-only APIs.
  static final RegExp _debugNamePattern = RegExp(r'^debug[A-Z]');

  @override
  void visitAssertStatement(AssertStatement node) {
    _assertDepth++;
    super.visitAssertStatement(node);
    _assertDepth--;
  }

  @override
  void visitAssertInitializer(AssertInitializer node) {
    _assertDepth++;
    super.visitAssertInitializer(node);
    _assertDepth--;
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    _checkName(node.identifier);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    _checkName(node.propertyName);
    super.visitPropertyAccess(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target != null) {
      _checkName(node.methodName);
    }
    super.visitMethodInvocation(node);
  }

  void _checkName(SimpleIdentifier name) {
    if (_assertDepth > 0) {
      return;
    }
    if (!_debugNamePattern.hasMatch(name.name)) {
      return;
    }
    report(
      ruleName: 'avoid_debug_only_api',
      message:
          '${name.name} is a debug-only framework API; reading it outside '
          'assert(...) throws LateInitializationError in AOT release. '
          'Wrap in assert(() { ... return true; }()) or drop the check.',
      offset: name.offset,
    );
  }
}
