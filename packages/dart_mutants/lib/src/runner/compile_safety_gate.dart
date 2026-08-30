import 'process_command.dart';

/// Whether a mutated file still compiles, checked before a mutant is ever
/// handed to the real test command.
///
/// This is the one thing this package cannot skip. An AST-legal edit is not
/// a type-legal one — swapping two ternary branches of different static
/// types, or borrowing a switch-expression arm's result whose type does not
/// fit the switch's own inferred type, both parse fine and both can fail to
/// compile. A test command that fails to even load a broken file still
/// exits non-zero, which — read naively as "the mutant was detected" —
/// makes the score go *up* for a file the mutation could not actually
/// exercise at all. That is the most dangerous failure shape this package
/// can have: a better-looking number sitting on top of nothing.
///
/// `dart analyze`'s exit code is the signal, empirically confirmed (not
/// assumed) against Dart's own SDK: `0` clean, `2` warnings only, `3` at
/// least one error. `2` is accepted — a mutation is not obliged to be
/// lint-clean, only to actually compile and run — and anything other than
/// `0`/`2` (`3`, or an unexpected code from a crashed/misconfigured
/// analyzer) is treated as *not* compiling. Failing closed here is
/// deliberate: the cost of wrongly discarding a valid mutant is a little
/// lost coverage, but the cost of wrongly accepting an invalid one is the
/// inflated-score failure mode above.
class CompileSafetyGate {
  const CompileSafetyGate(this.analyzeCommand);

  /// The project's analyzer invocation, e.g. `dart analyze` or
  /// `flutter analyze` — not fixed, for the same reason `dart_lints.yaml`
  /// already makes this configurable: a pure-Dart package and a Flutter
  /// package do not share one answer.
  final ProcessCommand analyzeCommand;

  static const Set<int> _compilingExitCodes = <int>{0, 2};

  /// Whether [filePath] — already mutated on disk — still compiles.
  Future<bool> compiles(String filePath) async {
    final ProcessCommand withTarget = ProcessCommand(
      analyzeCommand.executable,
      <String>[...analyzeCommand.arguments, filePath],
      workingDirectory: analyzeCommand.workingDirectory,
    );
    // No timeout is passed, so `run()` cannot actually return null here —
    // static analysis over already-parsed source cannot hang. `exitCode` is
    // still nullable at the type level because `run()` is shared with the
    // test command, which does need one.
    final int? exitCode = await withTarget.run();
    return exitCode != null && _compilingExitCodes.contains(exitCode);
  }
}
