import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when a Dart record **type annotation** appears.
///
/// A record used as a type annotation names nothing: it has no class to hang a
/// doc comment, an invariant, or a factory on, its equality is positional
/// rather than by declared value semantics, and it cannot participate in the
/// serialization conventions the rest of a codebase's data types share. A
/// named class costs one declaration and gives all of that back.
///
/// **Record literals are allowed** when used transiently for pattern
/// matching (e.g. `switch ((a, b))` on a tuple of values) — they don't
/// escape as a type and they make multi-axis switches more readable
/// than nested conditionals. The forbidden form is exposing a record
/// in a signature, field, or variable declaration.
class AvoidRecordTypes extends LintRule {
  @override
  String get name => 'avoid_record_types';

  @override
  String get description =>
      'Avoid record types as type annotations. Use Equatable parameter '
      'classes or plain classes instead. Transient record literals for '
      'pattern matching are allowed.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source);
}

class _Visitor extends LintVisitor {
  _Visitor(super.filePath, super.lineInfo, super.source);

  @override
  void visitRecordTypeAnnotation(RecordTypeAnnotation node) {
    report(
      ruleName: 'avoid_record_types',
      message:
          'Record type annotation. Declare an Equatable parameter / data '
          'class instead of a record.',
      offset: node.offset,
    );
    super.visitRecordTypeAnnotation(node);
  }
}
