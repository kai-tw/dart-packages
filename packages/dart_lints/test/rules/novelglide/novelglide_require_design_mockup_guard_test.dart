import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dart_lints/src/lint_rule_base.dart';
import 'package:dart_lints/src/rules/novelglide/novelglide_require_design_mockup_guard.dart';
import 'package:test/test.dart';

/// Parses [source] syntactically (no resolution — the rule is purely syntactic,
/// so undefined identifiers / unresolved imports in fixtures are fine) and runs
/// the rule's visitor over it, returning the violations it reported.
///
/// [path] must look like an app `lib/` file or the rule's `_isAppLib` gate
/// self-skips and every assertion would falsely read 0 — see the
/// `scope exclusion` group for the deliberate negative side of that gate.
List<LintViolation> _lint(
  String source, {
  String path = 'lib/features/foo/foo_page.dart',
}) {
  final ParseStringResult result = parseString(
    content: source,
    throwIfDiagnostics: false,
  );
  final NovelglideRequireDesignMockupGuard rule =
      NovelglideRequireDesignMockupGuard();
  final LintVisitor visitor = rule.createVisitor(path, result.lineInfo, source);
  result.unit.accept(visitor);
  return visitor.violations;
}

/// The line number of the first line whose text contains [needle], 1-based —
/// used to assert *which* of two references a rule flagged without depending on
/// offsets the fixture would have to hand-count.
int _lineOf(String source, String needle) {
  final List<String> lines = source.split('\n');
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].contains(needle)) {
      return i + 1;
    }
  }
  throw ArgumentError('needle "$needle" not found in source');
}

/// A prefixed import of the design-mockup package — the precondition for any
/// `m.` reference to be in scope of the rule.
const String _prefixedImport =
    "import 'package:novel_glide_design_mockups/novel_glide_design_mockups.dart' as m;";

