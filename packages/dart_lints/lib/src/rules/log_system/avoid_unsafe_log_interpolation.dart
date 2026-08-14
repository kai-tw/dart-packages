import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../lint_rule_base.dart';

/// Breadcrumb-level `LogSystem` calls (`info` / `warning` / `error` /
/// `fatal`) reach release Firebase Crashlytics. Interpolating an
/// identifier-shaped value into the **message string** leaks it into the
/// crash log (CWE-532) — and once a value is concatenated into the message,
/// the egress boundary can no longer tell an identifier from benign text, so
/// the only structural defence is to forbid it at authoring time.
///
/// This rule allows interpolation of provably non-identifying primitives —
/// `int` / `double` / `num` / `bool` and any `enum` value — and flags every
/// other interpolation (`String`, `Uri`, `Object`, `dynamic`, a custom type,
/// or a dynamically-constructed message). A `String`-typed value that is
/// genuinely safe (a plugin error code, an exception's `.code`) belongs in the
/// `error:` argument, which the Crashlytics adapter redacts by type — not in
/// the message.
///
/// `debug` is exempt: it is device-local and suppressed in release, so it
/// never egresses.
///
/// **Bad:**
/// ```dart
/// LogSystem.error('downloadBook($bookId): not found');   // String -> flagged
/// LogSystem.info('feed: ${uri}');                        // Uri -> flagged
/// LogSystem.warning('failed ' + reason);                 // dynamic message
/// ```
///
/// **Good:**
/// ```dart
/// LogSystem.error('downloadBook: not found', error: e, stackTrace: s);
/// LogSystem.info('availability=$availability');          // enum -> allowed
/// LogSystem.info('retry attempt $count');                // int -> allowed
/// ```
class AvoidUnsafeLogInterpolation extends ResolvedLintRule {
  AvoidUnsafeLogInterpolation({String? logger, List<String>? breadcrumbLevels})
    : logger = logger ?? 'LogSystem',
      breadcrumbLevels =
          breadcrumbLevels ??
          const <String>['info', 'warning', 'error', 'fatal'];

  /// The logging facade's type name.
  final String logger;

  /// Levels that reach the crash reporter, and therefore may not carry an
  /// interpolated value of unproven type. A device-local level is exempt.
  final List<String> breadcrumbLevels;

  @override
  String get name => 'avoid_unsafe_log_interpolation';

  @override
  String get description =>
      'Breadcrumb-level $logger messages must not interpolate '
      'String/identifier values (CWE-532); only num/bool/enum is allowed.';

  @override
  ResolvedLintVisitor createResolvedVisitor(
    String filePath,
    ResolvedUnitResult resolvedUnit,
  ) => _Visitor(filePath, resolvedUnit, logger, breadcrumbLevels);
}

class _Visitor extends ResolvedLintVisitor {
  _Visitor(
    super.filePath,
    super.resolvedUnit,
    this.logger,
    this.breadcrumbLevels,
  );

  final String logger;
  final List<String> breadcrumbLevels;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_isAttributedLog(node)) {
      final Expression? message = _firstPositionalArg(node);
      if (message != null) {
        _checkMessage(message);
      }
    }
    super.visitMethodInvocation(node);
  }

  bool _isAttributedLog(MethodInvocation node) {
    final Expression? target = node.target;
    if (target is! SimpleIdentifier || target.name != logger) {
      return false;
    }
    return breadcrumbLevels.contains(node.methodName.name);
  }

  Expression? _firstPositionalArg(MethodInvocation node) {
    for (final Expression arg in node.argumentList.arguments) {
      if (arg is! NamedExpression) {
        return arg;
      }
    }
    return null;
  }

  void _checkMessage(Expression message) {
    // A plain string literal is always safe.
    if (message is SimpleStringLiteral) {
      return;
    }

    // Adjacent string literals ('a' 'b') — recurse into each part.
    if (message is AdjacentStrings) {
      for (final StringLiteral part in message.strings) {
        _checkMessage(part);
      }
      return;
    }

    // An interpolated string — verify every interpolated expression is a
    // provably non-identifying primitive or enum.
    if (message is StringInterpolation) {
      for (final InterpolationElement element in message.elements) {
        if (element is InterpolationExpression) {
          final DartType? type = element.expression.staticType;
          if (type == null || !_isNonIdentifying(type)) {
            report(
              ruleName: 'avoid_unsafe_log_interpolation',
              message:
                  'Interpolating a non-primitive value into a breadcrumb '
                  'log message can leak PII to release Crashlytics '
                  '(CWE-532). Move it to the error: argument, or interpolate '
                  'only num/bool/enum.',
              offset: element.offset,
            );
          }
        }
      }
      return;
    }

    // Any other shape (`'a' + x`, a method call, a conditional, a bare
    // variable) constructs the message dynamically — it can carry an
    // identifier and cannot be verified statically.
    report(
      ruleName: 'avoid_unsafe_log_interpolation',
      message:
          'Breadcrumb log message must be a string literal; a dynamically '
          'constructed message can leak PII to release Crashlytics (CWE-532).',
      offset: message.offset,
    );
  }

  /// Whether [type] is a value that cannot carry user-derived data — an
  /// `int` / `double` / `num` / `bool`, or any `enum` (which implicitly
  /// extends `dart:core`'s `Enum`).
  bool _isNonIdentifying(DartType type) {
    if (type.isDartCoreInt ||
        type.isDartCoreDouble ||
        type.isDartCoreNum ||
        type.isDartCoreBool) {
      return true;
    }
    return type is InterfaceType &&
        type.allSupertypes.any(
          (InterfaceType supertype) => supertype.element.name == 'Enum',
        );
  }
}
