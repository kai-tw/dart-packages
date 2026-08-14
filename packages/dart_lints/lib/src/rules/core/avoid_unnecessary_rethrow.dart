import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when a catch clause only rethrows or throws the same exception type.
///
/// These catch clauses have no effect and should be removed.
///
/// **Bad:**
/// ```dart
/// try {
///   await cloudStorage.delete(path);
/// } on StorageFileNotFoundException {
///   rethrow;
/// }
/// ```
///
/// ```dart
/// try {
///   await cloudStorage.delete(path);
/// } on StorageFileNotFoundException {
///   throw StorageFileNotFoundException(path);
/// }
/// ```
///
/// **Good:**
/// ```dart
/// await cloudStorage.delete(path);
/// ```
///
/// **Not reported** — a rethrow standing in front of another catch clause is
/// load-bearing, because deleting it lets the *later* clause handle the type
/// instead. `rethrow` leaves the whole `try` rather than re-entering the
/// clause list, so the arm's only job is to keep the broader arm off this
/// type:
/// ```dart
/// } on StorageFileNotFoundException {
///   rethrow;                       // remove this and the next arm eats it
/// } on StorageException catch (e, s) {
///   LogSystem.error('…', error: e, stackTrace: s);
/// }
/// ```
/// Whether the later type really is a supertype needs type resolution this
/// syntax-level rule does not have, so **any** following clause suppresses the
/// report. That trades a few missed no-op clauses for never emitting a fix
/// that silently reroutes an exception.
class AvoidUnnecessaryRethrow extends LintRule {
  @override
  String get name => 'avoid_unnecessary_rethrow';

  @override
  String get description =>
      'Avoid catch clauses that only rethrow or throw the same '
      'exception type.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source);
}

class _Visitor extends LintVisitor {
  _Visitor(super.filePath, super.lineInfo, super.source);

  @override
  void visitCatchClause(CatchClause node) {
    if (_isUnnecessary(node)) {
      report(
        ruleName: 'avoid_unnecessary_rethrow',
        message:
            'Unnecessary catch clause \u2014 it only rethrows or throws '
            'the same exception type. Remove it.',
        offset: node.offset,
        fix: _buildFix(node),
      );
    }
    super.visitCatchClause(node);
  }

  /// Returns `true` when the catch clause body is a single rethrow or a
  /// single throw of the same type that was caught.
  bool _isUnnecessary(CatchClause node) {
    // Must have an explicit exception type (`on SomeType`).
    final TypeAnnotation? exceptionType = node.exceptionType;
    if (exceptionType is! NamedType) {
      return false;
    }

    // A clause with a later sibling is load-bearing — see the class doc.
    if (_hasFollowingClause(node)) {
      return false;
    }

    // Body must contain exactly one statement.
    final List<Statement> statements = node.body.statements;
    if (statements.length != 1) {
      return false;
    }

    final Statement stmt = statements.first;
    if (stmt is! ExpressionStatement) {
      return false;
    }

    final Expression expr = stmt.expression;

    // Pattern 1: `on SomeType { rethrow; }`
    if (expr is RethrowExpression) {
      return true;
    }

    // Pattern 2: `on SomeType { throw SomeType(...); }`
    if (expr is ThrowExpression) {
      final String caughtName = exceptionType.name.lexeme;
      return _throwsSameType(expr.expression, caughtName);
    }

    return false;
  }

  /// Whether another catch clause of the same `try` follows [node].
  ///
  /// Applies to the `throw SameType(...)` pattern as well as `rethrow`: both
  /// leave the try statement, so in both cases deleting the clause is what
  /// exposes the type to the later arm.
  bool _hasFollowingClause(CatchClause node) {
    final AstNode? parent = node.parent;
    if (parent is! TryStatement) {
      return false;
    }
    final List<CatchClause> clauses = parent.catchClauses;
    return clauses.indexOf(node) < clauses.length - 1;
  }

  bool _throwsSameType(Expression thrown, String caughtName) {
    // `throw SomeType(...)` without `new` — parsed as MethodInvocation.
    if (thrown is MethodInvocation &&
        thrown.target == null &&
        thrown.methodName.name == caughtName) {
      return true;
    }

    // `throw SomeType(...)` or `throw new SomeType(...)`.
    if (thrown is InstanceCreationExpression) {
      final NamedType type = thrown.constructorName.type;
      if (type.name.lexeme == caughtName && type.importPrefix == null) {
        return true;
      }
    }

    return false;
  }

  LintFix? _buildFix(CatchClause node) {
    final AstNode? parent = node.parent;
    if (parent is! TryStatement) {
      return null;
    }

    final bool isOnlyClause = parent.catchClauses.length == 1;
    final bool hasFinally = parent.finallyBlock != null;

    if (isOnlyClause && !hasFinally) {
      // The entire try-catch is unnecessary — unwrap the try body.
      return _buildUnwrapFix(parent);
    }

    // Remove just this catch clause.
    return LintFix(
      description: 'Remove unnecessary catch clause',
      edits: <SourceEdit>[
        SourceEdit(offset: node.offset, length: node.length, replacement: ''),
      ],
    );
  }

  LintFix _buildUnwrapFix(TryStatement tryStmt) {
    // Find the start of the line containing `try` so we can replace the
    // whole line range (including its leading indentation).
    int lineStart = tryStmt.offset;
    while (lineStart > 0 && source[lineStart - 1] != '\n') {
      lineStart--;
    }

    return LintFix(
      description: 'Remove unnecessary try-catch',
      edits: <SourceEdit>[
        SourceEdit(
          offset: lineStart,
          length: tryStmt.end - lineStart,
          replacement: _reindentBody(tryStmt),
        ),
      ],
    );
  }

  /// Extracts the try body statements and re-indents them to the level of
  /// the `try` keyword (one indentation level less than the body).
  String _reindentBody(TryStatement tryStmt) {
    final Block body = tryStmt.body;
    final int innerStart = body.leftBracket.end;
    final int innerEnd = body.rightBracket.offset;
    final String inner = source.substring(innerStart, innerEnd);

    // Determine the indentation of the `try` keyword.
    int lineStart = tryStmt.offset;
    while (lineStart > 0 && source[lineStart - 1] != '\n') {
      lineStart--;
    }
    final String tryIndent = source.substring(lineStart, tryStmt.offset);
    final String bodyIndent = '$tryIndent  ';

    // Strip leading/trailing blank lines from the body content.
    final List<String> lines = inner.split('\n');
    while (lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }

    // Re-indent each line from body-level to try-level.
    return lines
        .map((String line) {
          if (line.startsWith(bodyIndent)) {
            return '$tryIndent${line.substring(bodyIndent.length)}';
          }
          return line;
        })
        .join('\n');
  }
}
