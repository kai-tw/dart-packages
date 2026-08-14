import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when a class extends `Bloc<E, S>` instead of `Cubit<S>`.
///
/// A single-class state holder is the simpler shape here — the
/// event-class indirection a `Bloc` adds buys nothing the project needs
/// and fragments the conventions used by every existing feature.
class PreferCubitOverBloc extends LintRule {
  PreferCubitOverBloc({String? discouragedBase, String? preferredBase})
    : discouragedBase = discouragedBase ?? 'Bloc',
      preferredBase = preferredBase ?? 'Cubit';

  /// The event-driven base this rule steers away from.
  final String discouragedBase;

  /// The base it steers toward.
  final String preferredBase;

  @override
  String get name => 'prefer_cubit_over_bloc';

  @override
  String get description => 'Use $preferredBase, not $discouragedBase.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source, discouragedBase, preferredBase);
}

class _Visitor extends LintVisitor {
  _Visitor(
    super.filePath,
    super.lineInfo,
    super.source,
    this.discouragedBase,
    this.preferredBase,
  );

  final String discouragedBase;
  final String preferredBase;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final ExtendsClause? extends_ = node.extendsClause;
    if (extends_ == null) {
      super.visitClassDeclaration(node);
      return;
    }
    final NamedType supertype = extends_.superclass;
    if (supertype.name.lexeme == discouragedBase) {
      report(
        ruleName: 'prefer_cubit_over_bloc',
        message:
            '${node.name.lexeme} extends $discouragedBase — use '
            '$preferredBase instead.',
        offset: supertype.name.charOffset,
      );
    }
    super.visitClassDeclaration(node);
  }
}
