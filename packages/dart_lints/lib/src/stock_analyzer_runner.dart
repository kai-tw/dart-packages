import 'dart:io';

import 'config/analyzer_spec.dart';
import 'process_runner.dart';

/// Shells out to `dart analyze` / `flutter analyze` and counts what it found.
class StockAnalyzerRunner {
  StockAnalyzerRunner(this.process, {StringSink? out, StringSink? err})
    : out = out ?? stdout,
      err = err ?? stderr;

  static final RegExp _issueCount = RegExp(r'(\d+) issues? found');

  final ProcessRunner process;
  final StringSink out;
  final StringSink err;

  /// Runs [spec] over [paths] and returns the issue count (0 when skipped).
  int run(AnalyzerSpec spec, List<String> paths) {
    if (spec.command == AnalyzerCommand.none) {
      return 0;
    }

    final String executable = spec.command == AnalyzerCommand.flutter
        ? 'flutter'
        : 'dart';
    final List<String> effectivePaths = spec.paths.isNotEmpty
        ? spec.paths
        : paths;

    out.writeln('Running $executable analyze...');
    final ProcessResult result = process.run(executable, <String>[
      'analyze',
      ...spec.args,
      ...effectivePaths,
    ]);
    out.write(result.stdout);
    err.write(result.stderr);
    out.writeln('');

    if (result.exitCode == 0) {
      return 0;
    }

    // The summary line goes to stderr, not stdout — reading only stdout always
    // missed it and silently reported a single issue however many there were.
    final Match? match = _issueCount.firstMatch(
      '${result.stdout}${result.stderr}',
    );
    return match != null ? int.parse(match.group(1)!) : 1;
  }
}
