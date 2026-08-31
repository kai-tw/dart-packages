import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dart_mutants/src/mutant.dart';
import 'package:dart_mutants/src/mutation_visitor.dart';
import 'package:dart_mutants/src/operators/logical_operator_replacement.dart';
import 'package:test/test.dart';

List<Mutant> _mutate(String source, {String path = 'lib/foo.dart'}) {
  final ParseStringResult result = parseString(
    content: source,
    throwIfDiagnostics: false,
  );
  final MutationVisitor visitor = LogicalOperatorReplacement().createVisitor(
    path,
    result.lineInfo,
    source,
  );
  result.unit.accept(visitor);
  return visitor.mutants;
}

void main() {
  test('[partition] && becomes ||', () {
    const String source = 'bool f(bool a, bool b) => a && b;';
    final List<Mutant> mutants = _mutate(source);
    expect(mutants, hasLength(1));
    expect(mutants.single.applyTo(source), 'bool f(bool a, bool b) => a || b;');
  });

  test('[partition] || becomes &&', () {
    const String source = 'bool f(bool a, bool b) => a || b;';
    expect(
      _mutate(source).single.applyTo(source),
      'bool f(bool a, bool b) => a && b;',
    );
  });

  test('[boundary] each operator in a chain is its own mutant', () {
    expect(
      _mutate('bool f(bool a, bool b, bool c) => a && b || c;'),
      hasLength(2),
    );
  });

  test('[boundary] a non-logical binary expression is untouched', () {
    expect(_mutate('int f(int a, int b) => a + b;'), isEmpty);
    expect(_mutate('String f(String? a) => a ?? "d";'), isEmpty);
  });

  test('[boundary] the bitwise & and | are not logical operators', () {
    // Distinct semantics (no short-circuit), and swapping them is a different
    // mutation with a different meaning — out of scope for this operator.
    expect(_mutate('int f(int a, int b) => a & b;'), isEmpty);
    expect(_mutate('int f(int a, int b) => a | b;'), isEmpty);
  });
}
