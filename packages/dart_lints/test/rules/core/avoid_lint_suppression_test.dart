import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dart_lints/src/lint_rule_base.dart';
import 'package:dart_lints/src/rules/core/avoid_lint_suppression.dart';
import 'package:test/test.dart';

/// Parses [source] syntactically and runs the rule's visitor over it.
///
/// [path] defaults to an app `lib/` file; the `generated-file exclusion` group
/// drives it to `firebase_options.dart` to exercise the other side of the gate.
///
/// Both exemption lists are supplied here rather than defaulted: the rule ships
/// with them empty, because an exemption is a claim about one project's code
/// and inheriting another project's would be silent.
List<LintViolation> _lint(
  String source, {
  String path = 'lib/features/foo/foo_page.dart',
  List<String> generatedFiles = const <String>['firebase_options.dart'],
  List<String> sanctionedSuppressions = const <String>[
    'app_theme.dart:deprecated_member_use',
    'known_locale.dart:constant_identifier_names',
  ],
}) {
  final ParseStringResult result = parseString(
    content: source,
    throwIfDiagnostics: false,
  );
  final AvoidLintSuppression rule = AvoidLintSuppression(
    generatedFiles: generatedFiles,
    sanctionedSuppressions: sanctionedSuppressions,
  );
  final LintVisitor visitor = rule.createVisitor(path, result.lineInfo, source);
  result.unit.accept(visitor);
  return visitor.violations;
}

void main() {
  group('suppressions are flagged', () {
    test(
      '[boundary] `// ignore:` before a declaration — the shipped shape',
      () {
        expect(
          _lint('// ignore: deprecated_member_use\nfinal int x = 1;'),
          hasLength(1),
        );
      },
    );

    test('[boundary] `// ignore_for_file:` header', () {
      expect(
        _lint('// ignore_for_file: lines_longer_than_80_chars\nint x = 1;'),
        hasLength(1),
      );
    });

    test('[partition] no space after the slashes', () {
      expect(_lint('//ignore: foo\nint x = 1;'), hasLength(1));
    });

    test('[partition] space before the colon', () {
      expect(_lint('// ignore : foo\nint x = 1;'), hasLength(1));
    });

    test('[error-guessing] the rule cannot suppress itself', () {
      expect(
        _lint('// ignore: avoid_lint_suppression\nint x = 1;'),
        hasLength(1),
      );
    });

    test('[partition] trailing suppression on the same line as code', () {
      expect(_lint('int x = 1; // ignore: foo'), hasLength(1));
    });

    test('[partition] every occurrence is reported, not just the first', () {
      expect(
        _lint('// ignore: a\nint x = 1;\n// ignore: b\nint y = 2;'),
        hasLength(2),
      );
    });
  });

  group('non-suppressions are left alone', () {
    test('[boundary] an ordinary comment', () {
      expect(_lint('// the cache is best-effort\nint x = 1;'), isEmpty);
    });

    test('[error-guessing] prose that merely contains the word', () {
      expect(
        _lint('// we deliberately ignore: nothing here\nint x = 1;'),
        isEmpty,
      );
    });

    test('[boundary] a STRING LITERAL holding the text is not a suppression — '
        'this is why the rule walks tokens instead of raw source', () {
      expect(
        _lint("const String s = '// ignore: deprecated_member_use';"),
        isEmpty,
      );
    });

    test('[partition] dartdoc is not an analyzer suppression', () {
      expect(_lint('/// ignore: foo\nint x = 1;'), isEmpty);
    });

    test('[partition] a block comment is not an analyzer suppression', () {
      expect(_lint('/* ignore: foo */\nint x = 1;'), isEmpty);
    });
  });

  group('generated-file exclusion', () {
    test(
      '[boundary] firebase_options.dart writes its own header each regen',
      () {
        expect(
          _lint(
            '// ignore_for_file: lines_longer_than_80_chars\nint x = 1;',
            path: 'lib/firebase_options.dart',
          ),
          isEmpty,
        );
      },
    );

    test(
      '[partition] a hand-written file with a similar name is NOT exempt',
      () {
        expect(
          _lint(
            '// ignore: foo\nint x = 1;',
            path: 'lib/core/my_firebase_options_helper.dart',
          ),
          hasLength(1),
        );
      },
    );
  });
  group('sanctioned exemptions — language/framework leaves no alternative', () {
    test('[boundary] the M3 year2023 flag ships deprecated', () {
      expect(
        _lint(
          '// ignore: deprecated_member_use\nfinal bool y = false;',
          path: 'lib/app/theme/app_theme.dart',
        ),
        isEmpty,
      );
    });

    test('[boundary] `is` is a reserved word, so Icelandic must be `is_`', () {
      expect(
        _lint(
          '// ignore: constant_identifier_names\nfinal int x = 1;',
          path: 'lib/features/locale_system/domain/entities/known_locale.dart',
        ),
        isEmpty,
      );
    });

    test('[error-guessing] the allowlist is per DIAGNOSTIC, not per file — '
        'a sanctioned file cannot suppress anything else', () {
      expect(
        _lint(
          '// ignore: avoid_hardcoded_color\nfinal int x = 1;',
          path: 'lib/app/theme/app_theme.dart',
        ),
        hasLength(1),
      );
    });
  });
}