void main() {
  group('guarded references pass (no false positives)', () {
    test('[decision-table] collection-if (IfElement) guard — the canonical '
        'insertion form — is not flagged', () {
      const String source =
          '''
$_prefixedImport

List<Object> build() {
  return <Object>[
    if (DesignMockup.enabled) const m.FooSketch(),
  ];
}
''';
      expect(_lint(source), isEmpty);
    });

    test(
      '[decision-table] statement-if (IfStatement) block guard is not flagged',
      () {
        const String source =
            '''
$_prefixedImport

Object? build() {
  if (DesignMockup.enabled) {
    return const m.FooSketch();
  }
  return null;
}
''';
        expect(_lint(source), isEmpty);
      },
    );
  });

  group('unguarded references are flagged (the false-negative the rule exists '
      'to prevent — an unflagged ref ships in release)', () {
    test(
      '[decision-table] unguarded constructor reference (NamedType) is flagged',
      () {
        const String source =
            '''
$_prefixedImport

Object build() {
  return const m.FooSketch();
}
''';
        final List<LintViolation> violations = _lint(source);
        expect(violations, hasLength(1));
        expect(
          violations.single.ruleName,
          'novelglide_require_design_mockup_guard',
        );
      },
    );

    test('[equivalence/mutation:visitPrefixedIdentifier] unguarded prefixed '
        'identifier reference (m.kConst) is flagged', () {
      const String source =
          '''
$_prefixedImport

Object? get sketchData => m.kDefaultSketchData;
''';
      expect(_lint(source), hasLength(1));
    });

    test(
      '[equivalence/mutation:visitMethodInvocation] unguarded method-invocation '
      'reference (m.helper()) is flagged',
      () {
        const String source =
            '''
$_prefixedImport

void build() {
  m.renderSketch();
}
''';
        expect(_lint(source), hasLength(1));
      },
    );

    test(
      '[mutation:recursion] unguarded chained static access (m.Sketch.kConst, '
      'a PropertyAccess) is flagged — the inner m.Sketch node is caught even '
      'though the top-level node is a PropertyAccess the rule does not override',
      () {
        const String source =
            '''
$_prefixedImport

int get count => m.FooSketch.kDefaultCount;
''';
        expect(_lint(source), hasLength(1));
      },
    );

    test(
      '[mutation:recursion] unguarded chained static method (m.Sketch.make()) '
      'is flagged — visitMethodInvocation only matches a SimpleIdentifier '
      'target, but recursion into the m.Sketch sub-node catches this shape',
      () {
        const String source =
            '''
$_prefixedImport

Object build() => m.FooSketch.make();
''';
        expect(_lint(source), hasLength(1));
      },
    );

    test('[boundary:then/else] reference in the ELSE branch of the guard is '
        'flagged (else is not the guarded branch)', () {
      const String source =
          '''
$_prefixedImport

Object? build() {
  if (DesignMockup.enabled) {
    return null;
  } else {
    return const m.FooSketch();
  }
}
''';
      expect(_lint(source), hasLength(1));
    });

    test('[decision-table:wrong-condition] reference under if (!DesignMockup.'
        'enabled) is flagged (negation is not the guard condition)', () {
      const String source =
          '''
$_prefixedImport

Object? build() {
  if (!DesignMockup.enabled) {
    return const m.FooSketch();
  }
  return null;
}
''';
      expect(_lint(source), hasLength(1));
    });
  });

  group('guard scope opens and closes correctly', () {
    test('[mutation:guard-depth-balance] a reference AFTER the guard block is '
        'flagged while the one INSIDE is not — pins the depth decrement', () {
      const String source =
          '''
$_prefixedImport

Object? build() {
  if (DesignMockup.enabled) {
    return const m.GuardedSketch();
  }
  return const m.UnguardedSketch();
}
''';
      final List<LintViolation> violations = _lint(source);
      // Exactly one: dropping the decrement would guard both (0); failing to
      // guard the then-branch would flag both (2). Only correct open+close
      // yields 1, on the post-block reference.
      expect(violations, hasLength(1));
      expect(violations.single.line, _lineOf(source, 'UnguardedSketch'));
    });
  });

  group('import prefix contract', () {
    test(
      '[decision-table:import-contract] an UNPREFIXED design-mockup import is '
      'flagged at the import (an un-prefixed import is untrackable)',
      () {
        const String source = '''
import 'package:novel_glide_design_mockups/novel_glide_design_mockups.dart';

Object? build() => null;
''';
        final List<LintViolation> violations = _lint(source);
        expect(violations, hasLength(1));
        expect(violations.single.line, 1);
      },
    );
  });

  group('non-target prefixes are never flagged (no over-reach)', () {
    test('[equivalence:non-target-prefix] an unguarded reference through a '
        'DIFFERENT package prefix is not flagged', () {
      const String source = '''
import 'package:flutter/material.dart' as ui;

Object build() => const ui.SizedBox();
''';
      expect(_lint(source), isEmpty);
    });
  });

  group('scope exclusion — the rule governs app lib/ only', () {
    // The positive control for this group is the unguarded-constructor case
    // above: the SAME source at a lib/ path flags. These prove the _isAppLib
    // gate suppresses the flag off the app's lib/ — which is exactly why the
    // design_mockups package itself and the tool/ probe spec are exempt.
    const String unguardedSource = '''
import 'package:novel_glide_design_mockups/novel_glide_design_mockups.dart' as m;

Object build() {
  return const m.FooSketch();
}
''';

    test(
      '[equivalence:scope] an unguarded reference under packages/ is not '
      'flagged (the design_mockups package + other packages are out of scope)',
      () {
        expect(
          _lint(unguardedSource, path: 'packages/some_pkg/lib/some_file.dart'),
          isEmpty,
        );
      },
    );

    test(
      '[equivalence:scope] an unguarded reference under tool/ is not flagged '
      '(not lib/ — this is why the tool/ probe spec mounts a guarded sketch '
      'without tripping the rule)',
      () {
        expect(
          _lint(unguardedSource, path: 'tool/design_mockups/specs/probe.dart'),
          isEmpty,
        );
      },
    );
  });
}
