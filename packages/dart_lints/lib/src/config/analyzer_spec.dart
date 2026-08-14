/// Which stock analyzer `dart_lints` shells out to before running its own
/// rules.
enum AnalyzerCommand {
  /// `dart analyze` — a pure-Dart package or workspace.
  dart,

  /// `flutter analyze` — anything depending on the Flutter SDK.
  flutter,

  /// Skip the stock analyzer; run custom rules only.
  none,
}

/// How to invoke the stock analyzer: which command, with which flags, over
/// which paths.
///
/// The three are separate because they answer different questions and drift
/// apart in practice. `args` carries flags whose absence silently weakens the
/// gate — `--fatal-infos` is the load-bearing example, since linter diagnostics
/// are INFO severity and a run without it prints them and still exits 0.
/// `paths` is deliberately independent of the areas: a project may want its
/// custom rules over a directory that the stock analyzer cannot yet parse
/// cleanly, and collapsing the two would force it to choose.
class AnalyzerSpec {
  const AnalyzerSpec({
    required this.command,
    this.args = const <String>[],
    this.paths = const <String>[],
  });

  /// The spec for a config that names no `analyzer:` key at all.
  static const AnalyzerSpec none = AnalyzerSpec(command: AnalyzerCommand.none);

  final AnalyzerCommand command;
  final List<String> args;

  /// Paths handed to the stock analyzer. Empty means "the areas' paths".
  final List<String> paths;
}
