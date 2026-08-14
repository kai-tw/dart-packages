import 'package:glob/glob.dart';

import 'analyzer_spec.dart';
import 'area.dart';

/// A resolved `dart_lints.yaml`.
///
/// [rootDirectory] is the single basis every glob in this object is matched
/// against: paths are made relative to it and normalised to POSIX separators
/// before matching. Mixing bases is how an exclude list stops excluding — a
/// leading `**` does not match an absolute path — so the basis is fixed here
/// once rather than decided per call site.
class DartLintsConfig {
  const DartLintsConfig({
    required this.rootDirectory,
    required this.analyzer,
    required this.areas,
    this.excludeGlobs = const <Glob>[],
    this.coverageIgnore = const <Glob>[],
    this.options = const <String, Map<String, Object?>>{},
  });

  /// The directory holding the config file. Every glob resolves against it.
  final String rootDirectory;

  final AnalyzerSpec analyzer;
  final List<Area> areas;

  /// Paths never analyzed, whichever area they fall in.
  final List<Glob> excludeGlobs;

  /// Dart files deliberately claimed by no area. Anything else uncovered is a
  /// configuration fault, not a silent skip.
  final List<Glob> coverageIgnore;

  /// Global rule options, keyed by rule name. An area may layer over these.
  final Map<String, Map<String, Object?>> options;

  /// The options in force for [ruleName] inside [area].
  Map<String, Object?> optionsFor(String ruleName, Area? area) {
    final Map<String, Object?> global =
        options[ruleName] ?? const <String, Object?>{};
    final Map<String, Object?>? override = area?.optionOverrides[ruleName];
    if (override == null) {
      return global;
    }
    return <String, Object?>{...global, ...override};
  }
}
