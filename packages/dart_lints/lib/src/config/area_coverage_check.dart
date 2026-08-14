import 'package:glob/glob.dart';

import 'area.dart';
import 'dart_lints_config.dart';
import 'file_system_probe.dart';

/// Finds Dart files that no area claims.
///
/// The check is per **file**, not per directory, because the directory form
/// cannot see what actually escapes. `packages/*/lib/**` covers
/// `packages/x/lib/src/y.dart` and therefore reports the `packages/` directory
/// as covered — while `packages/x/bin/main.dart` matches nothing and goes
/// unlinted with no complaint. Directory granularity would have declared that
/// configuration complete.
///
/// An uncovered file is a configuration fault rather than a silent skip: a
/// region nobody lints reports zero violations, which reads exactly like a
/// region that passes.
class AreaCoverageCheck {
  const AreaCoverageCheck(this.probe);

  final FileSystemProbe probe;

  /// Dart files under the config root claimed by no area and not excluded.
  List<String> uncovered(DartLintsConfig config) {
    final List<String> candidates = probe.dartFilesUnder(config.rootDirectory);

    return candidates
        .where((String path) => !_matchesAny(config.excludeGlobs, path))
        .where((String path) => !_matchesAny(config.coverageIgnore, path))
        .where(
          (String path) => !config.areas.any((Area area) => area.matches(path)),
        )
        .toList();
  }

  bool _matchesAny(List<Glob> globs, String path) =>
      globs.any((Glob glob) => glob.matches(path));
}
