import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dart_lints/src/lint_rule_base.dart';
import 'package:dart_lints/src/rules/clean_arch/avoid_layer_violation.dart';
import 'package:test/test.dart';

/// Parses [source] syntactically and runs the rule's visitor over it, as if
/// [path] were the file being linted.
List<LintViolation> _lint(
  String source, {
  required String path,
  String? packageName,
  List<String>? exemptFiles,
}) {
  final ParseStringResult result = parseString(
    content: source,
    throwIfDiagnostics: false,
  );
  final AvoidLayerViolation rule = AvoidLayerViolation(
    packageName: packageName,
    exemptFiles: exemptFiles,
  );
  final LintVisitor visitor = rule.createVisitor(path, result.lineInfo, source);
  result.unit.accept(visitor);
  return visitor.violations;
}

void main() {
  group(
    'package: imports — the shape every project using '
    'always_use_package_imports actually writes',
    () {
      test('a self import crossing a forbidden direction is caught', () {
        expect(
          _lint(
            "import 'package:myapp/features/x/data/x_dto.dart';",
            path: 'lib/features/x/domain/x_repository.dart',
            packageName: 'myapp',
          ),
          hasLength(1),
        );
      });

      test('a self import in an allowed direction is not caught', () {
        expect(
          _lint(
            "import 'package:myapp/features/x/domain/x.dart';",
            path: 'lib/features/x/data/x_dto.dart',
            packageName: 'myapp',
          ),
          isEmpty,
        );
      });

      test(
        'an external package sharing the layer vocabulary by coincidence '
        'is left alone',
        () {
          expect(
            _lint(
              "import 'package:some_dep/features/x/data/x_dto.dart';",
              path: 'lib/features/x/domain/x_repository.dart',
              packageName: 'myapp',
            ),
            isEmpty,
          );
        },
      );

      test(
        '[the bug this rule used to have] without packageName configured, '
        'a self package: import silently passes — this is why '
        'DartLintsConfigLoader fills it in from pubspec.yaml by default',
        () {
          expect(
            _lint(
              "import 'package:myapp/features/x/data/x_dto.dart';",
              path: 'lib/features/x/domain/x_repository.dart',
            ),
            isEmpty,
          );
        },
      );

      test(
        'a self import with no layer segment resolves to null, not caught',
        () {
          expect(
            _lint(
              "import 'package:myapp/core/http/client.dart';",
              path: 'lib/features/x/domain/x_repository.dart',
              packageName: 'myapp',
            ),
            isEmpty,
          );
        },
      );
    },
  );

  group('relative imports', () {
    test('crossing a forbidden direction is caught', () {
      expect(
        _lint(
          "import '../data/x_dto.dart';",
          path: 'lib/features/x/domain/x_repository.dart',
        ),
        hasLength(1),
      );
    });

    test('within the same layer is not caught', () {
      expect(
        _lint(
          "import 'x_entity.dart';",
          path: 'lib/features/x/domain/x_repository.dart',
        ),
        isEmpty,
      );
    });

    test('crossing features but not layers is not caught', () {
      expect(
        _lint(
          "import '../../y/domain/y.dart';",
          path: 'lib/features/x/domain/x_repository.dart',
        ),
        isEmpty,
      );
    });
  });

  group('imports this rule has no opinion about', () {
    test('dart: is never a layer violation', () {
      expect(
        _lint(
          "import 'dart:async';",
          path: 'lib/features/x/domain/x_repository.dart',
        ),
        isEmpty,
      );
    });
  });

  group('exemptFiles', () {
    test('a wiring container crosses every layer by design', () {
      expect(
        _lint(
          "import 'package:myapp/features/x/data/x_dto.dart';",
          path: 'lib/features/x/domain/setup_dependencies.dart',
          packageName: 'myapp',
          exemptFiles: <String>['setup_dependencies.dart'],
        ),
        isEmpty,
      );
    });
  });
}
