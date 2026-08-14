import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Requires every reference to a `package:novel_glide_design_mockups` sketch in
/// production `lib/` code to sit behind an `if (DesignMockup.enabled)` guard,
/// and requires that package to be imported with a prefix.
///
/// Design-mockup sketches are dev-preview-only widgets. A reference guarded by
/// `if (DesignMockup.enabled)` (a compile-time `const false` in release) is
/// tree-shaken out, so the sketch never ships. An UNGUARDED reference is
/// referenced unconditionally → not tree-shaken → the sketch ships to users.
/// This rule makes the guard mandatory, not a convention.
///
/// Detection is purely syntactic (no resolved AST, so no analyzer-version
/// fragility): the package must be imported with a prefix
/// (`import 'package:novel_glide_design_mockups/…' as designMockups;`), and any
/// `<prefix>.` reference must be lexically inside the THEN branch of an
/// `if (DesignMockup.enabled)` — both the statement form (`IfStatement`) and the
/// collection-if form (`IfElement`, the canonical insertion). References in the
/// `else` branch, under `if (!DesignMockup.enabled)`, or guarded by a different
/// condition are NOT guarded and are flagged.
///
/// **Bad** (unguarded — ships in release):
/// ```dart
/// import 'package:novel_glide_design_mockups/…' as m;
/// SliverToBoxAdapter(child: const m.ConflictNoticeSketch()),
/// ```
///
/// **Good:**
/// ```dart
/// if (DesignMockup.enabled)
///   SliverToBoxAdapter(child: const m.ConflictNoticeSketch()),
/// ```
class NovelglideRequireDesignMockupGuard extends LintRule {
  @override
  String get name => 'novelglide_require_design_mockup_guard';

  @override
  String get description =>
      'design-mockup sketches must be imported with a prefix and referenced '
      'only inside an if (DesignMockup.enabled) guard, or they ship in release.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source);
}

const String _packageUriPrefix = 'package:novel_glide_design_mockups';
const String _guardClass = 'DesignMockup';
const String _guardMember = 'enabled';

class _Visitor extends LintVisitor {
  _Visitor(super.filePath, super.lineInfo, super.source);

  /// The prefix the design_mockups package was imported under in this file
  /// (null until/unless the import is seen). Imports precede usages in the AST,
  /// so this is set before any reference is visited.
  String? _mockupPrefix;

  /// > 0 while visiting the THEN branch of an `if (DesignMockup.enabled)`
  /// (statement or collection-if). References to the mockup prefix here are safe.
  int _guardDepth = 0;

  /// Root-app `lib/` only — the design_mockups package itself and `test/` are
  /// out of scope (the package isn't lint-scanned by the Stop hook; tests are
  /// not shipped).
  bool get _isAppLib {
    if (filePath.contains('packages/')) {
      return false;
    }
    if (filePath.endsWith('_test.dart') ||
        filePath.startsWith('test/') ||
        filePath.contains('/test/')) {
      return false;
    }
    return filePath.startsWith('lib/') || filePath.contains('/lib/');
  }

  @override
  void visitImportDirective(ImportDirective node) {
    // Capture the design_mockups import prefix; require one so usages are
    // syntactically trackable.
    if (_isAppLib) {
      final String? uri = node.uri.stringValue;
      if (uri != null && uri.startsWith(_packageUriPrefix)) {
        final SimpleIdentifier? prefix = node.prefix;
        if (prefix == null) {
          report(
            ruleName: 'novelglide_require_design_mockup_guard',
            message:
                "Import design-mockup sketches with a prefix (import '$uri' as "
                'designMockups;) so the guard rule can track their usages.',
            offset: node.uri.offset,
          );
        } else {
          _mockupPrefix = prefix.name;
        }
      }
    }
    super.visitImportDirective(node);
  }

  /// Whether [condition] is exactly the bare `DesignMockup.enabled`.
  bool _isGuardCondition(Expression condition) {
    if (condition is PrefixedIdentifier) {
      return condition.prefix.name == _guardClass &&
          condition.identifier.name == _guardMember;
    }
    if (condition is PropertyAccess) {
      final Expression? target = condition.target;
      return target is SimpleIdentifier &&
          target.name == _guardClass &&
          condition.propertyName.name == _guardMember;
    }
    return false;
  }

  @override
  void visitIfStatement(IfStatement node) {
    // Manual dispatch so only the THEN branch of the guard counts as guarded.
    node.expression.accept(this);
    final bool guarded = _isGuardCondition(node.expression);
    if (guarded) {
      _guardDepth++;
      node.thenStatement.accept(this);
      _guardDepth--;
    } else {
      node.thenStatement.accept(this);
    }
    node.elseStatement?.accept(this);
  }

  @override
  void visitIfElement(IfElement node) {
    node.expression.accept(this);
    final bool guarded = _isGuardCondition(node.expression);
    if (guarded) {
      _guardDepth++;
      node.thenElement.accept(this);
      _guardDepth--;
    } else {
      node.thenElement.accept(this);
    }
    node.elseElement?.accept(this);
  }

  @override
  void visitNamedType(NamedType node) {
    _flagIfMockupPrefix(node.importPrefix?.name.lexeme, node.offset);
    super.visitNamedType(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    _flagIfMockupPrefix(node.prefix.name, node.offset);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final Expression? target = node.target;
    if (target is SimpleIdentifier) {
      _flagIfMockupPrefix(target.name, node.offset);
    }
    super.visitMethodInvocation(node);
  }

  void _flagIfMockupPrefix(String? prefixName, int offset) {
    if (_mockupPrefix == null || prefixName != _mockupPrefix) {
      return;
    }
    if (_guardDepth > 0) {
      return;
    }
    report(
      ruleName: 'novelglide_require_design_mockup_guard',
      message:
          'design-mockup sketch ($_mockupPrefix.*) referenced outside an '
          'if ($_guardClass.$_guardMember) guard; it would not tree-shake and '
          'would ship in release. Wrap the reference in if ($_guardClass.$_guardMember).',
      offset: offset,
    );
  }
}
