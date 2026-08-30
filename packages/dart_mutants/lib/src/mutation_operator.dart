import 'package:analyzer/source/line_info.dart';

import 'mutation_visitor.dart';

/// Finds every place in a file where one specific kind of edit applies, and
/// proposes each as a [Mutant]. One operator, one construct — `??` and the
/// ternary are separate operators, not cases in a shared switch, so each has
/// its own file and its own tests, the same shape `dart_lints`'s rules use.
abstract class MutationOperator {
  /// Stable and machine-readable, e.g. `'ternary_swap'`.
  String get name;

  String get description;

  MutationVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  );
}
