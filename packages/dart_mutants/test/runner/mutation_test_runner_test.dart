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

  // no_mutants.dart: nothing any operator here touches at all — a file
  // that is fully covered but produces zero candidates.
  File(
    p.join(dir.path, 'lib', 'no_mutants.dart'),
  ).writeAsStringSync('String shout(String s) => s.toUpperCase();\n');
  File(p.join(dir.path, 'test', 'no_mutants_test.dart')).writeAsStringSync('''
import 'package:fixture/no_mutants.dart';
import 'package:test/test.dart';

void main() {
  test('shouts', () => expect(shout('hi'), 'HI'));
}
''');

  // hangs.dart: the original always takes the safe path (a real assertion
  // covers exactly that), but swapping the ternary's branches routes into a
  // genuine, synchronous, non-yielding infinite loop — the shape no
  // event-loop-based test timeout can preempt.
  File(p.join(dir.path, 'lib', 'hangs.dart')).writeAsStringSync('''
String process(bool takeSafePath) => takeSafePath ? _safe() : _hang();

String _safe() => 'ok';

String _hang() {
  // ignore: literal_only_boolean_expressions
  while (true) {}
}
''');
  File(p.join(dir.path, 'test', 'hangs_test.dart')).writeAsStringSync('''
import 'package:fixture/hangs.dart';
import 'package:test/test.dart';

void main() {
  test('takes the safe path', () => expect(process(true), 'ok'));
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
  // Short on purpose: every mutant in this fixture except hangs.dart's
  // finishes near-instantly, and that one is specifically designed to
  // never finish at all — a long timeout would only make this suite slower
  // without testing anything a short one does not already cover.
  mutantTimeout: const Duration(seconds: 5),
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
        p.join(dir.path, 'lib', 'no_mutants.dart'),
        p.join(dir.path, 'lib', 'hangs.dart'),
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

    test(
      '[boundary] a file with zero candidate mutants still appears in the '
      'report, at total 0 — "no mutants" and "not scanned" must stay '
      'distinguishable to a caller',
      () {
        final FileMutationReport f = _reportFor(report, 'no_mutants.dart');
        expect(f.total, 0);
        expect(f.detectionRate, isNull);
        expect(f.detected, 0);
        expect(f.undetected, 0);
        expect(f.invalid, 0);
        expect(f.timedOut, 0);
      },
    );

    test(
      '[boundary] a mutant that hangs the test command is timedOut, not '
      'detected — a hang is not the same evidence as an assertion actually '
      'catching the wrong output, even though both make the process exit '
      'non-zero-shaped',
      () {
        final FileMutationReport f = _reportFor(report, 'hangs.dart');
        expect(f.timedOut, 1);
        expect(f.detected, 0);
        expect(f.undetected, 0);
        expect(f.invalid, 0);
        expect(f.total, 0, reason: 'timedOut is excluded from the score');
      },
    );

    test(
      '[partition] a hung mutant still gets its file restored — the kill '
      'happens in _runOne\'s try block, and restore runs in its finally '
      'regardless',
      () {
        expect(
          File(p.join(dir.path, 'lib', 'hangs.dart')).readAsStringSync(),
          contains('takeSafePath ? _safe() : _hang()'),
        );
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
