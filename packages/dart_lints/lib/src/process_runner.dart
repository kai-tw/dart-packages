import 'dart:io';

/// Runs an external process and reports what it printed.
///
/// Exists so the analyzer step is assertable without spawning anything: a test
/// substitutes a fake and checks the argv, which is the only way to notice a
/// dropped flag like `--fatal-infos`.
abstract class ProcessRunner {
  ProcessResult run(String executable, List<String> arguments);
}

class SystemProcessRunner implements ProcessRunner {
  const SystemProcessRunner();

  @override
  ProcessResult run(String executable, List<String> arguments) =>
      Process.runSync(executable, arguments, runInShell: true);
}
