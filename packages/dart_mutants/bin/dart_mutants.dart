import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_mutants/src/runner/compile_safety_gate.dart';
import 'package:dart_mutants/src/runner/file_mutation_report.dart';
import 'package:dart_mutants/src/runner/mutant_result.dart';
import 'package:dart_mutants/src/runner/mutation_run_report.dart';
import 'package:dart_mutants/src/runner/mutation_test_runner.dart';
import 'package:dart_mutants/src/runner/process_command.dart';

/// The CLI contract: a file list and a test command in, per-file
/// total/undetected out. Which files to pass and what to do with the report
/// is deliberately not this binary's concern — that is `plan-mutation`'s
/// job, one layer up.
Future<void> main(List<String> arguments) async {
  final ArgParser parser = ArgParser()
    ..addOption(
      'test-command',
      mandatory: true,
      help:
          'The command that runs the relevant tests, e.g. '
          '"flutter test test/foo_test.dart". Split on whitespace — quoting '
          'an argument that itself contains a space is not supported yet.',
    )
    ..addOption(
      'analyze-command',
      defaultsTo: 'dart analyze',
      help: 'The analyzer invocation used for the compile-safety gate.',
    )
    ..addFlag('json', help: 'Emit the report as JSON instead of text.')
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(parser.usage);
    exitCode = 64; // EX_USAGE
    return;
  }

  if (args['help'] as bool) {
    stdout.writeln(parser.usage);
    return;
  }

  final List<String> filePaths = args.rest;
  if (filePaths.isEmpty) {
    stderr.writeln('no files given — nothing to mutate');
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  final MutationTestRunner runner = MutationTestRunner(
    testCommand: _parseCommand(args['test-command'] as String),
    compileSafetyGate: CompileSafetyGate(
      _parseCommand(args['analyze-command'] as String),
    ),
  );

  final MutationRunReport report = await runner.run(filePaths);

  if (args['json'] as bool) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
  } else {
    _printText(report);
  }

  if (report.aborted) {
    exitCode = 1;
    return;
  }
  final bool anyUndetected = report.files.any(
    (FileMutationReport f) => f.undetected > 0,
  );
  exitCode = anyUndetected ? 1 : 0;
}

ProcessCommand _parseCommand(String command) {
  final List<String> parts = command.trim().split(RegExp(r'\s+'));
  return ProcessCommand(parts.first, parts.skip(1).toList());
}

void _printText(MutationRunReport report) {
  if (report.aborted) {
    stdout.writeln('aborted: ${report.abortReason}');
    return;
  }
  for (final FileMutationReport f in report.files) {
    final String rate = f.detectionRate == null
        ? 'n/a'
        : '${(f.detectionRate! * 100).toStringAsFixed(0)}%';
    stdout.writeln(
      '${f.filePath}: $rate (${f.detected}/${f.total} detected, '
      '${f.invalid} invalid)',
    );
    for (final MutantResult r in f.undetectedMutants) {
      stdout.writeln(
        '  undetected: ${r.mutant.operatorName} at '
        '${f.filePath}:${r.mutant.line}:${r.mutant.column} — '
        '${r.mutant.description}',
      );
    }
  }
}
