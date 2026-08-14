import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import 'area_resolver.dart';
import 'config/area.dart';
import 'config/dart_lints_config.dart';
import 'lint_rule_base.dart';
import 'rule_registry.dart';
import 'stock_analyzer_runner.dart';
import 'violation_reporter.dart';

/// The outcome of one run: what to report, and what never got looked at.
class LintRunResult {
  const LintRunResult({
    required this.violations,
    required this.unresolvedPaths,
    required this.fixedCount,
    required this.analyzerIssues,
  });

  final List<LintViolation> violations;

  /// Files the analyzer could not resolve — see [ViolationReporter.reportUnresolved].
  final List<String> unresolvedPaths;

  final int fixedCount;
  final int analyzerIssues;

  bool get isClean =>
      violations.isEmpty && unresolvedPaths.isEmpty && analyzerIssues == 0;
}

/// Runs the stock analyzer and this package's rules over a set of paths.
class LintRunner {
  LintRunner({
    required this.config,
    required this.registry,
    required this.resolver,
    required this.analyzer,
    required this.reporter,
  });

  final DartLintsConfig config;
  final RuleRegistry registry;
  final AreaResolver resolver;
  final StockAnalyzerRunner analyzer;
  final ViolationReporter reporter;

  /// Rules are built once per area, not once per file.
  final Map<String, BuiltRules> _rulesByArea = <String, BuiltRules>{};

  Future<LintRunResult> run({
    List<String> paths = const <String>[],
    String? areaName,
    bool fix = false,
    bool skipAnalyze = false,
  }) async {
    final List<Area> areas = areaName == null
        ? config.areas
        : config.areas.where((Area a) => a.name == areaName).toList();

    final List<String> scanRoots = paths.isNotEmpty
        ? paths.map((String path) => p.normalize(p.absolute(path))).toList()
        : <String>[config.rootDirectory];

    final int analyzerIssues = skipAnalyze
        ? 0
        : analyzer.run(config.analyzer, scanRoots);

    final List<LintViolation> violations = <LintViolation>[];
    final List<String> unresolved = <String>[];
    final Map<ProjectLintRule, List<ProjectUnit>> projectUnits =
        <ProjectLintRule, List<ProjectUnit>>{};
    int fixedCount = 0;

    final AnalysisContextCollection collection = AnalysisContextCollection(
      includedPaths: scanRoots,
    );

    for (final AnalysisContext context in collection.contexts) {
      for (final String absolutePath in context.contextRoot.analyzedFiles()) {
        if (!absolutePath.endsWith('.dart')) {
          continue;
        }

        final String relativePath = resolver.relativize(absolutePath);
        if (_isExcluded(relativePath)) {
          continue;
        }

        final Area? area = resolver.resolve(absolutePath);
        if (area == null || !areas.contains(area)) {
          continue;
        }

        final _FileOutcome outcome = await _analyzeFile(
          context: context,
          absolutePath: absolutePath,
          relativePath: relativePath,
          area: area,
          projectUnits: projectUnits,
        );

        if (outcome.unresolved) {
          unresolved.add(relativePath);
          continue;
        }

        violations.addAll(outcome.violations);

        if (fix && outcome.source != null) {
          fixedCount += _applyFixes(
            absolutePath,
            outcome.source!,
            outcome.violations,
          );
        }
      }
    }

    // Per-file findings are reported before the project pass runs, so a rule
    // that throws below cannot take them down with it.
    reporter.report(violations);

    // Project rules see the whole collected set, after the per-file pass.
    // A throw here is deliberately NOT caught: a rule that throws is defective,
    // and a run that swallowed it would report a clean tree while one rule
    // silently contributed nothing — the failure this tool exists to prevent.
    // The findings above are already on stdout, so the crash costs the user
    // diagnosis, not the whole pass.
    for (final MapEntry<ProjectLintRule, List<ProjectUnit>> entry
        in projectUnits.entries) {
      final List<LintViolation> found = entry.key.run(entry.value);
      violations.addAll(found);
      reporter.report(found);
    }

    return LintRunResult(
      violations: violations,
      unresolvedPaths: unresolved,
      fixedCount: fixedCount,
      analyzerIssues: analyzerIssues,
    );
  }

  Future<_FileOutcome> _analyzeFile({
    required AnalysisContext context,
    required String absolutePath,
    required String relativePath,
    required Area area,
    required Map<ProjectLintRule, List<ProjectUnit>> projectUnits,
  }) async {
    final SomeResolvedUnitResult result = await context.currentSession
        .getResolvedUnit(absolutePath);
    if (result is! ResolvedUnitResult) {
      return const _FileOutcome.unresolved();
    }

    final BuiltRules rules = _rulesFor(area);
    final List<LintViolation> violations = <LintViolation>[];

    for (final LintRule rule in rules.syntax) {
      final LintVisitor visitor = rule.createVisitor(
        relativePath,
        result.lineInfo,
        result.content,
      );
      result.unit.accept(visitor);
      violations.addAll(visitor.violations);
    }

    for (final ResolvedLintRule rule in rules.resolved) {
      final ResolvedLintVisitor visitor = rule.createResolvedVisitor(
        relativePath,
        result,
      );
      result.unit.accept(visitor);
      violations.addAll(visitor.violations);
    }

    for (final ProjectLintRule rule in rules.project) {
      if (rule.shouldCollect(relativePath, result.content)) {
        projectUnits
            .putIfAbsent(rule, () => <ProjectUnit>[])
            .add(ProjectUnit(relativePath, result.unit, result.lineInfo));
      }
    }

    return _FileOutcome(violations: violations, source: result.content);
  }

  BuiltRules _rulesFor(Area area) => _rulesByArea.putIfAbsent(
    area.name,
    () => registry.build(
      area.enabledRules,
      (String ruleName) => config.optionsFor(ruleName, area),
    ),
  );

  /// Applies every fix on [violations] to [source] and writes the result.
  ///
  /// [source] is the buffer the offsets were computed against, not a fresh read
  /// of the file. Re-reading would let an edit made in between shift every
  /// offset, splicing the replacements at the wrong positions — a corrupted
  /// file rather than one of two intact versions.
  int _applyFixes(
    String absolutePath,
    String source,
    List<LintViolation> violations,
  ) {
    final List<SourceEdit> edits = <SourceEdit>[
      for (final LintViolation v in violations)
        if (v.fix != null) ...v.fix!.edits,
    ];
    if (edits.isEmpty) {
      return 0;
    }

    // Descending offset order keeps every earlier offset valid as edits land.
    edits.sort((SourceEdit a, SourceEdit b) => b.offset.compareTo(a.offset));

    String content = source;
    for (final SourceEdit edit in edits) {
      content =
          content.substring(0, edit.offset) +
          edit.replacement +
          content.substring(edit.offset + edit.length);
    }

    try {
      File(absolutePath).writeAsStringSync(content);
    } on FileSystemException catch (e) {
      reporter.err.writeln('Could not write $absolutePath: ${e.message}');
      return 0;
    }

    return violations.where((LintViolation v) => v.fix != null).length;
  }

  bool _isExcluded(String relativePath) =>
      config.excludeGlobs.any((Glob glob) => glob.matches(relativePath));
}

class _FileOutcome {
  const _FileOutcome({required this.violations, required this.source})
    : unresolved = false;

  const _FileOutcome.unresolved()
    : violations = const <LintViolation>[],
      source = null,
      unresolved = true;

  final List<LintViolation> violations;
  final String? source;
  final bool unresolved;
}
