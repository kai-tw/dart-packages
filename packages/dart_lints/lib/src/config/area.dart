import 'package:glob/glob.dart';

import 'analyzer_spec.dart';

/// A named region of a repository, plus the rule set that governs it.
///
/// An area is the unit a project reasons in — "production code", "tests",
/// "scripts" — and the only place paths are named. Rules never inspect a file
/// path to decide whether they apply to it; the runner resolves the area and
/// hands the rule the answer.
class Area {
  const Area({
    required this.name,
    required this.pathGlobs,
    required this.enabledRules,
    this.optionOverrides = const <String, Map<String, Object?>>{},
    this.analyzer,
  });

  final String name;

  /// Globs matched against paths relative to the config file's directory.
  final List<Glob> pathGlobs;

  /// Rule names in force here, after the global bundles/enable set has had this
  /// area's `enable` added and its `disable` removed.
  final Set<String> enabledRules;

  /// Per-area rule options layered over the global `options:` map.
  final Map<String, Map<String, Object?>> optionOverrides;

  /// Overrides the global analyzer spec for this area, when given.
  final AnalyzerSpec? analyzer;

  bool matches(String relativePath) =>
      pathGlobs.any((Glob glob) => glob.matches(relativePath));
}
