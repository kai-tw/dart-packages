import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when `MediaQuery.of(context)` is used.
///
/// `MediaQuery.of(context)` subscribes to the entire `MediaQueryData`,
/// causing the widget to rebuild whenever any property changes. Use
/// fine-grained accessors or `View.of(context)` instead.
///
/// **Bad:**
/// ```dart
/// final size = MediaQuery.of(context).size;
/// final dpr = MediaQuery.of(context).devicePixelRatio;
/// ```
///
/// **Good:**
/// ```dart
/// final size = MediaQuery.sizeOf(context);
/// final dpr = View.of(context).devicePixelRatio;
/// ```
class AvoidMediaQueryOf extends LintRule {
  @override
  String get name => 'avoid_media_query_of';

  @override
  String get description =>
      'Avoid MediaQuery.of(context). '
      'Use fine-grained accessors like MediaQuery.sizeOf(context) '
      'or View.of(context) instead.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source);
}

class _Visitor extends LintVisitor {
  _Visitor(super.filePath, super.lineInfo, super.source);

  /// MediaQuery instance properties that have a corresponding
  /// `MediaQuery.<prop>Of(context)` static accessor. When the lint
  /// hits one of these via `MediaQuery.of(context).<prop>`, the fix
  /// rewrites it to the fine-grained accessor.
  static const Set<String> _propertyWhitelist = <String>{
    'size',
    'padding',
    'viewInsets',
    'viewPadding',
    'devicePixelRatio',
    'textScaler',
    'platformBrightness',
    'orientation',
    'alwaysUse24HourFormat',
    'accessibleNavigation',
    'invertColors',
    'highContrast',
    'onOffSwitchLabels',
    'disableAnimations',
    'boldText',
    'navigationMode',
    'gestureSettings',
    'displayFeatures',
    'supportsShowingSystemContextMenu',
    'systemGestureInsets',
  };

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'of') {
      final Expression? target = node.target;
      if (target is SimpleIdentifier && target.name == 'MediaQuery') {
        report(
          ruleName: 'avoid_media_query_of',
          message:
              'Avoid MediaQuery.of(context) — it rebuilds on every '
              'MediaQueryData change. Use MediaQuery.sizeOf, '
              'MediaQuery.paddingOf, or View.of instead.',
          offset: target.offset,
          fix: _buildFix(node),
        );
      }
    }
    super.visitMethodInvocation(node);
  }

  /// Builds a fix when the call is `MediaQuery.of(context).<prop>` and
  /// `<prop>` has a known `MediaQuery.<prop>Of(context)` accessor.
  /// Returns `null` for other shapes (raw `MediaQuery.of(context)`,
  /// non-whitelisted property, cascade, etc.) — the violation still
  /// reports, but the user must rewrite by hand.
  LintFix? _buildFix(MethodInvocation node) {
    final AstNode? parent = node.parent;
    if (parent is! PropertyAccess) {
      return null;
    }
    if (parent.target != node) {
      return null;
    }

    final String prop = parent.propertyName.name;
    if (!_propertyWhitelist.contains(prop)) {
      return null;
    }

    final String args = node.argumentList.toSource();
    return LintFix(
      description:
          'Replace MediaQuery.of(context).$prop with '
          'MediaQuery.${prop}Of(context)',
      edits: <SourceEdit>[
        SourceEdit(
          offset: parent.offset,
          length: parent.length,
          replacement: 'MediaQuery.${prop}Of$args',
        ),
      ],
    );
  }
}
