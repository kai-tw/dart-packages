import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when a dartdoc block — a run of consecutive `///` lines with no
/// blank-line gap — contains a markdown heading (`##` or deeper).
///
/// A heading inside a dartdoc is the author's own admission that the block
/// carries more than one document. The fix is not to shorten it — it is to
/// split each section onto the declaration it actually constrains: a class's
/// contract stays on the class, one method's behavior goes on that method, a
/// field's reason for existing goes on the field. Length is the symptom;
/// documenting the wrong declaration is the disease.
///
/// This is a narrow, high-precision smoke detector, not a length check. A
/// length threshold was tried first and rejected: some genuinely
/// single-purpose contracts run long by nature — a documented cross-cutting
/// invariant, an exhaustive enum's per-value rules — and a length rule cannot
/// tell those apart from a real multi-document block. A heading is a rarer,
/// far more deliberate signal: an author reaches for `##` specifically to
/// separate sections. That means lower recall, but it is right close to every
/// time it fires.
///
/// **Bad:**
/// ```dart
/// /// Handles the sync engine.
/// ///
/// /// ## Retry policy
/// /// Retries three times with exponential backoff.
/// ///
/// /// ## Conflict resolution
/// /// Last write wins, keyed by [Hlc].
/// class SyncEngine { ... }
/// ```
///
/// **Good — split onto the declarations each section actually describes:**
/// ```dart
/// /// Handles the sync engine.
/// class SyncEngine {
///   /// Retries three times with exponential backoff.
///   Future<void> retry() { ... }
///
///   /// Resolves conflicts last-write-wins, keyed by [Hlc].
///   void resolveConflict() { ... }
/// }
/// ```
class AvoidMultiDocumentDartdoc extends LintRule {
  @override
  String get name => 'avoid_multi_document_dartdoc';

  @override
  String get description =>
      'A dartdoc block should document one declaration, not several '
      'sections stacked under markdown headings. Split each section onto '
      'the declaration it actually constrains.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source);
}

class _Visitor extends LintVisitor {
  _Visitor(super.filePath, super.lineInfo, super.source);

  static final RegExp _heading = RegExp(r'^#{2,}(\s|$)');

  static bool _isDocLine(String lexeme) =>
      lexeme.startsWith('///') && !lexeme.startsWith('////');

  static bool _isHeading(String lexeme) =>
      _heading.hasMatch(lexeme.substring(3).trimLeft());

  int? _blockLine;
  int? _headingOffset;

  void _closeBlock() {
    final int? offset = _headingOffset;
    if (offset != null) {
      report(
        ruleName: 'avoid_multi_document_dartdoc',
        message:
            'This dartdoc uses a markdown heading, which means it carries '
            'more than one document. Split each section onto the '
            "declaration it actually constrains instead — a class's "
            "contract stays on the class, a method's behavior goes on that "
            "method, a field's reason goes on the field.",
        offset: offset,
      );
    }
    _blockLine = null;
    _headingOffset = null;
  }

  @override
  void visitCompilationUnit(CompilationUnit node) {
    // Walk the token stream rather than the raw source: comments hang off
    // tokens, so `///`-looking text inside a string literal — a test fixture
    // holding sample source, say — can never be mistaken for a real dartdoc
    // line.
    Token? token = node.beginToken;
    while (token != null) {
      Token? comment = token.precedingComments;
      while (comment != null) {
        final String lexeme = comment.lexeme;
        if (_isDocLine(lexeme)) {
          final int line = lineInfo.getLocation(comment.offset).lineNumber;
          final int? blockLine = _blockLine;
          if (blockLine != null && line != blockLine + 1) {
            _closeBlock();
          }
          _blockLine = line;
          if (_headingOffset == null && _isHeading(lexeme)) {
            _headingOffset = comment.offset;
          }
        } else {
          _closeBlock();
        }
        comment = comment.next;
      }
      if (token.type == TokenType.EOF) {
        break;
      }
      token = token.next;
    }
    _closeBlock();

    super.visitCompilationUnit(node);
  }
}
