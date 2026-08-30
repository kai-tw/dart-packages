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

  /// Runs the command to completion and returns its exit code.
  Future<int> run() async {
    final ProcessResult result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
    return result.exitCode;
  }

  @override
  String toString() => '$executable ${arguments.join(' ')}';
}
