import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// The kind of codebase a project is, for rules whose premise holds for one
/// and not the other.
enum ProjectScope {
  /// An application: nothing is imported from outside, so a top-level
  /// declaration is a global with no compensating benefit.
  app,

  /// A publishable library: top-level declarations are the idiomatic public
  /// surface, and namespacing them into a holder class is a house preference an
  /// adopter has no reason to inherit.
  library,
}

/// Warns when a Dart library declares top-level variables, constants, or
/// functions instead of namespacing them on a class / enum / mixin.
///
/// In an application a top-level identifier is a global symbol: any file may
/// import and use it without declaring a dependency, it leaks across feature
/// boundaries, and related helpers have no obvious owner to grow next to. The
/// fix is to give it an owner: an extension method, a member on the type it
/// operates on, or an enum for a closed set of related constants.
///
/// That premise is an application's. In a publishable library the top-level
/// names *are* the public API, so `scope: library` turns the rule off rather
/// than narrowing it — see [ProjectScope].
///
/// **Interacts with `avoid_static_only_class`.** "Namespace it on a class
/// with a private constructor" is *not* this rule's fix, even though it looks
/// like the obvious one — that class, created solely to hold the orphaned
/// declaration, is exactly the shape `avoid_static_only_class` forbids.
/// Reach for a private-constructor class only as a last resort, when the
/// declaration truly has no owning type, no natural extension target, and no
/// closed set to join — and even then, add it as a static member to a class
/// that already exists for other reasons, not one created just to hold it.
///
/// Exempt (in `app` scope):
/// - A top-level `main` — the language's entry point, wherever the file sits.
///   Exempted by what the declaration is, not by the filename that usually
///   holds it, so a script in `bin/` and a test's `main` are covered too.
/// - Anything named in the `exemptFiles` option — a project's wiring
///   containers and service-locator home.
/// - Generated code (`*.freezed.dart`, `*.g.dart`, `generated/`).
/// - `part of` files (logical extensions of a class in another file).
/// - Type definitions (typedef) — they are types, not values.
///
/// Test files are **not** exempted here even though they need a top-level
/// `main()`: which paths hold tests is something the config already declares as
/// an area, and a second copy of that answer inside the rule could disagree
/// with the first. Disable this rule in the test area instead.
class AvoidTopLevelIdentifiers extends LintRule {
  AvoidTopLevelIdentifiers({
    String? scope,
    List<String>? exemptFiles,
    List<String>? exemptAnnotations,
    List<String>? exemptTypeSuffixes,
  }) : scope = scope == ProjectScope.library.name
           ? ProjectScope.library
           : ProjectScope.app,
       exemptFiles = exemptFiles ?? const <String>[],
       exemptAnnotations = exemptAnnotations ?? const <String>[],
       exemptTypeSuffixes = exemptTypeSuffixes ?? const <String>[];

  final ProjectScope scope;

  /// Files whose top-level declarations are by design — a wiring container, a
  /// service-locator home. Named per project because the file names are.
  final List<String> exemptFiles;

  /// Annotations marking a declaration a framework requires to be top-level.
  ///
  /// A path predicate cannot express this. Riverpod's `@riverpod` providers are
  /// the worked example: the generator only emits for a top-level declaration,
  /// and providers live beside the code they serve rather than in one container
  /// — so they are scattered across dozens of files with nothing in common but
  /// the annotation. Reporting them would tell the author to make a change that
  /// stops their code generating.
  final List<String> exemptAnnotations;

  /// Type-name suffixes marking a top-level variable a framework requires, for
  /// the hand-written counterpart of [exemptAnnotations] (`final x = Provider(…)`).
  final List<String> exemptTypeSuffixes;

  @override
  String get name => 'avoid_top_level_identifiers';

  @override
  String get description =>
      'Avoid top-level variables, constants, and functions. Namespace '
      'them on a class with a private constructor.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => scope == ProjectScope.library
      ? _InertVisitor(filePath, lineInfo, source)
      : _Visitor(
          filePath,
          lineInfo,
          source,
          exemptFiles,
          exemptAnnotations,
          exemptTypeSuffixes,
        );
}

/// Reports nothing. `scope: library` disables the rule outright rather than
/// narrowing it: the rule's premise — a top-level name is a global nobody
/// asked for — is false for a library, where those names *are* the API.
class _InertVisitor extends LintVisitor {
  _InertVisitor(super.filePath, super.lineInfo, super.source);
}

class _Visitor extends LintVisitor {
  _Visitor(
    super.filePath,
    super.lineInfo,
    super.source,
    this.exemptFiles,
    this.exemptAnnotations,
    this.exemptTypeSuffixes,
  );

  final List<String> exemptFiles;
  final List<String> exemptAnnotations;
  final List<String> exemptTypeSuffixes;

  /// Whether a framework requires [member] to stay top-level.
  bool _isFrameworkDeclaration(CompilationUnitMember member) {
    for (final Annotation annotation in member.metadata) {
      if (exemptAnnotations.contains(annotation.name.name)) {
        return true;
      }
    }
    if (member is TopLevelVariableDeclaration &&
        exemptTypeSuffixes.isNotEmpty) {
      final TypeAnnotation? type = member.variables.type;
      if (type is NamedType) {
        final String typeName = type.name.lexeme;
        return exemptTypeSuffixes.any(typeName.endsWith);
      }
    }
    return false;
  }

  bool _isExempt(CompilationUnit unit) {
    if (exemptFiles.any(filePath.endsWith)) {
      return true;
    }
    if (filePath.endsWith('.freezed.dart') ||
        filePath.endsWith('.g.dart') ||
        filePath.contains('/generated/')) {
      return true;
    }
    // No test-path predicate here on purpose. Test files do need a top-level
    // `main()`, but *which paths hold tests* is something the config already
    // declares as an area; a copy of that answer living in the rule is a second
    // definition free to drift from the first, and nothing would catch the
    // disagreement. A project exempts its tests by disabling this rule in its
    // test area.
    //
    // `part of` files cannot host classes alone — exempt.
    for (final Directive d in unit.directives) {
      if (d is PartOfDirective) {
        return true;
      }
    }
    return false;
  }

  @override
  void visitCompilationUnit(CompilationUnit node) {
    if (_isExempt(node)) {
      return;
    }

    for (final CompilationUnitMember member in node.declarations) {
      _reportMember(member);
    }
  }

  void _reportMember(CompilationUnitMember member) {
    if (_isFrameworkDeclaration(member)) {
      return;
    }
    if (member is TopLevelVariableDeclaration) {
      for (final VariableDeclaration v in member.variables.variables) {
        report(
          ruleName: 'avoid_top_level_identifiers',
          message:
              'Top-level ${member.variables.isConst ? 'const' : 'variable'} '
              "'${v.name.lexeme}' has no owner. Give it one: a static "
              'field on the type it relates to, or an enum member for a '
              'closed set.',
          offset: v.name.offset,
        );
      }
    } else if (member is FunctionDeclaration) {
      // `main` is the language's entry point and must be a top-level
      // function, wherever the file sits — an app's `lib/main.dart`, a
      // script in `bin/`, every test file. Reporting it would be advice the
      // author cannot take, so it is exempted by what it IS rather than by
      // the filename that usually holds it.
      if (member.name.lexeme == 'main') {
        return;
      }
      report(
        ruleName: 'avoid_top_level_identifiers',
        message:
            "Top-level function '${member.name.lexeme}' has no owner. "
            'Give it one: an extension method, or a method on the type '
            'it operates on.',
        offset: member.name.offset,
      );
    }
  }
}
