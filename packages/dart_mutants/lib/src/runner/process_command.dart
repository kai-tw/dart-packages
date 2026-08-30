import 'dart:async';
import 'dart:io';

/// One external command this package shells out to — the project's own test
/// command (`flutter test test/foo_test.dart`) or its analyzer
/// (`dart analyze` / `flutter analyze`). Neither is fixed: a Flutter package
/// has no `dart test` that works at all, and `dart_lints.yaml` already
/// established in this same workspace that the analyzer invocation itself
/// varies by project — this type exists so both are the caller's decision,
/// not this package's guess.
class ProcessCommand {
  const ProcessCommand(this.executable, this.arguments, {this.workingDirectory});

  final String executable;
  final List<String> arguments;

  /// Defaults to the current process's working directory when `null`.
  final String? workingDirectory;

  /// Runs the command to completion and returns its exit code, or `null` if
  /// it did not finish within [timeout].
  ///
  /// A mutant can turn a normal loop into an infinite one — the whole reason
  /// this exists. `package:test`'s own per-test timeout cannot be trusted to
  /// catch that: it is cooperative, built on the event loop, and a
  /// synchronous `while (true) {}` never yields to it at all, so the test
  /// framework's timeout never gets a chance to fire and this package's own
  /// `await` on the subprocess would hang forever. [timeout] is enforced
  /// from outside the subprocess instead — a `SIGKILL`, which cannot be
  /// blocked or ignored by whatever the child process is doing — so a
  /// mutant that hangs ends that one mutant's run, not the whole session.
  Future<int?> run({Duration? timeout}) async {
    final Process process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
    // The child's own output is not this package's concern, and an unread
    // pipe can fill up and deadlock the child — drain it unconditionally.
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());

    if (timeout == null) {
      return process.exitCode;
    }
    try {
      return await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode; // Reap it — otherwise it is left a zombie.
      return null;
    }
  }

  @override
  String toString() => '$executable ${arguments.join(' ')}';
}
