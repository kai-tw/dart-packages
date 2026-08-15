import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dart_lints/src/lint_rule_base.dart';
import 'package:dart_lints/src/rules/clean_arch/avoid_shared_preferences_outside_owner.dart';
import 'package:test/test.dart';

const String _import =
    "import 'package:shared_preferences/shared_preferences.dart';";

List<LintViolation> _lint(
  String source, {
  String path = 'lib/features/sync/sync_controller.dart',
  List<String>? ownerPaths,
}) {
  final ParseStringResult result = parseString(
    content: source,
    throwIfDiagnostics: false,
  );
  final AvoidSharedPreferencesOutsideOwner rule =
      AvoidSharedPreferencesOutsideOwner(ownerPaths: ownerPaths);
  final LintVisitor visitor = rule.createVisitor(path, result.lineInfo, source);
  result.unit.accept(visitor);
  return visitor.violations;
}

void main() {
  group('ownerPaths', () {
    test('a file under an owner path may import it', () {
      expect(
        _lint(
          _import,
          path: 'lib/core/preferences/preference_providers.dart',
          ownerPaths: <String>['core/preferences/'],
        ),
        isEmpty,
      );
    });

    test('a file outside every owner path may not', () {
      expect(
        _lint(_import, ownerPaths: <String>['core/preferences/']),
        hasLength(1),
      );
    });

    test('several owners are allowed, and a file need match only one', () {
      const List<String> owners = <String>[
        'features/preference/',
        'features/migration/processes/',
        'lib/main.dart',
      ];
      expect(
        _lint(
          _import,
          path: 'lib/features/migration/processes/v1/migrate.dart',
          ownerPaths: owners,
        ),
        isEmpty,
      );
      expect(
        _lint(_import, path: 'lib/main.dart', ownerPaths: owners),
        isEmpty,
      );
      expect(_lint(_import, ownerPaths: owners), hasLength(1));
    });

    // The alternative default — unconfigured means allow everything — would let
    // an enabled rule report success while inert, which is the one failure a
    // linter cannot report about itself.
    test('unconfigured reports every import rather than none', () {
      expect(
        _lint(
          _import,
          path: 'lib/core/preferences/preference_providers.dart',
        ),
        hasLength(1),
      );
    });
  });

  group('what counts as the import', () {
    test('any library within the package is matched, not just the entry', () {
      expect(
        _lint(
          "import 'package:shared_preferences/util/legacy_to_async_migration_util.dart';",
          ownerPaths: <String>['core/preferences/'],
        ),
        hasLength(1),
      );
    });

    test('a package whose name merely starts the same is not matched', () {
      expect(
        _lint(
          "import 'package:shared_preferences_platform_interface/types.dart';",
          ownerPaths: <String>['core/preferences/'],
        ),
        isEmpty,
        reason:
            'the prefix test ends at the slash, so a sibling package is a '
            'different package',
      );
    });

    test('an unrelated import in a non-owner file is left alone', () {
      expect(
        _lint("import 'package:flutter/material.dart';"),
        isEmpty,
      );
    });
  });
}
