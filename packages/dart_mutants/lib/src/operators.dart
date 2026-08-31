import 'mutation_operator.dart';
import 'operators/arithmetic_operator_replacement.dart';
import 'operators/condition_negation.dart';
import 'operators/logical_operator_replacement.dart';
import 'operators/null_coalescing_deletion.dart';
import 'operators/relational_operator_replacement.dart';
import 'operators/statement_deletion.dart';
import 'operators/switch_expression_arm_swap.dart';
import 'operators/ternary_swap.dart';

/// Every operator this package ships, run by default.
///
/// These fall into two groups that ask genuinely different questions, and a
/// pool holding only one of them has a blind half rather than merely a
/// smaller sample.
///
/// The **replacement and swap** operators ask "is this expression's branch or
/// boundary pinned?" — they presume the line runs and probe which way it
/// went. The **deletion and negation** operators ask the prior question:
/// "does any test assert this line's effect happened at all?" A guard like
/// `if (mounted) { setState(...) }` contains nothing for the first group to
/// grab, so a pool made only of those walks past it entirely and reports a
/// clean score for code nothing measured.
///
/// The first four shipped alone in 0.1.0 for a reason that has since expired.
/// This package was built to cover what a regex-based mutator could not see,
/// alongside that mutator — so reimplementing the constructs regex handled
/// fine (statements, `&&`/`||`, arithmetic) would have been duplicated work.
/// The AST engine then *replaced* the regex one outright instead of running
/// beside it, and the coverage that tool used to contribute left with it. The
/// scope never changed; the arrangement it was scoped against did.
///
/// A flat list, not a bundle/config system like `dart_lints`'s — that earns
/// its complexity from serving many unrelated house rulesets across different
/// project types. Add one if a real need for per-project operator selection
/// shows up; a caller wanting to stage these in gradually is the first
/// plausible candidate, and would be the reason to build it.
List<MutationOperator> defaultOperators() => <MutationOperator>[
  TernarySwap(),
  SwitchExpressionArmSwap(),
  NullCoalescingDeletion(),
  RelationalOperatorReplacement(),
  StatementDeletion(),
  ConditionNegation(),
  LogicalOperatorReplacement(),
  ArithmeticOperatorReplacement(),
];
