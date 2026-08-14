/// A configuration fault that stops the run before any analysis happens.
///
/// Every configuration fault is fatal by design. A mistyped rule name that
/// merely warned would leave the rule silently disabled while the run still
/// reported success — the one failure mode a linter cannot detect about
/// itself.
class DartLintsConfigException implements Exception {
  const DartLintsConfigException(
    this.message, {
    this.configPath,
    this.suggestions = const <String>[],
  });

  final String message;
  final String? configPath;

  /// Nearest legal spellings, when the fault is an unrecognised name.
  final List<String> suggestions;

  @override
  String toString() {
    final StringBuffer buffer = StringBuffer('dart_lints: $message');
    if (configPath != null) {
      buffer.write('\n  config: $configPath');
    }
    if (suggestions.isNotEmpty) {
      buffer.write('\n  did you mean: ${suggestions.join(', ')}?');
    }
    return buffer.toString();
  }
}
