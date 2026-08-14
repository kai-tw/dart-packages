import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Flags a Material `Badge` whose `child:` is a button widget instead of
/// the bare `Icon` it is meant to annotate.
///
/// A `Badge` pins its dot to the top-end corner of its child's layout
/// box. Wrapping the whole button puts the dot at the corner of the
/// ~48dp Material hit-box — far from the glyph. Badge the `Icon` and hand
/// the `Badge` to the button's icon slot so the dot sits on the glyph.
///
/// Scope is the direct `child:` only — the canonical mistake is
/// `Badge(child: IconButton(...))`. A `Badge(child: Icon(...))` handed to
/// `IconButton(icon: ...)` is the correct shape and never matches.
///
/// **Bad:**
/// ```dart
/// Badge(child: IconButton(onPressed: ..., icon: Icon(Icons.menu)));
/// ```
///
/// **Good:**
/// ```dart
/// IconButton(
///   icon: Badge(child: Icon(Icons.menu)),
///   onPressed: ...,
/// );
/// ```
class AvoidBadgeWrappingButton extends LintRule {
  @override
  String get name => 'avoid_badge_wrapping_button';

  @override
  String get description =>
      'Badge the Icon, not the button — hand Badge(child: Icon(...)) to '
      "the button's icon slot so the dot sits on the glyph.";

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source);
}

class _Visitor extends LintVisitor {
  _Visitor(super.filePath, super.lineInfo, super.source);

  /// Material buttons whose tap target is the full ~48dp hit-box, so a
  /// wrapping `Badge` lands its dot at the box corner, not the glyph.
  static const Set<String> _buttonTypes = <String>{
    'IconButton',
    'PopupMenuButton',
    'FloatingActionButton',
    'FilledButton',
    'ElevatedButton',
    'OutlinedButton',
    'TextButton',
    'BackButton',
    'CloseButton',
  };

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // Match Material Badge( … ) / Badge.count( … ).
    if (node.constructorName.type.name.lexeme == 'Badge') {
      final Expression? child = _childArgument(node);

      // Flag only a button handed directly as the child.
      if (child is InstanceCreationExpression) {
        final String childType = child.constructorName.type.name.lexeme;
        if (_buttonTypes.contains(childType)) {
          report(
            ruleName: 'avoid_badge_wrapping_button',
            message:
                'Badge wraps $childType — badge the Icon, not the button. '
                'Hand Badge(child: Icon(...)) to the button icon slot so the '
                'dot sits on the glyph, not the ~48dp hit-box corner.',
            offset: node.constructorName.offset,
          );
        }
      }
    }

    super.visitInstanceCreationExpression(node);
  }

  /// The expression passed as the `child:` named argument, or null.
  Expression? _childArgument(InstanceCreationExpression node) {
    for (final Expression arg in node.argumentList.arguments) {
      if (arg is NamedExpression && arg.name.label.name == 'child') {
        return arg.expression;
      }
    }

    return null;
  }
}
