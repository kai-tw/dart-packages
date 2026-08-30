import 'dart:io';

import 'package:dart_mutants/src/runner/compile_safety_gate.dart';
import 'package:dart_mutants/src/runner/file_mutation_report.dart';
import 'package:dart_mutants/src/runner/mutation_run_report.dart';
import 'package:dart_mutants/src/runner/mutation_test_runner.dart';
import 'package:dart_mutants/src/runner/process_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A real temp Dart package — `pubspec.yaml`, `dart pub get`, real `lib/`
/// and `test/` files — because the property under test (a mutant that
/// fails to compile must never read as "detected") only actually exists at
/// the boundary between three real subprocesses: `dart analyze`, `dart
/// test`, and this package's own file-mutation logic. A mock of any one of
/// them would test that the mock behaves as scripted, not that the real
/// pipeline gets the classification right.
Future<Directory> _fixturePackage() async {
  final Directory dir = Directory.systemTemp.createTempSync(
    'mutation_test_runner_test_',
  );
  File(
    p.join(dir.path, 'pubspec.yaml'),
  ).writeAsStringSync('''
name: fixture
environment:
  sdk: ^3.8.0
dev_dependencies:
  test: ^1.25.0
''');
  Directory(p.join(dir.path, 'lib')).createSync();
  Directory(p.join(dir.path, 'test')).createSync();

  // detected.dart: a ternary fully covered both ways — swapping it must
  // make at least one assertion fail.
  File(p.join(dir.path, 'lib', 'detected.dart')).writeAsStringSync(
    "String classify(bool isPositive) => isPositive ? 'positive' : 'negative';\n",
  );
  File(p.join(dir.path, 'test', 'detected_test.dart')).writeAsStringSync('''
import 'package:fixture/detected.dart';
import 'package:test/test.dart';

void main() {
  test('positive', () => expect(classify(true), 'positive'));
  test('negative', () => expect(classify(false), 'negative'));
}
''');

  // undetected.dart: a ternary no test ever calls at all — trivially, no
  // mutant on it can ever be caught.
  File(p.join(dir.path, 'lib', 'undetected.dart')).writeAsStringSync(
    "String classify(bool isPositive) => isPositive ? 'positive' : 'negative';\n",
  );
  File(p.join(dir.path, 'test', 'undetected_test.dart')).writeAsStringSync('''
void main() {}
''');

  // invalid.dart: a `??` whose "left alone" mutant is a guaranteed compile
  // error (String? assigned to an explicitly non-nullable String), and
  // whose "fallback alone" mutant compiles fine and is caught by the test.
  File(p.join(dir.path, 'lib', 'invalid.dart')).writeAsStringSync('''
String withDefault(String? a) {
  final String result = a ?? 'the default';
  return result;
}
''');
  File(p.join(dir.path, 'test', 'invalid_test.dart')).writeAsStringSync('''
import 'package:fixture/invalid.dart';
import 'package:test/test.dart';

void main() {
  test('uses the provided value when present', () {
    expect(withDefault('given'), 'given');
  });
}
''');

  final ProcessResult pubGet = await Process.run('dart', <String>[
    'pub',
    'get',
  ], workingDirectory: dir.path);
  if (pubGet.exitCode != 0) {
    throw StateError('dart pub get failed:\n${pubGet.stdout}\n${pubGet.stderr}');
  }
  return dir;
}

MutationTestRunner _runnerFor(Directory dir) => MutationTestRunner(
  testCommand: ProcessCommand('dart', <String>[
    'test',
  ], workingDirectory: dir.path),
  compileSafetyGate: const CompileSafetyGate(
    ProcessCommand('dart', <String>['analyze']),
  ),
);

FileMutationReport _reportFor(MutationRunReport report, String name) =>
    report.files.singleWhere(
      (FileMutationReport f) => p.basename(f.filePath) == name,
    );

void main() {
  group('a full run against a real package', () {
    late Directory dir;
    late MutationRunReport report;

    tearDownAll(() => dir.deleteSync(recursive: true));

    setUpAll(() async {
      dir = await _fixturePackage();
      report = await _runnerFor(dir).run(<String>[
        p.join(dir.path, 'lib', 'detected.dart'),
        p.join(dir.path, 'lib', 'undetected.dart'),
        p.join(dir.path, 'lib', 'invalid.dart'),
      ]);
    });

    test('[partition] does not abort — the baseline suite was green', () {
      expect(report.aborted, isFalse);
    });

    test(
      '[partition] a fully-covered ternary swap is detected',
      () {
        final FileMutationReport f = _reportFor(report, 'detected.dart');
        expect(f.detected, 1);
        expect(f.undetected, 0);
        expect(f.invalid, 0);
      },
    );

    test(
      '[partition] a never-called ternary swap is undetected, not invalid '
      '— it compiles fine, nothing just happens to run it',
      () {
        final FileMutationReport f = _reportFor(report, 'undetected.dart');
        expect(f.detected, 0);
        expect(f.undetected, 1);
        expect(f.invalid, 0);
      },
    );

    test(
      '[partition] a mutant that fails to compile is invalid, and does '
      'NOT inflate detected — this is the one failure mode the whole gate '
      'exists to prevent',
      () {
        final FileMutationReport f = _reportFor(report, 'invalid.dart');
        expect(f.invalid, 1, reason: 'the String?-into-String mutant');
        expect(
          f.detected,
          1,
          reason: 'the other mutant on this file compiles and is caught',
        );
        expect(f.undetected, 0);
      },
    );

    test('[partition] every mutated file ends the run back at its own original content', () {
      expect(
        File(p.join(dir.path, 'lib', 'detected.dart')).readAsStringSync(),
        "String classify(bool isPositive) => isPositive ? 'positive' : 'negative';\n",
      );
      expect(
        File(p.join(dir.path, 'lib', 'invalid.dart')).readAsStringSync(),
        contains("a ?? 'the default'"),
      );
    });
  });

  group('a red baseline', () {
    test(
      '[boundary] aborts before touching any file, rather than scoring '
      'against a suite that was already failing',
      () async {
        final Directory dir = await _fixturePackage();
        addTearDown(() => dir.deleteSync(recursive: true));
        File(p.join(dir.path, 'test', 'broken_test.dart')).writeAsStringSync(
          "import 'package:test/test.dart';\n\nvoid main() { test('x', () => throw Exception('always red')); }\n",
        );
        final String detectedBefore = File(
          p.join(dir.path, 'lib', 'detected.dart'),
        ).readAsStringSync();

        final MutationRunReport report = await _runnerFor(dir).run(<String>[
          p.join(dir.path, 'lib', 'detected.dart'),
        ]);

        expect(report.aborted, isTrue);
        expect(report.abortReason, contains('red'));
        expect(report.files, isEmpty);
        expect(
          File(p.join(dir.path, 'lib', 'detected.dart')).readAsStringSync(),
          detectedBefore,
        );
      },
    );
  });
}
