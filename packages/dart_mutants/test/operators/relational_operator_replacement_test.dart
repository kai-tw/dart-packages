import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dart_mutants/src/mutant.dart';
import 'package:dart_mutants/src/mutation_visitor.dart';
import 'package:dart_mutants/src/operators/relational_operator_replacement.dart';
import 'package:test/test.dart';

List<Mutant> _mutate(String source, {String path = 'lib/foo.dart'}) {
  final ParseStringResult result = parseString(
    content: source,
    throwIfDiagnostics: false,
  );
  final MutationVisitor visitor = RelationalOperatorReplacement().createVisitor(
    path,
    result.lineInfo,
    source,
  );
  result.unit.accept(visitor);
  return visitor.mutants;
}

void main() {
  test('[partition] < proposes <= and >=, not the full relational family', () {
    final List<Mutant> mutants = _mutate('bool f(int a, int b) => a < b;');
    expect(
      mutants.map((Mutant m) => m.replacement).toSet(),
      <String>{'<=', '>='},
    );
  });

  test('[partition] == proposes only !=, not a relational operator', () {
    final List<Mutant> mutants = _mutate('bool f(int a, int b) => a == b;');
    expect(mutants.map((Mutant m) => m.replacement).toSet(), <String>{'!='});
  });

  test('[boundary] each of the six operators is recognised', () {
    for (final String op in <String>['<', '<=', '>', '>=', '==', '!=']) {
      expect(
        _mutate('bool f(int a, int b) => a $op b;'),
        isNotEmpty,
        reason: 'operator "$op" produced no mutants',
      );
    }
  });

  test(
    '[boundary] a < inside a generic type parameter is not a comparison — '
    'this is the exact case the regex-based tool could not tell apart',
    () {
      expect(_mutate('List<int> f() => <int>[];'), isEmpty);
    },
  );

  test('[boundary] && and || are left to the existing regex coverage', () {
    expect(_mutate('bool f(bool a, bool b) => a && b || b;'), isEmpty);
  });

  test('[partition] the applied mutant preserves the rest of the line', () {
    const String source = 'bool f(int a, int b) => a <= b;';
    final Mutant mutant = _mutate(
      source,
    ).firstWhere((Mutant m) => m.replacement == '<');
    expect(mutant.applyTo(source), 'bool f(int a, int b) => a < b;');
  });
}
