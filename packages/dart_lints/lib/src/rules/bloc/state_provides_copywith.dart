import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../lint_rule_base.dart';

/// Requires a **multi-field** single-class state to declare `copyWith`.
///
/// State holders emit by copying the current state with one field changed, so
/// a state without `copyWith` forces every emit to reconstruct the whole
/// object — and an omitted field is silently reset rather than kept.
///
/// Scope (policy B — Equatable single-class OR Dart 3 sealed union):
/// - A cubit state is detected as an `Equatable` class whose name ends in
///   `State`, outside `/domain/` (domain entities named `*State` are state
///   *values*, not cubit states — they are not cubit-emitted and are exempt).
/// - **Sealed-union states are exempt** — they don't extend `Equatable` (so
///   they never match here), and their variants are constructed fresh via
///   pattern matching rather than copied.
/// - Abstract bases are exempt (the concrete leaf carries `copyWith`).
/// - States with fewer than two fields are exempt — a 0- or 1-field
///   state reconstructs trivially, so copyWith earns nothing.
///
/// **Bad:**
/// ```dart
/// class ReaderState extends Equatable { /* no copyWith */ }
/// ```
///
/// **Good:**
/// ```dart
/// class ReaderState extends Equatable {
///   ReaderState copyWith({ ... }) => ReaderState( ... );
/// }
/// ```
class StateProvidesCopyWith extends ResolvedLintRule {
  StateProvidesCopyWith({
    String? stateBase,
    String? stateSuffix,
    String? domainSegment,
  }) : stateBase = stateBase ?? 'Equatable',
       stateSuffix = stateSuffix ?? 'State',
       domainSegment = domainSegment ?? '/domain/';

  /// The value-equality base a state class extends.
  final String stateBase;

  /// The name suffix that marks a class as a state.
  final String stateSuffix;

  /// Path fragment for the layer where a same-named class is an entity rather
  /// than a state, and so is not this rule's business.
  final String domainSegment;

  @override
  String get name => 'state_provides_copywith';

  @override
  String get description =>
      'A state class with 2+ fields (extends $stateBase, name ends in '
      '$stateSuffix) must declare copyWith.';

  @override
  ResolvedLintVisitor createResolvedVisitor(
    String filePath,
    ResolvedUnitResult resolvedUnit,
  ) => _Visitor(filePath, resolvedUnit, stateBase, stateSuffix, domainSegment);
}

class _Visitor extends ResolvedLintVisitor {
  _Visitor(
    super.filePath,
    super.resolvedUnit,
    this.stateBase,
    this.stateSuffix,
    this.domainSegment,
  );

  final String stateBase;
  final String stateSuffix;
  final String domainSegment;

  // Dart cannot nest a ClassDeclaration inside a class body, so
  // super.visitClassDeclaration is intentionally skipped — recursion
  // would never find a second ClassDeclaration to visit.
  @override
  void visitClassDeclaration(ClassDeclaration node) {
    // Detection: a single-class cubit state.
    final String name = node.name.lexeme;
    if (!name.endsWith(stateSuffix)) {
      return;
    }
    if (filePath.contains(domainSegment)) {
      return;
    }
    if (node.abstractKeyword != null) {
      return;
    }
    if (!_extendsStateBase(node)) {
      return;
    }

    // Guard: skip states with fewer than 2 fields — copyWith earns nothing there.
    if (!_hasMultipleInstanceFields(node)) {
      return;
    }

    // Report: state is missing copyWith.
    if (!_declaresCopyWith(node)) {
      report(
        ruleName: 'state_provides_copywith',
        message:
            '$name is a multi-field state but declares no copyWith. '
            'Add copyWith so the state holder can emit field updates '
            'without reconstructing the whole state — or, if it has genuinely '
            'distinct variants, model it as a Dart 3 sealed union instead.',
        offset: node.name.offset,
      );
    }
  }

  // debt: this supertype walk is duplicated in
  // novelglide_prefer_loadingstatecode_over_bool.dart — extract a shared
  // helper onto ResolvedLintVisitor in lint_rule_base.dart.
  bool _extendsStateBase(ClassDeclaration node) {
    final List<InterfaceType>? supertypes =
        node.declaredFragment?.element.allSupertypes;
    if (supertypes == null) {
      return false;
    }
    return supertypes.any((InterfaceType t) => t.element.name == stateBase);
  }

  bool _declaresCopyWith(ClassDeclaration node) {
    return node.members.whereType<MethodDeclaration>().any(
      (MethodDeclaration m) => m.name.lexeme == 'copyWith',
    );
  }

  bool _hasMultipleInstanceFields(ClassDeclaration node) {
    final int count = node.members
        .whereType<FieldDeclaration>()
        .where((FieldDeclaration f) => f.staticKeyword == null)
        .expand((FieldDeclaration f) => f.fields.variables)
        .length;
    return count >= 2;
  }
}
