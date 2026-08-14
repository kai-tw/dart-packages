import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

/// A single source edit: replace [length] characters starting at [offset]
/// with [replacement].
class SourceEdit {
  const SourceEdit({
    required this.offset,
    required this.length,
    required this.replacement,
  });

  final int offset;
  final int length;
  final String replacement;
}

/// A quick fix that can be applied to resolve a lint violation.
class LintFix {
  const LintFix({required this.description, required this.edits});

  final String description;
  final List<SourceEdit> edits;
}

/// A violation found by a lint rule.
class LintViolation {
  const LintViolation({
    required this.ruleName,
    required this.message,
    required this.filePath,
    required this.line,
    required this.column,
    this.fix,
  });

  final String ruleName;
  final String message;
  final String filePath;
  final int line;
  final int column;
  final LintFix? fix;

  @override
  String toString() =>
      '  info \u2022 $message \u2022 $filePath:$line:$column \u2022 $ruleName';
}

/// Base class for custom lint rules.
abstract class LintRule {
  String get name;
  String get description;

  /// Returns a visitor that collects violations for [filePath].
  LintVisitor createVisitor(String filePath, LineInfo lineInfo, String source);
}

/// A visitor that collects [LintViolation]s.
abstract class LintVisitor extends RecursiveAstVisitor<void> {
  LintVisitor(this.filePath, this.lineInfo, this.source);

  final String filePath;
  final LineInfo lineInfo;
  final String source;
  final List<LintViolation> violations = <LintViolation>[];

  void report({
    required String ruleName,
    required String message,
    required int offset,
    LintFix? fix,
  }) {
    final CharacterLocation location = lineInfo.getLocation(offset);
    violations.add(
      LintViolation(
        ruleName: ruleName,
        message: message,
        filePath: filePath,
        line: location.lineNumber,
        column: location.columnNumber,
        fix: fix,
      ),
    );
  }
}

/// A lint rule that requires a fully resolved AST (type info, elements).
abstract class ResolvedLintRule {
  String get name;
  String get description;

  /// Returns a visitor that collects violations for a resolved unit.
  ResolvedLintVisitor createResolvedVisitor(
    String filePath,
    ResolvedUnitResult resolvedUnit,
  );
}

/// One parsed compilation unit handed to a [ProjectLintRule], paired with the
/// metadata needed to anchor a [LintViolation] back to its source location.
class ProjectUnit {
  const ProjectUnit(this.filePath, this.unit, this.lineInfo);

  final String filePath;
  final CompilationUnit unit;
  final LineInfo lineInfo;
}

/// A lint rule that reasons over the whole analyzed set at once rather than
/// one file in isolation. Unlike [LintRule] / [ResolvedLintRule] — which the
/// runner invokes per file — a project rule receives every collected
/// [ProjectUnit] in a single [run] call, so it can build cross-file graphs
/// (e.g. a dependency-injection graph) and report cycles that no single file
/// reveals. The rule computes its own violation locations via each unit's
/// [ProjectUnit.lineInfo].
abstract class ProjectLintRule {
  String get name;
  String get description;

  /// Whether the unit for [relativePath] / [source] must be retained for [run].
  ///
  /// Retaining every unit holds a `CompilationUnit` for the whole tree resident
  /// until the project pass finishes, so each rule declares the narrow slice it
  /// actually reasons over. There is deliberately no default — a rule needing
  /// the whole tree says so with `=> true`, keeping that memory cost someone's
  /// explicit decision rather than an inherited one.
  bool shouldCollect(String relativePath, String source);

  List<LintViolation> run(List<ProjectUnit> units);
}

/// A visitor for resolved-AST rules with access to type information.
abstract class ResolvedLintVisitor extends RecursiveAstVisitor<void> {
  ResolvedLintVisitor(this.filePath, this.resolvedUnit);

  final String filePath;
  final ResolvedUnitResult resolvedUnit;

  LineInfo get lineInfo => resolvedUnit.lineInfo;

  final List<LintViolation> violations = <LintViolation>[];

  void report({
    required String ruleName,
    required String message,
    required int offset,
    LintFix? fix,
  }) {
    final CharacterLocation location = lineInfo.getLocation(offset);
    violations.add(
      LintViolation(
        ruleName: ruleName,
        message: message,
        filePath: filePath,
        line: location.lineNumber,
        column: location.columnNumber,
        fix: fix,
      ),
    );
  }
}
