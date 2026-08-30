import 'package:dart_mutants/src/runner/process_command.dart';
import 'package:test/test.dart';

void main() {
  test(
    '[partition] a command that finishes before the timeout returns its '
    'exit code',
    () async {
      const ProcessCommand command = ProcessCommand('dart', <String>[
        '--version',
      ]);
      expect(
        await command.run(timeout: const Duration(seconds: 30)),
        0,
      );
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
}
