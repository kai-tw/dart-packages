import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:dart_lints/src/lint_rule_base.dart';
import 'package:dart_lints/src/rules/log_system/avoid_unsafe_log_interpolation.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Self-contained fixture preamble. The rule is a [ResolvedLintRule] — it
/// reads `expression.staticType`, so the fixture must be *resolved* (type
/// info), unlike the syntactic `parseString` harness used for syntax-only
/// rules. Everything the snippets reference (`LogSystem`, an enum, a custom
/// type, a not-LogSystem class, a message-building function) is declared here
/// so the fixture resolves against `dart:core` alone — no package imports.
///
/// `LogSystem.info` deliberately takes only the message (mirroring the real
/// facade) while the other levels carry `error:` / `stackTrace:`; the rule
/// only ever inspects the first positional argument, so this matches
/// production shape without affecting the test.
const String _preamble = r'''
class LogSystem {
  static void debug(String m, {Object? error, StackTrace? stackTrace}) {}
  static void info(String m) {}
  static void warning(String m, {Object? error, StackTrace? stackTrace}) {}
  static void error(String m, {Object? error, StackTrace? stackTrace}) {}
  static void fatal(String m, {Object? error, StackTrace? stackTrace}) {}
  static void event(String name) {}
}

class NotLogSystem {
  static void error(String m, {Object? error, StackTrace? stackTrace}) {}
}

enum SampleEnum { a, b }

class CustomType {
  const CustomType();
}

String buildMessage() => 'built';
''';

/// Writes [snippet] (the body of a `_sample()` function) into a resolved
/// fixture, runs the rule's resolved visitor, and returns the violations.
///
/// Resolution is real (an [AnalysisContextCollection] over a temp file), so
/// `staticType` reflects `dart:core` semantics for `int` / `Uri` / `enum` etc.
Future<List<LintViolation>> _lint(String snippet) async {
  final Directory tempDir = Directory.systemTemp.createTempSync(
    'ngl_unsafe_log_',
  );
  try {
    final String filePath = p.join(tempDir.path, 'fixture.dart');
    final String source = '$_preamble\nvoid _sample() {\n$snippet\n}\n';
    File(filePath).writeAsStringSync(source);

    final AnalysisContextCollection collection = AnalysisContextCollection(
      includedPaths: <String>[filePath],
    );
    final SomeResolvedUnitResult result = await collection
        .contextFor(filePath)
        .currentSession
        .getResolvedUnit(filePath);
    if (result is! ResolvedUnitResult) {
      throw StateError('fixture failed to resolve: $result');
    }

    final AvoidUnsafeLogInterpolation rule = AvoidUnsafeLogInterpolation();
    final ResolvedLintVisitor visitor = rule.createResolvedVisitor(
      filePath,
      result,
    );
    result.unit.accept(visitor);
    return visitor.violations;
  } finally {
    tempDir.deleteSync(recursive: true);
  }
}

