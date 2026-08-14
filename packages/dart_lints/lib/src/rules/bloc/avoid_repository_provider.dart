import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when `RepositoryProvider`, `RepositoryProvider.value`, or
/// `MultiRepositoryProvider` is used to route a service into the widget
/// tree.
///
/// A service belongs to the state holder that uses it, not to the widget tree
/// above it. Routing it through a provider only renames one resolution
/// mechanism into another while adding a tree dependency — and it puts the
/// service somewhere widgets can reach directly, bypassing the state holder
/// that was supposed to own the decision.
class AvoidRepositoryProvider extends LintRule {
  AvoidRepositoryProvider({List<String>? forbiddenProviders})
    : forbiddenProviders =
          forbiddenProviders ??
          const <String>['RepositoryProvider', 'MultiRepositoryProvider'];

  /// Widget-tree provider types this rule refuses. A project routing services
  /// some other way names its own.
  final List<String> forbiddenProviders;

  @override
  String get name => 'avoid_repository_provider';

  @override
  String get description =>
      'Avoid RepositoryProvider/MultiRepositoryProvider — inject services '
      'into the owning Cubit instead.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source, forbiddenProviders);
}

class _Visitor extends LintVisitor {
  _Visitor(
    super.filePath,
    super.lineInfo,
    super.source,
    this.forbiddenProviders,
  );

  final List<String> forbiddenProviders;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final String typeName = node.constructorName.type.name.lexeme;
    if (forbiddenProviders.contains(typeName)) {
      report(
        ruleName: 'avoid_repository_provider',
        message:
            '$typeName routes a service into the widget tree. Move the '
            'action into the owning Cubit and inject the service via the '
            "Cubit's constructor.",
        offset: node.constructorName.offset,
      );
    }
    super.visitInstanceCreationExpression(node);
  }
}
