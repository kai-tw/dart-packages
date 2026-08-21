import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../lint_rule_base.dart';

/// Warns when a catch clause names an **abstract** exception base type.
///
/// Catching an abstract base sweeps every subclass under one handler,
/// hides which failure modes the call path can actually produce, and
/// inevitably leads to either (a) silent over-handling — the catch
/// fires for failure modes the author never considered — or (b)
/// uniform `LogSystem.error` severity for both expected and unexpected
/// subclasses. Enumerate the concrete subclasses the underlying call
/// path can throw; collapse only when a single concrete sibling (e.g.
/// `StorageApiException` which has `StorageSocketException` as a child)
/// genuinely covers the residual cases.
///
/// **Bad:**
/// ```dart
/// try {
///   await cloudStorage.readMetadata(id);
/// } on StorageException catch (e, s) {  // abstract base
///   LogSystem.error('Skipping remote records', error: e, stackTrace: s);
/// }
/// ```
///
/// **Good:**
/// ```dart
/// try {
///   await cloudStorage.readMetadata(id);
/// } on StorageOfflineException {
///   LogSystem.info('Skipping remote records: device offline (pre-check)');
/// } on StorageDownloadException catch (e, s) {
///   LogSystem.error('Skipping remote records', error: e, stackTrace: s);
/// } on StorageApiException catch (e, s) {
///   // Covers StorageSocketException via inheritance.
///   LogSystem.error('Skipping remote records', error: e, stackTrace: s);
/// }
/// ```
///
/// Dart's built-in `Exception` and `Error` are flagged by sibling rules
/// (`avoid_catching_base_exception`, `avoid_catching_error`) and skipped
/// here to avoid duplicate reports.
///
/// Some libraries export only the abstract base and keep the concrete
/// subclass in an unexported `src/`, which leaves a consumer nothing narrower
/// to name. `sanctionedBases` is for those: it names the types this
/// configuration accepts, so the boundary that has no alternative can be
/// declared instead of the whole rule being switched off there. Everything
/// else in the same file still reports.
class AvoidCatchingAbstractException extends ResolvedLintRule {
  AvoidCatchingAbstractException({List<String>? sanctionedBases})
    : sanctionedBases = sanctionedBases ?? const <String>[];

  /// Abstract exception types this configuration accepts, by name.
  ///
  /// Deliberately not scoped by the rule itself — pair it with an area whose
  /// paths name the one boundary that needs it. A list here with the whole
  /// tree as its scope excuses the type everywhere, which is a different and
  /// much weaker claim than "this file has no alternative".
  ///
  /// Matched on the written name, which is what the report prints and what a
  /// reader of the configuration can check against the source.
  final List<String> sanctionedBases;

  @override
  String get name => 'avoid_catching_abstract_exception';

  @override
  String get description =>
      'Avoid catching abstract exception base types. '
      'Enumerate concrete subclasses the call path actually throws.';

  @override
  ResolvedLintVisitor createResolvedVisitor(
    String filePath,
    ResolvedUnitResult resolvedUnit,
  ) => _Visitor(filePath, resolvedUnit, sanctionedBases);
}

class _Visitor extends ResolvedLintVisitor {
  _Visitor(super.filePath, super.resolvedUnit, this.sanctionedBases);

  final List<String> sanctionedBases;

  /// Built-in base types covered by sibling rules — skip to avoid
  /// double-reporting.
  static const Set<String> _siblingRuleNames = <String>{
    'Exception', // avoid_catching_base_exception
    'Error', // avoid_catching_error
  };

  @override
  void visitCatchClause(CatchClause node) {
    final TypeAnnotation? typeAnnotation = node.exceptionType;
    if (typeAnnotation is! NamedType) {
      super.visitCatchClause(node);
      return;
    }
    final String typeName = typeAnnotation.name.lexeme;
    if (_siblingRuleNames.contains(typeName) ||
        sanctionedBases.contains(typeName)) {
      super.visitCatchClause(node);
      return;
    }
    final DartType? dartType = typeAnnotation.type;
    if (dartType is! InterfaceType) {
      super.visitCatchClause(node);
      return;
    }
    final InterfaceElement element = dartType.element;
    if (element is! ClassElement || !element.isAbstract) {
      super.visitCatchClause(node);
      return;
    }
    if (!_isExceptionLike(dartType)) {
      super.visitCatchClause(node);
      return;
    }
    report(
      ruleName: 'avoid_catching_abstract_exception',
      message:
          'Avoid catching abstract base "$typeName". '
          'Enumerate the concrete subclasses the call path actually '
          'throws — see error-handling.md.',
      offset: typeAnnotation.name.charOffset,
    );
    super.visitCatchClause(node);
  }

  /// Returns `true` when [type] is `Exception` itself or has `Exception`
  /// somewhere in its supertype chain — limits the rule's scope to
  /// exception bases (not abstract domain values that happen to be
  /// abstract for unrelated reasons).
  bool _isExceptionLike(InterfaceType type) {
    if (type.element.name == 'Exception') {
      return true;
    }
    for (final InterfaceType supertype in type.allSupertypes) {
      if (supertype.element.name == 'Exception') {
        return true;
      }
    }
    return false;
  }
}
