import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dart_mutants/src/mutant.dart';
import 'package:dart_mutants/src/mutation_visitor.dart';
import 'package:dart_mutants/src/operators/condition_negation.dart';
import 'package:test/test.dart';

List<Mutant> _mutate(String source, {String path = 'lib/foo.dart'}) {
  final ParseStringResult result = parseString(
    content: source,
    throwIfDiagnostics: false,
  );
  final MutationVisitor visitor = ConditionNegation().createVisitor(
    path,
    result.lineInfo,
    source,
  );
  result.unit.accept(visitor);
  return visitor.mutants;
}

void main() {
  test('[partition] negates a bare-identifier if condition', () {
    const String source = 'void f() { if (mounted) { g(); } }';
    final List<Mutant> mutants = _mutate(source);
    expect(mutants, hasLength(1));
    expect(
      mutants.single.applyTo(source),
      'void f() { if (!(mounted)) { g(); } }',
    );
  });

  test('[partition] negates while and do-while conditions', () {
    expect(_mutate('void f() { while (ready) { g(); } }'), hasLength(1));
    expect(_mutate('void f() { do { g(); } while (ready); }'), hasLength(1));
  });

  test('[partition] negates a collection-if element', () {
    const String source = 'List<int> f() => [1, if (flag) 2];';
    final List<Mutant> mutants = _mutate(source);
    expect(mutants, hasLength(1));
    expect(
      mutants.single.applyTo(source),
      'List<int> f() => [1, if (!(flag)) 2];',
    );
  });

  test(
    '[boundary] the parentheses are mandatory — `!a == b` would negate the '
    'wrong operand while still compiling',
    () {
      const String source = 'void f() { if (a.b) { g(); } }';
      expect(_mutate(source).single.applyTo(source), contains('!(a.b)'));
    },
  );

  group('a top-level comparison is left to RelationalOperatorReplacement', () {
    test('[boundary] a relational condition is not negated', () {
      // Negating `a < b` yields exactly `a >= b`, which that operator already
      // proposes — generating it here spends a second analyze-and-test cycle
      // to re-ask the same question.
      expect(_mutate('void f() { if (a < b) { g(); } }'), isEmpty);
      expect(_mutate('void f() { if (a == b) { g(); } }'), isEmpty);
    });

    test(
      '[boundary] only the TOP level is checked — a comparison inside a '
      'conjunction is still negated as a whole',
      () {
        const String source = 'void f() { if (a < b && c) { g(); } }';
        final List<Mutant> mutants = _mutate(source);
        expect(mutants, hasLength(1));
        expect(mutants.single.applyTo(source), contains('!(a < b && c)'));
      },
    );
  });

  test(
    '[boundary] an if-case is skipped — its expression is a matched value, '
    'not a bool, so `!(x)` never compiles',
    () {
      expect(
        _mutate('void f(Object x) { if (x case int n) { g(n); } }'),
        isEmpty,
      );
    },
  );

  test('[boundary] an already-negated condition is negated again', () {
    // `!x` -> `!(!x)` inverts the guard, so it is a real mutation, not a
    // no-op that would score as permanently undetected.
    const String source = 'void f() { if (!ready) { g(); } }';
    expect(_mutate(source).single.applyTo(source), contains('!(!ready)'));
  });

  test('[boundary] a ternary condition is not this operator\'s job', () {
    // TernarySwap already mutates the ?: by swapping its branches.
    expect(_mutate('int f() => flag ? 1 : 0;'), isEmpty);
  });

  group('nested constructs are visited too, not just the outermost one', () {
    test('[boundary] an if-statement nested inside another if-statement', () {
      const String source = 'void f() { if (a) { if (b) { g(); } } }';
      expect(_mutate(source), hasLength(2));
    });

    test('[boundary] an if-element nested inside another if-element', () {
      const String source = 'List<int> f() => [if (a) if (b) 2];';
      expect(_mutate(source), hasLength(2));
    });

    test('[boundary] a while loop nested inside another while loop', () {
      const String source = 'void f() { while (a) { while (b) { g(); } } }';
      expect(_mutate(source), hasLength(2));
    });

    test('[boundary] a do-while loop nested inside another do-while loop', () {
      const String source =
          'void f() { do { do { g(); } while (b); } while (a); }';
      expect(_mutate(source), hasLength(2));
    });
  });
}
