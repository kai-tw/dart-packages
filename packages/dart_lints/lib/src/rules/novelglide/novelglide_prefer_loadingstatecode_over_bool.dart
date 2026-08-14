import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../lint_rule_base.dart';

/// Flags a loading-lifecycle `bool` **field declared in a cubit state**
/// (`state.md`: model load status with `LoadingStateCode`, not bool flags).
///
/// A single status field is exhaustive and rules out impossible
/// combinations like `isLoading && isError`; two booleans can drift into
/// states the UI never expects.
///
/// Scope is deliberately narrow — it fires only on a `bool` whose name is a
/// load-lifecycle term, declared as a field of a cubit state (an `Equatable`
/// class whose name ends in `State`, outside `/domain/`). A `bool isLoading`
/// that is a widget parameter, a local variable, or a value derived from
/// `state.code.isLoading` is correct and never matches.
///
/// **Bad:**
/// ```dart
/// class FooState extends Equatable {
///   final bool isLoading;
///   final bool isError;
/// }
/// ```
///
/// **Good:**
/// ```dart
/// class FooState extends Equatable {
///   final LoadingStateCode code;
/// }
/// ```
class NovelglidePreferLoadingStateCodeOverBool extends ResolvedLintRule {
  @override
  String get name => 'novelglide_prefer_loadingstatecode_over_bool';

  @override
  String get description =>
      'Model load status in a cubit state with LoadingStateCode, not a '
      'bool isLoading / isError field.';

  @override
  ResolvedLintVisitor createResolvedVisitor(
    String filePath,
    ResolvedUnitResult resolvedUnit,
  ) => _Visitor(filePath, resolvedUnit);
}

class _Visitor extends ResolvedLintVisitor {
  _Visitor(super.filePath, super.resolvedUnit);

  /// `bool` field names that should be a `LoadingStateCode` instead.
  static const Set<String> _loadingNames = <String>{
    'isLoading',
    'isLoaded',
    'isError',
    'hasError',
    'loading',
    'isInitial',
  };

  // Dart cannot nest a ClassDeclaration inside a class body, so
  // super.visitClassDeclaration is intentionally skipped — recursion
  // would never find a second ClassDeclaration to visit.
  @override
  void visitClassDeclaration(ClassDeclaration node) {
    // Detection: a cubit state (Equatable, *State, not a domain entity).
    final String name = node.name.lexeme;
    if (!name.endsWith('State')) {
      return;
    }
    if (filePath.contains('/domain/')) {
      return;
    }
    if (!_extendsEquatable(node)) {
      return;
    }

    // Scan: flag any loading-lifecycle bool field.
    for (final ClassMember member in node.members) {
      if (member is! FieldDeclaration) {
        continue;
      }
      if (!_isBoolField(member)) {
        continue;
      }
      for (final VariableDeclaration v in member.fields.variables) {
        if (_loadingNames.contains(v.name.lexeme)) {
          report(
            ruleName: 'novelglide_prefer_loadingstatecode_over_bool',
            message:
                '$name.${v.name.lexeme} is a loading-lifecycle bool. Model '
                'load status with LoadingStateCode (state.md) — one '
                'exhaustive status rules out impossible combinations like '
                'isLoading && isError.',
            offset: v.name.offset,
          );
        }
      }
    }
  }

  // debt: _extendsEquatable is duplicated in state_provides_copywith.dart —
  // extract a shared static helper onto ResolvedLintVisitor in lint_rule.dart.
  bool _extendsEquatable(ClassDeclaration node) {
    final List<InterfaceType>? supertypes =
        node.declaredFragment?.element.allSupertypes;
    if (supertypes == null) {
      return false;
    }
    return supertypes.any((InterfaceType t) => t.element.name == 'Equatable');
  }

  bool _isBoolField(FieldDeclaration field) {
    final TypeAnnotation? type = field.fields.type;
    // Matches both bool and bool? — nullable loading flags are equally wrong.
    return type is NamedType && type.name.lexeme == 'bool';
  }
}
