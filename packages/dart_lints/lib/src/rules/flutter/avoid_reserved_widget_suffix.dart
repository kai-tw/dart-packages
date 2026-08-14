import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../lint_rule_base.dart';

/// One reserved suffix, why it is reserved, and the longer name that is the
/// exception to it.
///
/// A flat list of suffix strings cannot express this. `Sheet` is reserved only
/// when it is *bare* — `BottomSheet` is the spelling the rule steers toward —
/// and each suffix needs its own guidance, because "rename to View /
/// Placeholder / Indicator" is useless advice for a class named `FooCubit`.
class ReservedSuffix {
  const ReservedSuffix({required this.suffix, required this.hint, this.unless});

  factory ReservedSuffix.fromMap(Map<String, Object?> map) => ReservedSuffix(
    suffix: map['suffix']! as String,
    hint: map['hint']! as String,
    unless: map['unless'] as String?,
  );

  final String suffix;
  final String hint;

  /// A longer suffix that is the sanctioned form, so it must not be reported.
  final String? unless;

  bool matches(String name) =>
      name.endsWith(suffix) && !(unless != null && name.endsWith(unless!));
}

/// Warns when a public widget class ends in a suffix reserved for another role.
///
/// A widget named `FooState` collides on import with the state class of the
/// same name, and the reader of a call site cannot tell which they have. The
/// suffixes are configurable; see [ReservedSuffix].
///
/// Private classes (leading `_`) are exempt, which also covers the framework's
/// own `_FooState extends State<Foo>` pattern — those are state objects, not
/// widgets.
class AvoidReservedWidgetSuffix extends ResolvedLintRule {
  AvoidReservedWidgetSuffix({
    List<Map<String, Object?>>? reservedSuffixes,
    List<String>? widgetSupertypes,
  }) : reservedSuffixes =
           reservedSuffixes?.map(ReservedSuffix.fromMap).toList() ??
           _defaultReservedSuffixes,
       widgetSupertypes =
           widgetSupertypes ??
           const <String>['StatelessWidget', 'StatefulWidget'];

  /// Reserved out of the box, so the rule enforces without configuration.
  ///
  /// `State` and `Sheet` are Flutter's own: `State` is the framework's state
  /// object and `Sheet` is the Material component whose full spelling is
  /// `BottomSheet`. `Cubit` names a state-holder role; in a codebase with no
  /// Cubits nothing ends in it, so carrying it costs such a project nothing.
  static const List<ReservedSuffix> _defaultReservedSuffixes = <ReservedSuffix>[
    ReservedSuffix(
      suffix: 'State',
      hint:
          'Rename to View / Placeholder / Indicator / Banner — State is '
          'reserved for the framework and for state classes.',
    ),
    ReservedSuffix(
      suffix: 'Cubit',
      hint:
          'Rename to a descriptive widget role — Cubit is reserved for '
          'state holders.',
    ),
    ReservedSuffix(
      suffix: 'Sheet',
      unless: 'BottomSheet',
      hint:
          'Modal bottom sheets must spell out BottomSheet so call sites '
          'are unambiguous.',
    ),
  ];

  /// Suffixes a widget name may not end in. Configuring an empty list turns the
  /// rule off, which is a project's call to make explicitly — it is not what
  /// silence means.
  final List<ReservedSuffix> reservedSuffixes;

  /// Supertypes that make a class a widget subject to the naming rule.
  final List<String> widgetSupertypes;

  @override
  String get name => 'avoid_reserved_widget_suffix';

  @override
  String get description =>
      'Widget class names must not end in a suffix reserved for another role: '
      '${reservedSuffixes.map((ReservedSuffix r) => r.suffix).join(' / ')}.';

  @override
  ResolvedLintVisitor createResolvedVisitor(
    String filePath,
    ResolvedUnitResult resolvedUnit,
  ) => _Visitor(filePath, resolvedUnit, reservedSuffixes, widgetSupertypes);
}

class _Visitor extends ResolvedLintVisitor {
  _Visitor(
    super.filePath,
    super.resolvedUnit,
    this.reservedSuffixes,
    this._widgetSupertypes,
  );

  final List<ReservedSuffix> reservedSuffixes;
  final List<String> _widgetSupertypes;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final String name = node.name.lexeme;
    if (name.startsWith('_')) {
      return;
    }
    if (!_isWidget(node)) {
      return;
    }

    // First match only: the suffixes are alternatives, and a name ending in two
    // of them has one problem, not two.
    for (final ReservedSuffix reserved in reservedSuffixes) {
      if (!reserved.matches(name)) {
        continue;
      }
      report(
        ruleName: 'avoid_reserved_widget_suffix',
        message:
            "$name uses the reserved '${reserved.suffix}' suffix on a widget. "
            '${reserved.hint}',
        offset: node.name.offset,
      );
      return;
    }
  }

  bool _isWidget(ClassDeclaration node) {
    final List<InterfaceType>? supertypes =
        node.declaredFragment?.element.allSupertypes;
    if (supertypes == null) {
      return false;
    }
    return supertypes.any(
      (InterfaceType t) => _widgetSupertypes.contains(t.element.name),
    );
  }
}
