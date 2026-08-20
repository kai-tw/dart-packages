import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:dart_lints/src/lint_rule_base.dart';
import 'package:dart_lints/src/rules/flutter/avoid_hardcoded_color.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A **resolved** unit, not a parsed one: the runner lints what
/// `getResolvedUnit` returns, and only there does `Color(0xff112233)` become an
/// `InstanceCreationExpression`. Parsed, it is indistinguishable from a
/// function call, so a parse-only fixture would report nothing and every
/// expectation below would pass whatever the rule did.
const String _stubs = r'''
class Color {
  const Color(int value);
  const Color.fromARGB(int a, int r, int g, int b);
  const Color.fromRGBO(int r, int g, int b, double opacity);
  Color withOpacity(double opacity) => this;
  Color withValues({double? alpha}) => this;
}

class Colors {
  static const Color red = Color(0xffff0000);
}

const int brandArgb = 0xffea580c;
''';

/// One case per line, so the assertions can name lines rather than counts —
/// a count says three were reported, not which three.
const String _fixture = r'''
import 'stubs.dart';

Object literal() => const Color(0x33000000);
Object fromArgb() => const Color.fromARGB(51, 0, 0, 0);
Object fromRgbo() => const Color.fromRGBO(0, 0, 0, 0.2);
Object parenthesised() => const Color((0x33000000));
Object negative() => const Color.fromARGB(1, 0, 0, 0);
Object materialConstant() => Colors.red;
Object stored(int argb) => Color(argb);
Object parsed(String hex) => Color(int.parse(hex, radix: 16));
Object namedConstant() => const Color(brandArgb);
Object mixed(int alpha) => Color.fromARGB(alpha, 0, 0, 0);
Object arithmetic() => const Color(0xff000000 + 1);
Object opacity(Color c) => c.withOpacity(0.8);
Object values(Color c) => c.withValues(alpha: 0.8);
''';

/// The 1-based line of each named function in [_fixture], so an edit to the
/// fixture cannot silently point an expectation at the wrong case.
int _lineOf(String functionName) {
  final List<String> lines = _fixture.split('\n');
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].startsWith('Object $functionName(')) {
      return i + 1;
    }
  }
  throw ArgumentError('no case named $functionName in the fixture');
}

Future<List<LintViolation>> _lint({
  List<String>? pathMarkers,
  String fileName = 'foo_screen.dart',
}) async {
  final Directory root = Directory.systemTemp.createTempSync(
    'avoid_hardcoded_color_',
  );
  addTearDown(() => root.deleteSync(recursive: true));

  File(p.join(root.path, 'stubs.dart')).writeAsStringSync(_stubs);
  final String subject = p.join(root.path, fileName);
  File(subject).writeAsStringSync(_fixture);

  final AnalysisContextCollection collection = AnalysisContextCollection(
    includedPaths: <String>[root.path],
  );
  final SomeResolvedUnitResult result = await collection
      .contextFor(subject)
      .currentSession
      .getResolvedUnit(subject);
  if (result is! ResolvedUnitResult) {
    fail('fixture did not resolve — every rule would report nothing');
  }

  final AvoidHardcodedColor rule = AvoidHardcodedColor(
    pathMarkers: pathMarkers,
  );
  final LintVisitor visitor = rule.createVisitor(
    fileName,
    result.lineInfo,
    result.content,
  );
  result.unit.accept(visitor);
  return visitor.violations;
}

Future<Set<int>> _reportedLines({List<String>? pathMarkers}) async =>
    (await _lint(
      pathMarkers: pathMarkers,
    )).map((LintViolation v) => v.line).toSet();

void main() {
  test('a colour stated in the source is reported', () async {
    final Set<int> lines = await _reportedLines();
    for (final String name in <String>[
      'literal',
      'fromArgb',
      'fromRgbo',
      'parenthesised',
      'negative',
      'materialConstant',
      'opacity',
    ]) {
      expect(lines, contains(_lineOf(name)), reason: '$name should report');
    }
  });

  test('a colour the code did not write down is left alone', () async {
    // The case this distinction exists for: a tag's colour is picked by the
    // user off a colour wheel and stored as an ARGB integer. There is no theme
    // role it could have used instead, so a report here names no fix.
    final Set<int> lines = await _reportedLines();
    for (final String name in <String>[
      'stored',
      'parsed',
      'mixed',
      // Already centralised by having a name; whatever is worth arguing about
      // it, the argument does not belong at this call site.
      'namedConstant',
      // The rule cannot evaluate arithmetic. Lenient on purpose: the miss is a
      // colour someone obscured deliberately, while a false report has no fix.
      'arithmetic',
    ]) {
      expect(
        lines,
        isNot(contains(_lineOf(name))),
        reason: '$name should not report',
      );
    }
  });

  test('withValues is the replacement, not another violation', () async {
    expect(await _reportedLines(), isNot(contains(_lineOf('values'))));
  });

  test('nothing outside the fixture is reported', () async {
    // Guards the line-based assertions above: an extra report on a line no
    // case owns would otherwise pass every one of them.
    final Set<int> expected = <int>{
      for (final String name in <String>[
        'literal',
        'fromArgb',
        'fromRgbo',
        'parenthesised',
        'negative',
        'materialConstant',
        'opacity',
      ])
        _lineOf(name),
    };
    expect(await _reportedLines(), expected);
  });

  group('pathMarkers', () {
    test('empty means the whole tree', () async {
      expect(await _reportedLines(), isNotEmpty);
    });

    test('a path outside the markers is not visited', () async {
      expect(
        await _reportedLines(pathMarkers: <String>['/presentation/']),
        isEmpty,
      );
    });
  });
}
