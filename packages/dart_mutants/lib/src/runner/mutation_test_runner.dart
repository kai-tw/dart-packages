import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';

import '../generated_file_filter.dart';
import '../mutant.dart';
import '../mutation_operator.dart';
import '../mutation_visitor.dart';
import '../operators.dart';
import 'compile_safety_gate.dart';
import 'file_mutation_report.dart';
import 'mutant_result.dart';
import 'mutant_verdict.dart';
import 'mutated_file_registry.dart';
import 'mutation_run_report.dart';
import 'process_command.dart';
import 'test_compilation_cache.dart';

/// Runs every operator's mutants against [testCommand], one at a time, and
/// scores the result.
///
/// The contract this whole package exists to serve: hand it a file list and
/// a test command, get back per-file totals and the actual survivors. Which
/// files to pass, whether the score is good enough, and what to do about a
/// surviving mutant are all outside this class on purpose — that is policy,
/// decided by whoever calls this, not by the engine running the mutants.
class MutationTestRunner {
  MutationTestRunner({
    required this.testCommand,
    required this.compileSafetyGate,
    List<MutationOperator>? operators,
    this.mutantTimeout = const Duration(seconds: 30),
  }) : operators = operators ?? defaultOperators();

  final ProcessCommand testCommand;
  final CompileSafetyGate compileSafetyGate;
  final List<MutationOperator> operators;

  /// How long [testCommand] gets before a run is killed and scored as
  /// [MutantVerdict.timeout] instead of waited on forever. Applied to the
  /// baseline check too — an already-hanging test command is exactly as
  /// unusable a baseline as an already-failing one.
  final Duration mutantTimeout;

  final MutatedFileRegistry _registry = MutatedFileRegistry();

  /// See [TestCompilationCache]'s own doc for why this exists at all — in
  /// short, `dart test`'s incremental kernel cache does not reliably notice
  /// the fast, repeated, small rewrites this class makes to one file.
  late final TestCompilationCache _testCache = TestCompilationCache(
    testCommand.workingDirectory,
  );

  /// Runs the full session over [filePaths]. Generated files are dropped
  /// silently — they are never a meaningful target, not a policy choice a
  /// caller needs to make per run — everything else needs the caller to have
  /// already decided it belongs in this run; this class does not further
  /// filter by "was it actually covered" or any other policy question.
  ///
  /// Refuses to run at all if [testCommand] does not pass unmodified first:
  /// scoring mutants against a suite that was already red makes every one of
  /// them look detected, for a reason that has nothing to do with the
  /// mutation.
  Future<MutationRunReport> run(List<String> filePaths) async {
    final List<String> targets = filePaths
        .where((String path) => !isGeneratedFile(path))
        .toList();

    // Armed before the baseline runs, not after. The baseline is a full test
    // command like any other, so a Ctrl-C during it orphans a subprocess tree
    // exactly the same way — and it is the longest single run of the session,
    // being the cold one. There is nothing to restore yet at this point; the
    // restore half is simply a no-op until the first mutant is written.
    _registry.armSignalRestore(beforeExit: ProcessCommand.killAllRunning);
    try {
      _testCache.clear();
      final int? baselineExitCode = await testCommand.run(
        timeout: mutantTimeout,
      );
      if (baselineExitCode == null) {
        return const MutationRunReport.aborted(
          'the test command did not finish against unmodified code within '
          'the timeout — refusing to score mutants against a baseline that '
          'never even completes',
        );
      }
      if (baselineExitCode != 0) {
        return MutationRunReport.aborted(
          'the test command failed against unmodified code (exit '
          '$baselineExitCode) — refusing to score mutants against a baseline '
          'that was already red',
        );
      }

      final List<FileMutationReport> fileReports = <FileMutationReport>[];
      for (final String filePath in targets) {
        fileReports.add(await _runFile(filePath));
      }
      return MutationRunReport.completed(fileReports);
    } finally {
      // A safety net, not the primary mechanism — _runOne already restores
      // after every individual mutant. This only fires if something escaped
      // before that: at most one file's worth of cleanup, never a whole
      // run's worth.
      _registry.restoreAll();
      await _registry.disarm();
    }
  }

  Future<FileMutationReport> _runFile(String filePath) async {
    final String originalSource = await File(filePath).readAsString();
    final List<Mutant> mutants = _collectMutants(filePath, originalSource);

    int detected = 0;
    int undetected = 0;
    int invalid = 0;
    int timedOut = 0;
    final List<MutantResult> undetectedResults = <MutantResult>[];
    final List<MutantResult> timedOutResults = <MutantResult>[];

    for (final Mutant mutant in mutants) {
      final MutantVerdict verdict = await _runOne(mutant, originalSource);
      switch (verdict) {
        case MutantVerdict.invalid:
          invalid++;
        case MutantVerdict.timeout:
          timedOut++;
          // Kept, not just counted. A timed-out mutant is real code that went
          // unmeasured, and a caller who only gets the number cannot tell
          // WHICH line, whether it is the same one across runs, or go and look
          // at it. Measured: a mutant that timed out on every round of a file
          // was therefore never scored at all — permanently invisible behind a
          // count nobody reads per-mutant.
          timedOutResults.add(MutantResult(mutant: mutant, verdict: verdict));
        case MutantVerdict.detected:
          detected++;
        case MutantVerdict.undetected:
          undetected++;
          undetectedResults.add(
            MutantResult(mutant: mutant, verdict: verdict),
          );
      }
    }

    return FileMutationReport(
      filePath: filePath,
      detected: detected,
      undetected: undetected,
      invalid: invalid,
      timedOut: timedOut,
      undetectedMutants: undetectedResults,
      timedOutMutants: timedOutResults,
    );
  }

  List<Mutant> _collectMutants(String filePath, String source) {
    final ParseStringResult parsed = parseString(
      content: source,
      throwIfDiagnostics: false,
    );
    final List<Mutant> mutants = <Mutant>[];
    for (final MutationOperator operator in operators) {
      final MutationVisitor visitor = operator.createVisitor(
        filePath,
        parsed.lineInfo,
        source,
      );
      parsed.unit.accept(visitor);
      mutants.addAll(visitor.mutants);
    }
    return mutants;
  }

  /// Applies [mutant] to disk, checks compile-safety, runs [testCommand] if
  /// it passed that gate, then restores the file before returning —
  /// regardless of which branch was taken, so a thrown exception here still
  /// leaves the file clean.
  Future<MutantVerdict> _runOne(Mutant mutant, String originalSource) async {
    _registry.track(mutant.filePath, originalSource);
    await File(mutant.filePath).writeAsString(mutant.applyTo(originalSource));
    try {
      if (!await compileSafetyGate.compiles(mutant.filePath)) {
        return MutantVerdict.invalid;
      }
      _testCache.clear();
      final int? exitCode = await testCommand.run(timeout: mutantTimeout);
      if (exitCode == null) {
        // A mutant that hangs the suite is not neutral evidence — it often
        // means the mutation introduced a genuine infinite loop, which is
        // arguably the mutation actually changing behaviour. But counting it
        // as "detected" would let a hang inflate the score in exactly the
        // wrong direction the compile-safety gate exists to prevent for
        // invalid mutants: a number that looks better while representing a
        // test that never actually ran to a real assertion. Kept as its own
        // bucket, excluded from the score like `invalid`, rather than
        // guessed into either side.
        return MutantVerdict.timeout;
      }
      return exitCode == 0 ? MutantVerdict.undetected : MutantVerdict.detected;
    } finally {
      _registry.restore(mutant.filePath);
    }
  }
}
