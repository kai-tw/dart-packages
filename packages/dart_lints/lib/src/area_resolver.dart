import 'package:path/path.dart' as p;

import 'config/area.dart';

/// Maps a file to the area that governs it.
///
/// A file matching more than one area belongs to the first area declared in the
/// config. Declaration order is stable in YAML, so the tie-break never depends
/// on filesystem enumeration order.
class AreaResolver {
  AreaResolver(this.areas, {required this.rootDirectory});

  final List<Area> areas;

  /// The basis every glob is matched against — see [DartLintsConfig].
  final String rootDirectory;

  /// The area governing [absolutePath], or null when no area claims it.
  ///
  /// Null is not "apply everything": an unclaimed file is a configuration gap,
  /// and `AreaCoverageCheck` reports it at validation time rather than letting
  /// the run guess here.
  Area? resolve(String absolutePath) {
    final String relative = relativize(absolutePath);
    for (final Area area in areas) {
      if (area.matches(relative)) {
        return area;
      }
    }
    return null;
  }

  /// [absolutePath] as a POSIX path relative to [rootDirectory].
  String relativize(String absolutePath) =>
      p.posix.joinAll(p.split(p.relative(absolutePath, from: rootDirectory)));
}
