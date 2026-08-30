import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dart_mutants/src/mutant.dart';
import 'package:dart_mutants/src/mutation_visitor.dart';
import 'package:dart_mutants/src/operators/null_coalescing_deletion.dart';
import 'package:test/test.dart';

List<Mutant> _mutate(String source, {String path = 'lib/foo.dart'}) {
  final ParseStringResult result = parseString(
    content: source,
    throwIfDiagnostics: false,
  );
  final MutationVisitor visitor = NullCoalescingDeletion().createVisitor(
    path,
    result.lineInfo,
    source,
  );
  result.unit.accept(visitor);
  return visitor.mutants;
}

void main() {
  test('[partition] proposes both the fallback alone and the left alone', () {
    const String source = 'String f(String? a) => a ?? "default";';
    final List<Mutant> mutants = _mutate(source);
    expect(mutants, hasLength(2));
    final Set<String> mutated = mutants
        .map((Mutant m) => m.applyTo(source))
        .toSet();
    expect(
      mutated,
      <String>{
        'String f(String? a) => "default";',
        'String f(String? a) => a;',
      },
    );
  });

  test('[boundary] a chained ?? mutates at each binary node separately', () {
    // `a ?? b ?? c` parses as `a ?? (b ?? c)` — the outer node's "left
    // alone"/"fallback alone" mutants operate on the whole `b ?? c` subtree
    // as one operand, which is correct: it is one operand of the outer `??`.
    final List<Mutant> mutants = _mutate(
      "String f(String? a, String? b) => a ?? b ?? 'c';",
    );
    expect(mutants, hasLength(4));
  });

  test('[boundary] a non-null-coalescing binary expression is untouched', () {
    expect(_mutate('bool f(bool a, bool b) => a && b;'), isEmpty);
  });

  test('[boundary] a nullable-typed default expression stays intact', () {
    // Regression guard for offset math: the replacement must be exactly the
    // operand's own span, not accidentally include the `??` token or
    // trailing whitespace.
    const String source = 'int f(int? a) => a ?? 0;';
    final List<Mutant> mutants = _mutate(source);
    final Set<String> mutated = mutants
        .map((Mutant m) => m.applyTo(source))
        .toSet();
    expect(mutated, <String>{
      'int f(int? a) => 0;',
      'int f(int? a) => a;',
    });
  });
}
