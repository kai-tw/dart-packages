import 'mutation_operator.dart';
import 'operators/null_coalescing_deletion.dart';
import 'operators/relational_operator_replacement.dart';
import 'operators/switch_expression_arm_swap.dart';
import 'operators/ternary_swap.dart';

/// Every operator this package ships, run by default.
///
/// A flat list, not a bundle/config system like `dart_lints`'s — that earns
/// its complexity from serving many unrelated house rulesets across
/// different project types; every operator here targets the same "regex
/// mutation testing cannot see this" gap, so there is nothing yet for a
/// config layer to actually choose between. Add one if a real need for
/// per-project operator selection shows up.
List<MutationOperator> defaultOperators() => <MutationOperator>[
  TernarySwap(),
  SwitchExpressionArmSwap(),
  NullCoalescingDeletion(),
  RelationalOperatorReplacement(),
];
