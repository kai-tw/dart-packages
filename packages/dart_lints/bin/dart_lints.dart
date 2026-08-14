import 'dart:io';

import 'package:dart_lints/dart_lints.dart';

const String _usage = '''
Usage: dart run dart_lints [path...] [options]

With no path, every area declared in dart_lints.yaml is scanned. A path
restricts the scan; each file's area — and therefore its rules — still comes
from its own location.

Options:
  --config=PATH   Config file to use (default: nearest dart_lints.yaml at or
                  above the working directory)
  --area=NAME     Restrict to one area declared in the config
  --fix           Apply auto-fixes where a rule offers one
  --skip-analyze  Skip the stock analyzer, run custom rules only
  -h, --help      Show this message

Examples:
  dart run dart_lints
  dart run dart_lints --area=test
  dart run dart_lints lib --fix
  dart run dart_lints lib --skip-analyze
''';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.write(_usage);
    return;
  }

  final bool fix = args.contains('--fix');
  final bool skipAnalyze = args.contains('--skip-analyze');
  final String? configArg = _valueOf(args, '--config=');
  final String? areaArg = _valueOf(args, '--area=');
  final List<String> paths = args
      .where((String a) => !a.startsWith('-'))
      .toList();

  const FileSystemProbe probe = SystemFileSystemProbe();
  const RuleRegistry registry = RuleRegistry();
  const DartLintsConfigLoader loader = DartLintsConfigLoader(registry, probe);

  final DartLintsConfig config;
  try {
    final String configPath =
        configArg ?? loader.discover(Directory.current.path);
    config = loader.load(configPath);
  } on DartLintsConfigException catch (e) {
    stderr.writeln(e);
    exit(2);
  }

  if (areaArg != null && !config.areas.any((Area a) => a.name == areaArg)) {
    stderr.writeln(
      'dart_lints: unknown area "$areaArg" — declared areas are '
      '${config.areas.map((Area a) => a.name).join(', ')}.',
    );
    exit(2);
  }

  final ViolationReporter reporter = ViolationReporter(stdout, err: stderr);
  final LintRunner runner = LintRunner(
    config: config,
    registry: registry,
    resolver: AreaResolver(config.areas, rootDirectory: config.rootDirectory),
    analyzer: StockAnalyzerRunner(const SystemProcessRunner()),
    reporter: reporter,
  );

  final LintRunResult result = await runner.run(
    paths: paths,
    areaName: areaArg,
    fix: fix,
    skipAnalyze: skipAnalyze,
  );

  // Violations are printed by the runner as each pass completes, so a project
  // rule that throws cannot take the per-file findings down with it.
  reporter.reportFixes(result.fixedCount);
  reporter.reportUnresolved(result.unresolvedPaths);
  reporter.summarise(
    analyzerIssues: result.analyzerIssues,
    customIssues: result.violations.length,
    analyzerRan: !skipAnalyze,
  );

  // An unresolved file is a failure, not a quiet skip: it produced no
  // violations because nothing looked at it, which reads exactly like passing.
  exit(result.isClean ? 0 : 1);
}

String? _valueOf(List<String> args, String prefix) => args
    .where((String a) => a.startsWith(prefix))
    .map((String a) => a.substring(prefix.length))
    .firstOrNull;
