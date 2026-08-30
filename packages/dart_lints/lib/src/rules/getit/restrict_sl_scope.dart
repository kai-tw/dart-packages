import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when `sl<T>()` is invoked outside the contexts the dependency
/// injection rule allows: Cubit / Bloc / use-case classes,
/// `setup_dependencies.dart` files, or `BlocProvider(create: ...)` /
/// `BlocProvider.value(...)` named-argument callbacks.
///
/// Resolving the service locator from widgets, listeners, build methods,
/// or root wiring leaks the dependency graph into the widget tree —
/// `sl` becomes an ambient global instead of a wiring detail.
class RestrictSlScope extends LintRule {
  RestrictSlScope({
    String? accessor,
    List<String>? allowedSupertypes,
    List<String>? setupFiles,
    List<String>? providerTypes,
  }) : accessor = accessor ?? 'sl',
       allowedSupertypes =
           allowedSupertypes ??
           const <String>['Cubit<', 'Bloc<', 'BlocBase<', 'UseCase<'],
       setupFiles = setupFiles ?? const <String>['setup_dependencies.dart'],
       providerTypes =
           providerTypes ?? const <String>['BlocProvider', 'MultiBlocProvider'];

  /// The identifier a project resolves dependencies through.
  final String accessor;

  /// Supertype markers whose classes may resolve dependencies directly.
  final List<String> allowedSupertypes;

  /// Wiring containers where resolution is the whole point.
  final List<String> setupFiles;

  /// Widget-tree providers whose create callback may resolve.
  final List<String> providerTypes;

  @override
  String get name => 'restrict_sl_scope';

  @override
  String get description =>
      'sl<T>() is restricted to Cubits, use cases, setup_dependencies.dart, '
      'and BlocProvider.create callbacks.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(
    filePath,
    lineInfo,
    source,
    accessor,
    allowedSupertypes,
    setupFiles,
    providerTypes,
  );
}

class _Visitor extends LintVisitor {
  _Visitor(
    super.filePath,
    super.lineInfo,
    super.source,
    this.accessor,
    this.allowedSupertypes,
    this.setupFiles,
    this.providerTypes,
  );

  final String accessor;
  final List<String> allowedSupertypes;
  final List<String> setupFiles;
  final List<String> providerTypes;

  bool get _isSetupFile => setupFiles.any(filePath.endsWith);

  /// Class supertype name fragments that mark an "allowed enclosing
  /// class" for sl resolution. Matched by substring against the
  /// `extends` clause source text.
  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (!_isSlCall(node)) {
      super.visitMethodInvocation(node);
      return;
    }
    if (_isSetupFile || _isAllowedContext(node)) {
      super.visitMethodInvocation(node);
      return;
    }
    report(
      ruleName: 'restrict_sl_scope',
      message:
          'sl<T>() is restricted to Cubits, use cases, '
          'setup_dependencies.dart, and BlocProvider.create callbacks. '
          'Inject this dependency through the owning Cubit instead.',
      offset: node.methodName.offset,
    );
    super.visitMethodInvocation(node);
  }

  bool _isSlCall(MethodInvocation node) {
    return node.target == null &&
        node.methodName.name == accessor &&
        node.typeArguments != null;
  }

  /// Returns true if [node] is inside an allowed lexical context: an
  /// allowed class body, or a `create` named argument of a
  /// `BlocProvider(...)` constructor (or `BlocProvider.value(...)`).
  bool _isAllowedContext(AstNode node) {
    AstNode? current = node.parent;
    while (current != null) {
      if (_isAllowedAncestor(current)) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }

  bool _isAllowedAncestor(AstNode current) {
    if (current is ClassDeclaration && _isAllowedClass(current)) {
      return true;
    }
    if (current is NamedExpression &&
        current.name.label.name == 'create' &&
        _isInBlocProviderCreation(current)) {
      return true;
    }
    // BlocProvider.value takes a positional `value:` arg via the
    // factory; sl resolution there is allowed by the rule too.
    if (current is InstanceCreationExpression &&
        _isBlocProviderValueCtor(current)) {
      return true;
    }
    return false;
  }

  bool _isAllowedClass(ClassDeclaration node) {
    final ExtendsClause? extends_ = node.extendsClause;
    if (extends_ == null) {
      return false;
    }
    final String src = extends_.superclass.toSource();
    for (final String marker in allowedSupertypes) {
      if (src.contains(marker)) {
        return true;
      }
    }
    return false;
  }

  bool _isInBlocProviderCreation(NamedExpression namedArg) {
    final AstNode? parent = namedArg.parent?.parent;
    if (parent is! InstanceCreationExpression) {
      return false;
    }
    final String typeName = parent.constructorName.type.name.lexeme;
    return providerTypes.contains(typeName);
  }

  bool _isBlocProviderValueCtor(InstanceCreationExpression node) {
    final String typeName = node.constructorName.type.name.lexeme;
    final String? namedCtor = node.constructorName.name?.name;
    return providerTypes.contains(typeName) && namedCtor == 'value';
  }
}
