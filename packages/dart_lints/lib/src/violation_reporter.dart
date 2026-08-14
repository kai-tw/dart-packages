import 'lint_rule_base.dart';

/// Writes violations and the run summary to an injected sink.
///
/// The sink is a constructor parameter rather than `stdout` so a test can
/// assert the exact output. That matters more here than it looks: the output
/// format is the migration's acceptance surface, and a format drift that no
/// test can see is a drift nobody notices.
class ViolationReporter {
  ViolationReporter(this.out, {StringSink? err}) : err = err ?? out;

  final StringSink out;
  final StringSink err;

  void report(List<LintViolation> violations) {
    final List<LintViolation> sorted = List<LintViolation>.of(violations)
      ..sort((LintViolation a, LintViolation b) {
        final int byPath = a.filePath.compareTo(b.filePath);
        if (byPath != 0) {
          return byPath;
        }
        return a.line.compareTo(b.line);
      });

    sorted.forEach(out.writeln);
  }

  void reportFixes(int fixedCount) {
    if (fixedCount == 0) {
      return;
    }
    out.writeln(
      '  Applied $fixedCount fix${fixedCount == 1 ? '' : 'es'}. '
      'Run dart format to clean up.',
    );
  }

  /// Names every file the analyzer could not resolve.
  ///
  /// Unresolvable files are listed rather than merely skipped because a skip is
  /// indistinguishable from a clean pass: the file simply reports no
  /// violations. On a pinned older analyzer, newer language syntax lands here —
  /// so silence would mean the rules never ran on exactly the files most likely
  /// to be new.
  void reportUnresolved(List<String> unresolvedPaths) {
    if (unresolvedPaths.isEmpty) {
      return;
    }
    err.writeln('');
    err.writeln(
      '${unresolvedPaths.length} file(s) could not be resolved and were NOT '
      'linted:',
    );
    for (final String path in unresolvedPaths) {
      err.writeln('  $path');
    }
  }

  void summarise({
    required int analyzerIssues,
    required int customIssues,
    required bool analyzerRan,
  }) {
    out.writeln('');
    final int total = analyzerIssues + customIssues;
    if (total == 0) {
      out.writeln('No issues found!');
      return;
    }
    if (analyzerRan) {
      out.writeln(
        '$total total issue${total == 1 ? '' : 's'} '
        '($analyzerIssues analyzer, $customIssues custom).',
      );
      return;
    }
    out.writeln('$customIssues issue${customIssues == 1 ? '' : 's'} found.');
  }
}
