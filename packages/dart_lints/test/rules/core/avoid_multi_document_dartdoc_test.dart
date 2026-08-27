import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dart_lints/src/lint_rule_base.dart';
import 'package:dart_lints/src/rules/core/avoid_multi_document_dartdoc.dart';
import 'package:test/test.dart';

/// Parses [source] syntactically and runs the rule's visitor over it.
List<LintViolation> _lint(String source) {
  final ParseStringResult result = parseString(
    content: source,
    throwIfDiagnostics: false,
  );
  final AvoidMultiDocumentDartdoc rule = AvoidMultiDocumentDartdoc();
  final LintVisitor visitor = rule.createVisitor(
    'lib/foo.dart',
    result.lineInfo,
    source,
  );
  result.unit.accept(visitor);
  return visitor.violations;
}

void main() {
  group('a heading inside a dartdoc block is flagged', () {
    test('[boundary] `## ` heading — the shipped shape', () {
      expect(
        _lint('/// Summary.\n/// ## Retry policy\n/// Details.\nclass C {}'),
        hasLength(1),
      );
    });

    test('[partition] a deeper heading (`### `) also counts', () {
      expect(
        _lint('/// Summary.\n/// ### Retry policy\nclass C {}'),
        hasLength(1),
      );
    });

    test('[partition] no space required after the hashes at end of line', () {
      expect(_lint('/// Summary.\n/// ##\nclass C {}'), hasLength(1));
    });

    test('[error-guessing] a heading before any declaration', () {
      expect(_lint('/// ## Overview\n/// text\nint x = 1;'), hasLength(1));
    });

    test('[error-guessing] only the first heading in a block is reported', () {
      expect(
        _lint(
          '/// ## First\n/// text\n/// ## Second\n/// text\nclass C {}',
        ),
        hasLength(1),
      );
    });

    test(
      '[error-guessing] two separate declarations each with their own '
      'heading are both reported',
      () {
        expect(
          _lint(
            '/// ## A\nclass C {}\n\n/// ## B\nclass D {}',
          ),
          hasLength(2),
        );
      },
    );
  });

  group('a plain multi-paragraph dartdoc is left alone', () {
    test('[boundary] an ordinary long dartdoc with no heading', () {
      expect(
        _lint(
          '/// Summary.\n///\n/// More detail on a second paragraph.\n'
          '/// And a third one, still no heading anywhere in sight.\n'
          'class C {}',
        ),
        isEmpty,
      );
    });

    test('[partition] a single `#` is not a heading — reserved for the '
        "block's own one-line summary, never a section marker", () {
      expect(_lint('/// Summary.\n/// # Not a heading\nclass C {}'), isEmpty);
    });

    test('[partition] `####text` with no space after the hashes is not a '
        'heading, matching CommonMark\'s own ATX rule', () {
      expect(_lint('/// Summary.\n/// ####text\nclass C {}'), isEmpty);
    });

    test('[partition] a bare `//` comment is not dartdoc', () {
      expect(_lint('// ## Not dartdoc\nclass C {}'), isEmpty);
    });

    test('[partition] `////` is a commented-out doc line, not dartdoc', () {
      expect(_lint('//// ## Disabled\nclass C {}'), isEmpty);
    });

    test(
      '[boundary] a STRING LITERAL holding heading-shaped text is not '
      'dartdoc — this is why the rule walks tokens instead of raw source',
      () {
        expect(
          _lint("const String s = '/// ## Not a real heading';"),
          isEmpty,
        );
      },
    );

    test(
      '[partition] a heading separated from the doc block by a blank line '
      'is a different, shorter block, not part of the flagged one',
      () {
        expect(
          _lint(
            '/// ## Orphaned heading\n\n/// Actual doc, no heading.\n'
            'class C {}',
          ),
          hasLength(1),
        );
      },
    );
  });
}
