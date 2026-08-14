import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../lint_rule_base.dart';

/// Warns when a Cubit subclass passes an inline arrow / anonymous closure
/// to `Stream.listen(...)` or its `onError:` named argument.
///
/// A named method handler keeps the subscription readable, so the
/// `isClosed` guard pattern stays uniform, the listener is greppable
/// across files, and stale closure captures don't drift away from
/// authoritative state.
class PreferNamedSubscriptionCallbacks extends ResolvedLintRule {
  PreferNamedSubscriptionCallbacks({String? stateHolderBase})
    : stateHolderBase = stateHolderBase ?? 'BlocBase';

  /// The state-holder supertype this rule keys on. Named because which base a
  /// project's state holders extend is the project's choice.
  final String stateHolderBase;

  @override
  String get name => 'prefer_named_subscription_callbacks';

  @override
  String get description =>
      'In Cubits, pass a named method reference to Stream.listen / onError '
      '— never an inline closure.';

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

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_inCubitClass && node.methodName.name == 'listen') {
      _checkArgs(node);
    }
    super.visitMethodInvocation(node);
  }

  void _checkArgs(MethodInvocation node) {
    for (final Expression arg in node.argumentList.arguments) {
      if (arg is FunctionExpression) {
        report(
          ruleName: 'prefer_named_subscription_callbacks',
          message:
              'Stream.listen received an inline closure inside a Cubit. '
              'Pass a named method reference (e.g. _onEvent) so the '
              'isClosed guard stays uniform and the listener is '
              'greppable.',
          offset: arg.offset,
        );
      } else if (arg is NamedExpression) {
        if (arg.name.label.name == 'onError' &&
            arg.expression is FunctionExpression) {
          report(
            ruleName: 'prefer_named_subscription_callbacks',
            message:
                'onError received an inline closure inside a Cubit. Pass '
                'a named method reference (e.g. _onEventError).',
            offset: arg.expression.offset,
          );
        }
      }
    }
  }
}
