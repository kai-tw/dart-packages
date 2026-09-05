import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dart_mutants/src/mutant.dart';
import 'package:dart_mutants/src/mutation_visitor.dart';
import 'package:dart_mutants/src/operators/statement_deletion.dart';
import 'package:test/test.dart';

List<Mutant> _mutate(String source, {String path = 'lib/foo.dart'}) {
  final ParseStringResult result = parseString(
    content: source,
    throwIfDiagnostics: false,
  );
  final MutationVisitor visitor = StatementDeletion().createVisitor(
    path,
    result.lineInfo,
    source,
  );
  result.unit.accept(visitor);
  return visitor.mutants;
}

void main() {
  test('[partition] deletes each statement of a body separately', () {
    const String source = 'void f() { a(); b(); }';
    final List<Mutant> mutants = _mutate(source);
    expect(mutants, hasLength(2));
    expect(
      mutants.map((Mutant m) => m.applyTo(source)).toSet(),
      <String>{'void f() { ; b(); }', 'void f() { a(); ; }'},
    );
  });

  test(
    '[partition] reaches the guarded statement that no other operator sees '
    '— the whole reason this operator exists',
    () {
      const String source = 'void f() { if (mounted) { setState(); } }';
      final List<Mutant> mutants = _mutate(source);
      final Set<String> mutated = mutants
          .map((Mutant m) => m.applyTo(source))
          .toSet();
      // Both the guarded call and the guard-as-a-whole are deletable.
      expect(mutated, contains('void f() { if (mounted) { ; } }'));
      expect(mutated, contains('void f() { ; }'));
    },
  );

  test('[boundary] a nested block\'s statements are mutated too', () {
    const String source = 'void f() { if (a) { b(); } }';
    final List<Mutant> mutants = _mutate(source);
    // The `if` statement itself, plus `b();` inside its block.
    expect(mutants, hasLength(2));
  });

  test('[boundary] an already-empty statement is not proposed', () {
    // `;` -> `;` is a no-op mutant no test could ever fail on, so it would
    // score as permanently undetected and drag every file containing one.
    expect(_mutate('void f() { ; }'), isEmpty);
  });

  test(
    '[boundary] an expression body has no block, so nothing is proposed',
    () {
      expect(_mutate('int f() => 1;'), isEmpty);
    },
  );

  test(
    '[boundary] a multi-line statement is summarised, not printed whole',
    () {
      final List<Mutant> mutants = _mutate('''
void f() {
  someCall(
    aLongArgumentName: 1,
    anotherLongArgumentName: 2,
    aThirdArgumentNameForLength: 3,
  );
}
''');
      expect(mutants, hasLength(1));
      expect(mutants.single.description, isNot(contains('\n')));
      expect(mutants.single.description.length, lessThan(80));
    },
  );

  group('the summary\'s 60-char truncation boundary', () {
    test(
      '[boundary] a statement flattening to exactly 60 chars is not '
      'truncated — the cutoff is inclusive',
      () {
        final String call = '${'a'.padRight(57, 'b')}();';
        expect(call.length, 60);
        final List<Mutant> mutants = _mutate('void f() { $call }');
        expect(mutants.single.description, "deleted '$call'");
      },
    );

    test(
      '[boundary] a statement flattening to 61 chars is truncated to 57 '
      'chars plus an ellipsis',
      () {
        final String call = '${'a'.padRight(58, 'b')}();';
        expect(call.length, 61);
        final List<Mutant> mutants = _mutate('void f() { $call }');
        expect(
          mutants.single.description,
          "deleted '${call.substring(0, 57)}...'",
        );
      },
    );
  });

  test('[partition] a closure body is its own block', () {
    const String source = 'void f() { xs.forEach((int x) { g(x); }); }';
    final List<Mutant> mutants = _mutate(source);
    // The whole `xs.forEach(...)` statement, and `g(x);` within the closure.
    expect(mutants, hasLength(2));
    expect(
      mutants.map((Mutant m) => m.applyTo(source)),
      contains('void f() { xs.forEach((int x) { ; }); }'),
    );
  });
}
