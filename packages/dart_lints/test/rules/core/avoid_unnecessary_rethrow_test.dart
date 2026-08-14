// Contract tests for `avoid_unnecessary_rethrow`.
//
// The rule's whole value is deleting a no-op catch clause, so its dangerous
// failure is the inverse: flagging a clause whose removal CHANGES BEHAVIOUR.
// A `rethrow` leaves the entire `try` rather than re-entering the clause list,
// so an arm sitting in front of a broader one exists precisely to keep that
// broader arm off its type — and the rule ships an auto-fix that would delete
// it. Those cases are the reason the sibling guard exists and are pinned here.
//
// Technique index: equivalence partitioning over the two reported patterns
// (rethrow / throw-same-type), boundary value on clause position (last vs not
// last — the guard's actual predicate), mutation sensitivity (drop the guard
// and the four `load-bearing` cases go red).

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dart_lints/src/lint_rule_base.dart';
import 'package:dart_lints/src/rules/core/avoid_unnecessary_rethrow.dart';
import 'package:test/test.dart';

List<LintViolation> _lint(String body) {
  final String source =
      'class AErr implements Exception {}\n'
      'class BErr implements AErr {}\n'
      'void work() {}\n'
      'void f() {\n$body\n}\n';
  final ParseStringResult result = parseString(
    content: source,
    throwIfDiagnostics: false,
  );
  final AvoidUnnecessaryRethrow rule = AvoidUnnecessaryRethrow();
  final LintVisitor visitor = rule.createVisitor(
    'lib/features/foo/foo.dart',
    result.lineInfo,
    source,
  );
  result.unit.accept(visitor);
  return visitor.violations;
}

void main() {
  group('reported — the clause really is a no-op', () {
    test('[EP] `on X { rethrow; }` as the only clause', () {
      expect(_lint('try { work(); } on AErr { rethrow; }'), hasLength(1));
    });

    test('[EP] `on X catch (e) { rethrow; }` — a caught binding changes '
        'nothing about the clause being a no-op', () {
      expect(
        _lint('try { work(); } on AErr catch (_) { rethrow; }'),
        hasLength(1),
      );
    });

    test('[EP] `on X { throw X(); }` — rethrowing the same type by hand', () {
      expect(_lint('try { work(); } on AErr { throw AErr(); }'), hasLength(1));
    });

    test('[BVA] LAST of several clauses — nothing follows it, so deleting it '
        'lets the type propagate exactly as the rethrow did', () {
      expect(
        _lint('try { work(); } on BErr { work(); } on AErr { rethrow; }'),
        hasLength(1),
      );
    });
  });

  group('NOT reported — deleting the clause would change behaviour', () {
    test('[BVA, mutation pin] a rethrow arm FOLLOWED by another clause is '
        'load-bearing: removing it routes the type into the later arm', () {
      expect(
        _lint('try { work(); } on BErr { rethrow; } on AErr { work(); }'),
        isEmpty,
      );
    });

    test(
      '[mutation pin] the same guard covers the throw-same-type pattern, '
      'which also leaves the try rather than re-entering the clause list',
      () {
        expect(
          _lint(
            'try { work(); } on BErr { throw BErr(); } on AErr { work(); }',
          ),
          isEmpty,
        );
      },
    );

    test('[FMEA] a following BARE catch swallows everything, so the guard '
        'must hold even though that clause names no type', () {
      expect(
        _lint('try { work(); } on BErr { rethrow; } catch (e) { work(); }'),
        isEmpty,
      );
    });

    test('[BVA] middle of three — guarded by the clause after it', () {
      expect(
        _lint(
          'try { work(); } on BErr { work(); } '
          'on BErr { rethrow; } on AErr { work(); }',
        ),
        isEmpty,
      );
    });
  });

  group('never reported — outside the rule\'s shape', () {
    test('[partition] bare `catch (e) { rethrow; }` has no on-type; '
        '`avoid_bare_catch` owns that shape instead', () {
      expect(_lint('try { work(); } catch (e) { rethrow; }'), isEmpty);
    });

    test('[partition] the clause does real work before rethrowing', () {
      expect(_lint('try { work(); } on AErr { work(); rethrow; }'), isEmpty);
    });

    test('[partition] rethrowing as a DIFFERENT type is a translation, not a '
        'no-op', () {
      expect(_lint('try { work(); } on AErr { throw BErr(); }'), isEmpty);
    });
  });
}
