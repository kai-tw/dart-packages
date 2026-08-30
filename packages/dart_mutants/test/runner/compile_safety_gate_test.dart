import 'dart:io';

import 'package:dart_mutants/src/runner/compile_safety_gate.dart';
import 'package:dart_mutants/src/runner/process_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// These exercise the real `dart analyze` subprocess, not a mock — the exit
/// codes this gate depends on (0 clean, 2 warnings-only, 3 has an error) are
/// empirically confirmed against a real Dart SDK, not assumed from
/// documentation, precisely because getting this wrong is the single most
/// dangerous failure mode this whole package has (see the class doc on
/// [CompileSafetyGate]).
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('compile_safety_gate_test_');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  CompileSafetyGate gate() =>
      const CompileSafetyGate(ProcessCommand('dart', <String>['analyze']));

  test('[partition] a clean file compiles', () async {
    final File file = File(p.join(tempDir.path, 'clean.dart'))
      ..writeAsStringSync('int f() => 1;\n');
    expect(await gate().compiles(file.path), isTrue);
  });

  test('[boundary] a file with only a warning still counts as compiling', () async {
    // An unused import is a warning, not an error — the file still runs.
    final File file = File(p.join(tempDir.path, 'warn.dart'))
      ..writeAsStringSync("import 'dart:math';\n\nint f() => 1;\n");
    expect(await gate().compiles(file.path), isTrue);
  });

  test('[partition] a genuine type error does not compile', () async {
    final File file = File(p.join(tempDir.path, 'broken.dart'))
      ..writeAsStringSync('int f() => "not an int";\n');
    expect(await gate().compiles(file.path), isFalse);
  });

  test(
    '[boundary] a file with both a warning and an error is rejected — the '
    'error dominates, not "any diagnostic at all"',
    () async {
      final File file = File(p.join(tempDir.path, 'both.dart'))
        ..writeAsStringSync(
          "import 'dart:math';\n\nint f() => \"not an int\";\n",
        );
      expect(await gate().compiles(file.path), isFalse);
    },
  );
}
