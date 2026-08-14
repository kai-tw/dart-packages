import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../lint_rule_base.dart';

/// Requires that a state-holder class carries its role suffix.
///
/// The inverse of `avoid_reserved_widget_suffix`, which forbids the same
/// suffix on widgets: there a non-state-holder must not claim the name, here a
/// real one must.
///
/// A cubit named without the suffix breaks the "read in isolation"
/// promise — a call site, grep hit, or stack frame can no longer tell
/// the type's layer/role from its name alone.
///
/// `Bloc` subclasses are not covered (that's `prefer_cubit_over_bloc`'s
/// job); this rule scopes to `Cubit` because `Cubit` and `Bloc` are
/// siblings under `BlocBase`, so a `Cubit` supertype never matches a
/// `Bloc`.
///
/// **Bad:**
/// ```dart
/// class ReaderSettings extends Cubit<ReaderSettingsState> { ... }
/// ```
///
/// **Good:**
/// ```dart
/// class ReaderSettingsCubit extends Cubit<ReaderSettingsState> { ... }
/// ```
class RequireCubitSuffix extends ResolvedLintRule {
  RequireCubitSuffix({String? stateHolderBase, String? requiredSuffix})
    : stateHolderBase = stateHolderBase ?? 'Cubit',
      requiredSuffix = requiredSuffix ?? 'Cubit';

  /// The supertype that makes a class a state holder.
  final String stateHolderBase;

  /// The role suffix its name must carry. Separate from [stateHolderBase]
  /// because a project may name the role differently from the base it extends.
  final String requiredSuffix;

  @override
  String get name => 'require_cubit_suffix';

  @override
  String get description =>
      'A class extending $stateHolderBase must carry the '
      '$requiredSuffix role suffix.';

  @override
  ResolvedLintVisitor createResolvedVisitor(
    String filePath,
    ResolvedUnitResult resolvedUnit,
  ) => _Visitor(filePath, resolvedUnit, stateHolderBase, requiredSuffix);
}

class _Visitor extends ResolvedLintVisitor {
  _Visitor(
    super.filePath,
    super.resolvedUnit,
    this.stateHolderBase,
    this.requiredSuffix,
  );

  final String stateHolderBase;
  final String requiredSuffix;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final String name = node.name.lexeme;

    if (!_isCubit(node)) {
      super.visitClassDeclaration(node);
      return;
    }

    if (!name.endsWith(requiredSuffix)) {
      report(
        ruleName: 'require_cubit_suffix',
        message:
            '$name extends $stateHolderBase but lacks the '
            "'$requiredSuffix' role suffix. Rename to $name$requiredSuffix — "
            "the suffix announces the class's layer and role at "
            'every call site, grep hit, and stack frame.',
        offset: node.name.offset,
      );
    }

    super.visitClassDeclaration(node);
  }

  bool _isCubit(ClassDeclaration node) {
    final List<InterfaceType>? supertypes =
        node.declaredFragment?.element.allSupertypes;
    if (supertypes == null) {
      return false;
    }
    return supertypes.any(
      (InterfaceType t) => t.element.name == stateHolderBase,
    );
  }
}
