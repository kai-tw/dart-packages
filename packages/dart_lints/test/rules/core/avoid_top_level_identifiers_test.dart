import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dart_lints/src/lint_rule_base.dart';
import 'package:dart_lints/src/rules/core/avoid_top_level_identifiers.dart';
import 'package:test/test.dart';

List<LintViolation> _lint(
  String source, {
  String path = 'lib/features/foo/foo_service.dart',
  String? scope,
  List<String>? exemptFiles,
  List<String>? exemptAnnotations,
  List<String>? exemptTypeSuffixes,
}) {
  final ParseStringResult result = parseString(
    content: source,
    throwIfDiagnostics: false,
  );
  final AvoidTopLevelIdentifiers rule = AvoidTopLevelIdentifiers(
    scope: scope,
    exemptFiles: exemptFiles,
    exemptAnnotations: exemptAnnotations,
    exemptTypeSuffixes: exemptTypeSuffixes,
  );
  final LintVisitor visitor = rule.createVisitor(path, result.lineInfo, source);
  result.unit.accept(visitor);
  return visitor.violations;
}

void main() {
  group('default (app scope)', () {
    test('flags a top-level function and a top-level variable', () {
      expect(_lint('int add(int a, int b) => a + b;'), hasLength(1));
      expect(_lint('const int limit = 3;'), hasLength(1));
    });

    test('a class member is not top-level', () {
      expect(_lint('class A { static int add() => 1; }'), isEmpty);
    });
  });

  group('scope: library', () {
    // The rule is disabled outright, not narrowed. Its premise — a top-level
    // name is a global nobody asked for — is false where those names are the
    // package's API, and that applies to private helpers in the same file too.
    test('reports nothing at all, public or private', () {
      const String source = '''
int publicHelper() => 1;
int _privateHelper() => 2;
const int _limit = 3;
''';
      expect(_lint(source), hasLength(3));
      expect(_lint(source, scope: 'library'), isEmpty);
    });

    test('an unrecognised scope value falls back to app rather than off', () {
      // Silently disabling on a typo would be the one failure a linter cannot
      // report about itself.
      expect(_lint('int f() => 1;', scope: 'lbrary'), hasLength(1));
    });
  });

  group('scope is the configuration\'s job, not the rule\'s', () {
    // The rule used to carry its own test-path predicate, a second definition
    // of "what is a test file" beside the one the config declares as an area.
    // Two copies drift, and nothing catches the disagreement — so the rule now
    // reports wherever it runs and a project disables it in its test area.
    test('reports in a test-tree path — the rule no longer self-excludes', () {
      expect(
        _lint('int helper() => 1;', path: 'test/features/foo_test.dart'),
        hasLength(1),
      );
    });

    test('reports identically whatever the path', () {
      expect(
        _lint('int helper() => 1;', path: 'integration_test/reader_test.dart'),
        hasLength(1),
      );
    });
  });

  group('main is exempt by what it is, not by where it lives', () {
    // `main` must be a top-level function for the language to find it, so
    // reporting it is advice the author cannot take. Keying that on the
    // filename `main.dart` was a path convention wearing a language rule's
    // clothes — it missed every script in bin/ and every test file, and it
    // exempted any file that merely happened to be named main.dart.
    test('exempt in an app entry point', () {
      expect(_lint('void main() {}', path: 'lib/main.dart'), isEmpty);
    });

    test('exempt in a script whose file is not called main.dart', () {
      expect(_lint('void main() {}', path: 'bin/generate.dart'), isEmpty);
    });

    test('exempt in a test file', () {
      expect(
        _lint('void main() {}', path: 'test/features/foo_test.dart'),
        isEmpty,
      );
    });

    test('an async entry point is the same declaration', () {
      expect(
        _lint('Future<void> main() async {}', path: 'bin/generate.dart'),
        isEmpty,
      );
    });

    test('only main itself — a sibling top-level function still reports', () {
      final List<LintViolation> violations = _lint(
        'void main() {}\nint helper() => 1;',
        path: 'lib/main.dart',
      );
      expect(violations, hasLength(1));
      expect(violations.single.message, contains('helper'));
    });
  });

  group('exemptFiles', () {
    test('matches on a path suffix', () {
      expect(
        _lint(
          'void configure() {}',
          path: 'lib/core/di/service_locator.dart',
          exemptFiles: <String>['core/di/service_locator.dart'],
        ),
        isEmpty,
      );
    });

    test('an unrelated file is still reported', () {
      expect(
        _lint(
          'void configure() {}',
          path: 'lib/features/foo/foo_service.dart',
          exemptFiles: <String>['core/di/service_locator.dart'],
        ),
        hasLength(1),
      );
    });
  });

  group(
    'exemptAnnotations — declarations a framework requires to be top-level',
    () {
      const String riverpodProvider = '''
@riverpod
int counter(CounterRef ref) => 0;
''';

      test('without the option the provider is reported', () {
        // This is the state that blocks a Riverpod project: the suggested fix
        // (move it into a class) stops the generator emitting the provider.
        expect(_lint(riverpodProvider), hasLength(1));
      });

      test('the annotation exempts it', () {
        expect(
          _lint(riverpodProvider, exemptAnnotations: <String>['riverpod']),
          isEmpty,
        );
      });

      test('exemption is per declaration, not per file', () {
        const String mixed = '''
@riverpod
int counter(CounterRef ref) => 0;

int strayHelper() => 1;
''';
        final List<LintViolation> violations = _lint(
          mixed,
          exemptAnnotations: <String>['riverpod'],
        );
        expect(violations, hasLength(1));
        expect(violations.single.message, contains('strayHelper'));
      });

      test('a different annotation does not exempt', () {
        expect(
          _lint(riverpodProvider, exemptAnnotations: <String>['Riverpod']),
          hasLength(1),
        );
      });
    },
  );

  group('exemptTypeSuffixes — the hand-written provider counterpart', () {
    const String handWritten = 'final Provider<int> countProvider = _make();';

    test('without the option it is reported', () {
      expect(_lint(handWritten), hasLength(1));
    });

    test('a matching declared type exempts it', () {
      expect(
        _lint(handWritten, exemptTypeSuffixes: <String>['Provider']),
        isEmpty,
      );
    });

    test('the suffix matches the declared TYPE, not the variable name', () {
      // `countProvider` ends in Provider; its type does not. Keying on the name
      // would let any variable opt itself out by being named well.
      expect(
        _lint(
          'final int countProvider = 1;',
          exemptTypeSuffixes: <String>['Provider'],
        ),
        hasLength(1),
      );
    });

    test('a function is never exempted by a type suffix', () {
      expect(
        _lint(
          'int makeProvider() => 1;',
          exemptTypeSuffixes: <String>['Provider'],
        ),
        hasLength(1),
      );
    });
  });
}
