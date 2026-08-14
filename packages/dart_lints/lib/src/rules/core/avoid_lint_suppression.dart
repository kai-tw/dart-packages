import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Flags `// ignore:` and `// ignore_for_file:` analyzer suppressions.
///
/// This rule guards the other rules. Every other lint here catches a mistake;
/// this one catches the *escape hatch* from all of them — and it is the only
/// rule whose subject is the author's decision to bypass enforcement rather
/// than the code itself. That asymmetry is why it cannot live as prose: a line
/// asking an author not to suppress is read at exactly the moment they have
/// already decided to, which is the weakest possible point of enforcement.
///
/// A suppression hides the smell the lint exists to catch, and it does so
/// invisibly — one comment, no diff signal, no review surface.
///
/// **Bad:**
/// ```dart
/// // ignore: deprecated_member_use
/// final ThemeData t = ThemeData.raw(...);
/// ```
///
/// **Good — restructure so the rule passes:**
/// ```dart
/// final ThemeData t = ThemeData(colorScheme: scheme);
/// ```
///
/// **Good — when the diagnostic is wrong for the whole project,** exempt it in
/// `analysis_options.yaml` under `analyzer: errors:` with a comment explaining
/// why (`experimental_member_use: ignore` is the worked example).
///
/// **When the language or the framework leaves no alternative at ONE site**,
/// add it to [_sanctioned] below with its reason. Repo-wide severity is the
/// wrong tool for a single forced line — silencing `deprecated_member_use`
/// everywhere to fix one call throws away the signal for the whole codebase.
/// Both escape routes share the property that matters: the exemption lives in
/// a tracked file, shows up in a diff, and carries a written reason, instead of
/// being a comment the author adds beside their own violation.
///
/// Generated output is out of scope — `.freezed.dart`, `.g.dart` and
/// `generated/` are excluded by the runner, and `firebase_options.dart` is
/// excluded here (the flutterfire CLI writes its own `ignore_for_file` header
/// and regenerates it on every run, so there is nothing an author can fix).
///
/// Not covered by the stock linter: `unnecessary_ignore` solves the opposite
/// problem — it flags an ignore whose diagnostic is *no longer produced*
/// (a dead suppression). A live, working suppression is exactly what it
/// permits and this rule forbids. The two compose; neither replaces the other.
class AvoidLintSuppression extends LintRule {
  AvoidLintSuppression({
    List<String>? generatedFiles,
    List<String>? sanctionedSuppressions,
  }) : generatedFiles = generatedFiles ?? const <String>[],
       sanctionedSuppressions = sanctionedSuppressions ?? const <String>[];

  /// Files a tool writes and rewrites, header and suppressions included. Their
  /// contents are not anybody's to restructure.
  ///
  /// This is the one exemption that is genuinely unfixable rather than merely
  /// inconvenient: `firebase_options.dart` ships an `// ignore_for_file:` line
  /// that the generator re-emits on every run, so editing it is undone by the
  /// next `flutterfire configure`. Contrast a hand-written file, where the
  /// suppression is nearly always a shape problem the author can solve — a
  /// class flagged for holding only statics needs a private constructor, not an
  /// exemption. Reach for this list only when a tool owns the bytes.
  final List<String> generatedFiles;

  /// `<file>:<diagnostic>` pairs where the language or framework leaves no
  /// alternative AT THAT SITE. Repo-wide severity is the wrong tool for a
  /// single forced line; this list is the narrow one.
  ///
  /// It lives in the project's config rather than here because each entry is a
  /// claim about one project's code, and the reason belongs next to the entry
  /// where a reviewer reads it.
  final List<String> sanctionedSuppressions;

  @override
  String get name => 'avoid_lint_suppression';

  @override
  String get description =>
      'Never suppress a diagnostic with // ignore: or // ignore_for_file:. '
      'Restructure the code to satisfy the rule, or — if the diagnostic is '
      'genuinely wrong for this project — exempt it in analysis_options.yaml '
      'under `analyzer: errors:`, where the exemption is visible in a diff.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(
    filePath,
    lineInfo,
    source,
    generatedFiles,
    sanctionedSuppressions,
  );
}

class _Visitor extends LintVisitor {
  _Visitor(
    super.filePath,
    super.lineInfo,
    super.source,
    this.generatedFiles,
    this.sanctionedSuppressions,
  );

  final List<String> generatedFiles;
  final List<String> sanctionedSuppressions;

  static final RegExp _suppression = RegExp(r'^//\s*ignore(_for_file)?\s*:');

  bool get _isGenerated => generatedFiles.any(filePath.endsWith);

  bool _isSanctioned(String lexeme) {
    final String file = filePath.split('/').last;
    return sanctionedSuppressions.any(
      (String key) =>
          key.startsWith('$file:') && lexeme.contains(key.split(':').last),
    );
  }

  @override
  void visitCompilationUnit(CompilationUnit node) {
    if (!_isGenerated) {
      // Walk the token stream rather than the raw source: comments hang off
      // tokens, so a `// ignore:` appearing inside a string literal or a
      // dartdoc example can never be mistaken for a real suppression.
      Token? token = node.beginToken;
      while (token != null) {
        Token? comment = token.precedingComments;
        while (comment != null) {
          final String lexeme = comment.lexeme.trim();
          if (_suppression.hasMatch(lexeme) && !_isSanctioned(lexeme)) {
            report(
              ruleName: 'avoid_lint_suppression',
              message:
                  'Lint suppression is forbidden — it hides the smell the '
                  'rule exists to catch. Restructure to satisfy the rule, or '
                  'exempt the diagnostic in analysis_options.yaml under '
                  '`analyzer: errors:` so the exemption is reviewable.',
              offset: comment.offset,
            );
          }
          comment = comment.next;
        }
        if (token.type == TokenType.EOF) {
          break;
        }
        token = token.next;
      }
    }
    super.visitCompilationUnit(node);
  }
}