void main() {
  // ── Attributed-method partition ────────────────────────────────────────────
  // Which LogSystem levels does the rule govern? info/warning/error/fatal
  // egress to Crashlytics breadcrumbs; debug is device-local + release-
  // suppressed; event is console-only. Each membership decision is pinned so
  // a mutation to `_attributedMethods` (drop one, add one) goes red.
  group('attributed-method partition (egress levels only)', () {
    for (final String level in <String>['info', 'warning', 'error', 'fatal']) {
      test(
        '[equivalence] LogSystem.$level with a String interpolation is flagged',
        () async {
          final List<LintViolation> v = await _lint(
            "final String s = 'x'; LogSystem.$level('v=\$s');",
          );
          expect(v, hasLength(1));
          expect(v.single.ruleName, 'avoid_unsafe_log_interpolation');
        },
      );
    }

    test(
      '[equivalence:exempt] LogSystem.debug with a String interpolation is '
      'NOT flagged (device-local, release-suppressed)',
      () async {
        final List<LintViolation> v = await _lint(
          "final String s = 'x'; LogSystem.debug('v=\$s');",
        );
        expect(v, isEmpty);
      },
    );

    test(
      '[equivalence:exempt] LogSystem.event with a String interpolation is '
      'NOT flagged (console-only, not an egress level)',
      () async {
        final List<LintViolation> v = await _lint(
          "final String s = 'x'; LogSystem.event('v=\$s');",
        );
        expect(v, isEmpty);
      },
    );
  });

  // ── Target partition (must be LogSystem) ───────────────────────────────────
  group('target partition (no over-reach to look-alike methods)', () {
    test(
      '[equivalence:non-target] a same-named .error on a different class is '
      'NOT flagged (target name must be LogSystem)',
      () async {
        final List<LintViolation> v = await _lint(
          "final String s = 'x'; NotLogSystem.error('v=\$s');",
        );
        expect(v, isEmpty);
      },
    );
  });

  // ── Safe literal message forms ─────────────────────────────────────────────
  group('literal message forms pass (no false positives)', () {
    test(
      '[equivalence] a plain string literal message is not flagged',
      () async {
        expect(await _lint("LogSystem.error('plain literal');"), isEmpty);
      },
    );

    test(
      '[equivalence] adjacent string literals (\'a\' \'b\') are not flagged',
      () async {
        expect(await _lint("LogSystem.error('a' 'b');"), isEmpty);
      },
    );
  });

  // ── Interpolation type lattice — ALLOWED (the 2b primitive/enum set) ────────
  group('interpolation of provably non-identifying values passes', () {
    test('[equivalence:int] int interpolation is allowed', () async {
      expect(await _lint("final int n = 1; LogSystem.info('n=\$n');"), isEmpty);
    });

    test('[equivalence:double] double interpolation is allowed', () async {
      expect(
        await _lint("final double d = 1.0; LogSystem.info('d=\$d');"),
        isEmpty,
      );
    });

    test('[equivalence:num] num interpolation is allowed', () async {
      expect(await _lint("final num x = 1; LogSystem.info('x=\$x');"), isEmpty);
    });

    test('[equivalence:bool] bool interpolation is allowed', () async {
      expect(
        await _lint("final bool b = true; LogSystem.info('b=\$b');"),
        isEmpty,
      );
    });

    test('[equivalence:enum] enum interpolation is allowed', () async {
      expect(
        await _lint("LogSystem.info('e=\${SampleEnum.a}');"),
        isEmpty,
      );
    });
  });

  // ── Interpolation type lattice — FORBIDDEN ─────────────────────────────────
  // One representative per identifying class. `Object`/`dynamic` matter because
  // they are the static types a value most often hides behind at a log site.
  group('interpolation of identifying / unverifiable values is flagged', () {
    test('[equivalence:String] String interpolation is flagged', () async {
      expect(
        await _lint("final String s = 'x'; LogSystem.error('s=\$s');"),
        hasLength(1),
      );
    });

    test('[equivalence:Uri] Uri interpolation is flagged', () async {
      expect(
        await _lint(
          "final Uri u = Uri.parse('x'); LogSystem.error('u=\$u');",
        ),
        hasLength(1),
      );
    });

    test(
      '[equivalence:Object] Object-typed interpolation is flagged',
      () async {
        expect(
          await _lint("final Object o = 1; LogSystem.error('o=\$o');"),
          hasLength(1),
        );
      },
    );

    test('[equivalence:dynamic] dynamic interpolation is flagged', () async {
      expect(
        await _lint("final dynamic d = 1; LogSystem.error('d=\$d');"),
        hasLength(1),
      );
    });

    test('[equivalence:custom] custom-type interpolation is flagged', () async {
      expect(
        await _lint(
          "const CustomType c = CustomType(); LogSystem.error('c=\$c');",
        ),
        hasLength(1),
      );
    });
  });

  // ── Per-element granularity ────────────────────────────────────────────────
  // The rule checks each interpolated expression independently, not the
  // message as a whole. Two-String → 2; one-String-one-int → 1. A whole-
  // message check would yield 1 in both cases — so the pair pins granularity.
  group('per-interpolation-element granularity', () {
    test(
      '[boundary:mixed] one String + one int interpolation flags exactly once '
      '(only the String element)',
      () async {
        final List<LintViolation> v = await _lint(
          "final int n = 1; final String s = 'x'; "
          "LogSystem.error('n=\$n s=\$s');",
        );
        expect(v, hasLength(1));
      },
    );

    test(
      '[boundary:multiple] two String interpolations flag twice (per element, '
      'not per message)',
      () async {
        final List<LintViolation> v = await _lint(
          "final String a = 'x'; final String b = 'y'; "
          "LogSystem.error('a=\$a b=\$b');",
        );
        expect(v, hasLength(2));
      },
    );
  });

  // ── AdjacentStrings recursion ──────────────────────────────────────────────
  group('adjacent-strings recursion', () {
    test(
      '[mutation:recursion] an interpolation hidden in an adjacent part is '
      'flagged (recursion into each AdjacentStrings part)',
      () async {
        final List<LintViolation> v = await _lint(
          "final String s = 'x'; LogSystem.error('prefix ' 'mid=\$s');",
        );
        expect(v, hasLength(1));
      },
    );

    test(
      '[boundary:recursion] an adjacent part interpolating only an int is not '
      'flagged',
      () async {
        final List<LintViolation> v = await _lint(
          "final int n = 1; LogSystem.error('prefix ' 'mid=\$n');",
        );
        expect(v, isEmpty);
      },
    );
  });

  // ── Dynamically-constructed (non-literal) messages ─────────────────────────
  // Anything that is not SimpleStringLiteral / AdjacentStrings /
  // StringInterpolation cannot be verified statically → flagged as "must be a
  // string literal", regardless of the runtime contents.
  group('dynamically-constructed messages are flagged', () {
    test(
      '[equivalence:bare-variable] a bare String variable message is flagged',
      () async {
        expect(
          await _lint("final String m = 'x'; LogSystem.error(m);"),
          hasLength(1),
        );
      },
    );

    test(
      '[equivalence:concatenation] a string + variable message is flagged',
      () async {
        expect(
          await _lint("final String s = 'x'; LogSystem.error('a' + s);"),
          hasLength(1),
        );
      },
    );

    test(
      '[boundary:literal-concatenation] even all-literal + concatenation is '
      'flagged (the rule recognises only the three literal node shapes)',
      () async {
        expect(await _lint("LogSystem.error('a' + 'b');"), hasLength(1));
      },
    );

    test(
      '[equivalence:conditional] a conditional-expression message is flagged',
      () async {
        expect(
          await _lint("final bool c = true; LogSystem.error(c ? 'a' : 'b');"),
          hasLength(1),
        );
      },
    );

    test(
      '[equivalence:method-call] a method-call message is flagged',
      () async {
        expect(await _lint('LogSystem.error(buildMessage());'), hasLength(1));
      },
    );
  });
}
