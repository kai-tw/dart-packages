import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dart_lints/src/lint_rule_base.dart';
import 'package:dart_lints/src/rules/core/avoid_production_null_assertion.dart';
import 'package:test/test.dart';

/// Parses [source] syntactically (the rule is purely syntactic, so unresolved
/// identifiers in fixtures are fine) and runs the rule's visitor over it.
///
/// [path] defaults to an app `lib/` file; the `scope exclusion` group drives
/// it to a test path to exercise the opposite side of the `_isTest` gate.
List<LintViolation> _lint(
  String source, {
  String path = 'lib/features/foo/foo_data_source.dart',
}) {
  final ParseStringResult result = parseString(
    content: source,
    throwIfDiagnostics: false,
  );
  final AvoidProductionNullAssertion rule = AvoidProductionNullAssertion();
  final LintVisitor visitor = rule.createVisitor(path, result.lineInfo, source);
  result.unit.accept(visitor);
  return visitor.violations;
}

void main() {
  group('returned null-assertions are flagged', () {
    test(
      '[boundary] block-body `return x!;` — the canonical incident shape',
      () {
        expect(_lint('Object f() { return value!; }'), hasLength(1));
      },
    );

    test(
      '[boundary] arrow-body `=> x!` is the same shape, different syntax',
      () {
        expect(_lint('Object f() => value!;'), hasLength(1));
      },
    );

    test('[partition] property access — the shape that ships in practice', () {
      expect(_lint('Object f() => document.coverImage!;'), hasLength(1));
    });

    test('[partition] index expression', () {
      expect(_lint("Object f() { return map['k']!; }"), hasLength(1));
    });

    test('two returns in one unit each report once', () {
      expect(
        _lint('Object f() { if (c) { return a!; } return b!; }'),
        hasLength(2),
      );
    });
  });

  group('non-assertion returns pass (no false positives)', () {
    test('[partition] plain return', () {
      expect(_lint('Object f() { return value; }'), isEmpty);
    });

    test('[partition] null-coalescing return — the compliant alternative', () {
      expect(_lint('Object f() { return value ?? fallback; }'), isEmpty);
    });

    test(
      '[partition] prefix `!` (boolean negation) is a different operator',
      () {
        expect(_lint('bool f() { return !flag; }'), isEmpty);
      },
    );

    test('[partition] `is!` type test is a different operator', () {
      expect(_lint('bool f() { return value is! String; }'), isEmpty);
    });

    test('[partition] postfix `++` is a PostfixExpression but not `!`', () {
      expect(_lint('int f() { return i++; }'), isEmpty);
    });
  });

  group('scope: only the returned expression itself', () {
    test('assertion consumed by a local, then returned, is out of scope', () {
      expect(
        _lint('Object f() { final Object v = value!; return v; }'),
        isEmpty,
      );
    });

    test('assertion nested inside an argument is out of scope', () {
      expect(_lint('Object f() { return wrap(value!); }'), isEmpty);
    });
  });

  group('scope is the configuration\'s job, not the rule\'s', () {
    // The rule used to carry its own "is this a test file?" path predicate.
    // That was a second definition of "test file" living beside the one the
    // config already declares as an area, free to disagree with it. A project
    // that wants fixtures exempt declares its test paths once and disables the
    // rule there; the rule itself now reports wherever it is run.
    test('reports in a test-tree path — the rule no longer self-excludes', () {
      expect(
        _lint('Object f() => value!;', path: 'test/features/foo_test.dart'),
        hasLength(1),
      );
    });

    test('reports identically whatever the path', () {
      expect(
        _lint(
          'Object f() => value!;',
          path: 'integration_test/reader_test.dart',
        ),
        hasLength(1),
      );
    });
  });
}
