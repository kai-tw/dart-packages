import 'dart:async';
import 'dart:io';

import 'package:dart_mutants/src/runner/process_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A shell that backgrounds a child and waits, recording the child's pid so a
/// test can ask about it afterwards. It stands in for the shape that caused
/// the leak: `flutter test` is three processes, not one.
String _spawnerScript(String pidFile) =>
    'sleep 120 & echo \$! > "$pidFile"; wait';

bool _isAlive(int pid) =>
    (Process.runSync('ps', <String>['-o', 'pid=', '-p', '$pid']).stdout
            as String)
        .trim()
        .isNotEmpty;

void main() {
  test(
    '[partition] a command that finishes before the timeout returns its '
    'exit code',
    () async {
      const ProcessCommand command = ProcessCommand('dart', <String>[
        '--version',
      ]);
      expect(await command.run(timeout: const Duration(seconds: 30)), 0);
    },
  );

  test(
    '[boundary] a command that outlives the timeout is killed, returns '
    'null, and does not make the caller actually wait out its own runtime',
    () async {
      const ProcessCommand command = ProcessCommand('sleep', <String>['30']);
      final Stopwatch stopwatch = Stopwatch()..start();

      final int? exitCode = await command.run(
        timeout: const Duration(seconds: 1),
      );

      stopwatch.stop();
      expect(exitCode, isNull);
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 10)),
        reason: 'the 30s sleep must have actually been killed, not awaited',
      );
    },
  );

  test('[partition] no timeout given waits for the real exit code', () async {
    const ProcessCommand command = ProcessCommand('dart', <String>[
      '--version',
    ]);
    expect(await command.run(), 0);
  });

  group('the timeout kills the process TREE, not just the direct child', () {
    // The defect these guard: `flutter test` is three processes — the wrapper
    // spawns a runtime, which spawns the engine that actually runs the test —
    // and a SIGKILL to the wrapper does not propagate downward. POSIX
    // reparents an orphan to init rather than killing it, so the engine
    // survived, went on executing the mutant's infinite loop, and nothing
    // would ever reap it. Measured at roughly 130 MB/s of growth, forever,
    // from ONE timed-out mutant; two runs exhausted a workstation's memory.
    late Directory dir;
    late String pidFile;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('tree_kill_test_');
      pidFile = p.join(dir.path, 'grandchild.pid');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    Future<int> recordedGrandchildPid() async {
      final File file = File(pidFile);
      for (int i = 0; i < 50 && !file.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return int.parse(file.readAsStringSync().trim());
    }

    test(
      '[boundary] the fixture really does orphan — killing only the direct '
      'child leaves the grandchild running',
      () async {
        // Not a test of the operating system. It is what makes the assertion
        // in the next test non-vacuous: without it, a fixture that never
        // spawned a grandchild at all would pass that test for the wrong
        // reason, and the guard would quietly stop guarding anything.
        final Process process = await Process.start('/bin/sh', <String>[
          '-c',
          _spawnerScript(pidFile),
        ]);
        unawaited(process.stdout.drain<void>());
        unawaited(process.stderr.drain<void>());
        final int grandchild = await recordedGrandchildPid();

        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(
          _isAlive(grandchild),
          isTrue,
          reason: 'the single-process kill is exactly the leak being fixed',
        );
        Process.killPid(grandchild, ProcessSignal.sigkill);
      },
    );

    test('[boundary] the timeout leaves no survivor behind', () async {
      final ProcessCommand command = ProcessCommand('/bin/sh', <String>[
        '-c',
        _spawnerScript(pidFile),
      ]);

      final int? exitCode = await command.run(
        timeout: const Duration(seconds: 2),
      );

      expect(exitCode, isNull, reason: 'the fixture must have timed out');
      final int grandchild = await recordedGrandchildPid();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        _isAlive(grandchild),
        isFalse,
        reason:
            'a surviving grandchild is the unbounded leak: it outlives the '
            'run that created it and nothing will ever reap it',
      );
    });
  });
}
