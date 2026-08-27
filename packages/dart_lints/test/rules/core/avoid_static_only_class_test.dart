import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dart_lints/src/lint_rule_base.dart';
import 'package:dart_lints/src/rules/core/avoid_static_only_class.dart';
import 'package:test/test.dart';

/// Parses [source] syntactically and runs the rule's visitor over it.
List<LintViolation> _lint(
  String source, {
  String path = 'lib/foo.dart',
  List<String> exemptFiles = const <String>[],
}) {
  final ParseStringResult result = parseString(
    content: source,
    throwIfDiagnostics: false,
  );
  final AvoidStaticOnlyClass rule = AvoidStaticOnlyClass(
    exemptFiles: exemptFiles,
  );
  final LintVisitor visitor = rule.createVisitor(path, result.lineInfo, source);
  result.unit.accept(visitor);
  return visitor.violations;
}

void main() {
  group('static-only classes the stock rule misses are flagged', () {
    test(
      '[boundary] a private constructor blocking instantiation — the most '
      'common shape, and exactly what the stock rule exempts',
      () {
        expect(
          _lint('''
class LocaleUtils {
  LocaleUtils._();
  static String normalize(String tag) => tag.toLowerCase();
}
'''),
          hasLength(1),
        );
      },
    );

    test(
      '[boundary] abstract WITH a redundant constructor is still reported — '
      'the constructor does nothing on an already-uninstantiable class',
      () {
        expect(
          _lint('''
abstract final class DebounceKeys {
  DebounceKeys._();
  static const search = 'search';
}
'''),
          hasLength(1),
        );
      },
    );

    test('[partition] sealed', () {
      expect(_lint('sealed class X { static void a() {} }'), hasLength(1));
    });

    test('[partition] base', () {
      expect(_lint('base class X { static void a() {} }'), hasLength(1));
    });

    test('[partition] a plain class with no constructor at all', () {
      expect(_lint('class X { static void a() {} }'), hasLength(1));
    });

    test('[partition] a const private constructor', () {
      expect(
        _lint('class X { const X._(); static void a() {} }'),
        hasLength(1),
      );
    });

    test('[partition] a factory constructor alongside statics', () {
      expect(
        _lint(
          'class X { factory X._make() => X._(); X._(); '
          'static void a() {} }',
        ),
        hasLength(1),
      );
    });

    test('[partition] a static getter counts as a static member', () {
      expect(_lint('class X { X._(); static int get a => 1; }'), hasLength(1));
    });

    test(
      '[error-guessing] two static-only classes in one file both report',
      () {
        expect(
          _lint(
            'class X { X._(); static void a() {} }\n'
            'class Y { static void b() {} }',
          ),
          hasLength(2),
        );
      },
    );
  });

  group('classes that are not this antipattern are left alone', () {
    test(
      '[boundary] bare abstract-final with no constructor — Effective '
      "Dart's own namespace idiom, already uninstantiable with nothing "
      'left to close',
      () {
        expect(
          _lint('''
abstract final class DebounceKeys {
  static const search = 'search';
  static const sync = 'sync';
}
'''),
          isEmpty,
        );
      },
    );

    test('[partition] plain abstract (no final), no constructor', () {
      expect(_lint('abstract class X { static void a() {} }'), isEmpty);
    });

    test('[boundary] a normal class mixing instance and static members', () {
      expect(
        _lint('class X { int a = 1; static void b() {} }'),
        isEmpty,
      );
    });

    test('[partition] every member is an instance member', () {
      expect(_lint('class X { void a() {} }'), isEmpty);
    });

    test('[partition] an empty class — nothing to move anywhere', () {
      expect(_lint('class X {}'), isEmpty);
    });

    test(
      '[partition] only a private constructor, no other members — not a '
      'namespace, just an uninstantiable marker',
      () {
        expect(_lint('class X { X._(); }'), isEmpty);
      },
    );

    test('[partition] a single instance field among statics', () {
      expect(
        _lint('class X { X._(); int a = 1; static void b() {} }'),
        isEmpty,
      );
    });
  });

  group('exemptFiles', () {
    test(
      '[boundary] flutterfire regenerates this file, so it is not the '
      "author's to restructure",
      () {
        expect(
          _lint(
            'class DefaultFirebaseOptions { '
            'DefaultFirebaseOptions._(); '
            'static const x = 1; }',
            path: 'lib/firebase_options.dart',
            exemptFiles: <String>['firebase_options.dart'],
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
            'class X { X._(); static void a() {} }',
            path: 'lib/core/my_firebase_options_helper.dart',
            exemptFiles: <String>['firebase_options.dart'],
          ),
          hasLength(1),
        );
      },
    );
  });
}
