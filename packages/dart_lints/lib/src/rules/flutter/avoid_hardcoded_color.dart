import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when presentation-layer code constructs a hardcoded `Color`,
/// references a constant on `Colors`, or uses the deprecated
/// `.withOpacity()` accessor.
///
/// Hardcoded colors ignore the current theme and break dark/light mode.
/// `Colors.X` and `Color(0x...)` both bypass `Theme.of(context).colorScheme`.
/// `.withOpacity()` is deprecated; `.withValues(alpha: ...)` is the
/// non-lossy replacement.
///
/// **Bad:**
/// ```dart
/// color: Color(0x33000000),
/// color: Color.fromARGB(51, 0, 0, 0),
/// color: Colors.red,
/// color: Theme.of(context).colorScheme.surface.withOpacity(0.8),
/// ```
///
/// **Good:**
/// ```dart
/// color: Theme.of(context).shadowColor.withAlpha(0x33),
/// color: Theme.of(context).colorScheme.outline,
/// color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
/// ```
///
/// Scoped by the `pathMarkers` option; unscoped by default.
class AvoidHardcodedColor extends LintRule {
  AvoidHardcodedColor({List<String>? pathMarkers})
    : pathMarkers = pathMarkers ?? const <String>[];

  /// Path fragments scoping the rule. **Empty means the whole tree.**
  ///
  /// Theme-driven colour is a project's idea, not a directory's: a codebase
  /// whose hardcoded colours sit in shared and core folders has no directory to
  /// name. Defaulting to a presentation folder would have silently excused
  /// every colour outside it, which is the failure this rule exists to prevent.
  final List<String> pathMarkers;

  @override
  String get name => 'avoid_hardcoded_color';

  @override
  String get description =>
      'Avoid hardcoded Color, Colors.X, and .withOpacity() in '
      'presentation files. Use theme colors and .withValues().';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source, pathMarkers);
}

class _Visitor extends LintVisitor {
  _Visitor(super.filePath, super.lineInfo, super.source, this.pathMarkers);

  final List<String> pathMarkers;

  bool get _isPresentation =>
      pathMarkers.isEmpty || pathMarkers.any(filePath.contains);

  static const Set<String> _flaggedConstructors = <String>{
    'fromARGB',
    'fromRGBO',
  };

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (_isPresentation) {
      final String typeName = node.constructorName.type.toSource();
      if (typeName == 'Color') {
        final String? namedConstructor = node.constructorName.name?.name;
        if (namedConstructor == null ||
            _flaggedConstructors.contains(namedConstructor)) {
          report(
            ruleName: 'avoid_hardcoded_color',
            message:
                'Avoid hardcoded Color constructor in presentation code. '
                'Use Theme.of(context).colorScheme.* instead.',
            offset: node.constructorName.offset,
          );
        }
      }
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (_isPresentation && node.prefix.name == 'Colors') {
      report(
        ruleName: 'avoid_hardcoded_color',
        message:
            'Avoid Colors.${node.identifier.name} in presentation code. '
            'Use Theme.of(context).colorScheme.* instead.',
        offset: node.offset,
      );
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_isPresentation && node.methodName.name == 'withOpacity') {
      report(
        ruleName: 'avoid_hardcoded_color',
        message:
            '.withOpacity() is deprecated. Use '
            '.withValues(alpha: ...) for non-lossy alpha adjustment.',
        offset: node.methodName.offset,
      );
    }
    super.visitMethodInvocation(node);
  }
}
