import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:dart_lints/src/lint_rule_base.dart';
import 'package:dart_lints/src/rules/core/avoid_catching_abstract_exception.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Resolved units, because the rule asks the element model whether a caught
/// type is abstract and whether `Exception` is in its supertype chain. A
/// parsed AST answers neither.
const String _fixture = r'''
abstract class StorageException implements Exception {}

class StorageOfflineException extends StorageException {}

abstract class DatabaseException implements Exception {}

abstract class Shape {}

void run(void Function() body) {
  try {
    body();
  } on StorageOfflineException {
    // concrete
  }
  try {
    body();
  } on StorageException {
    // abstract, exception-like
  }
  try {
    body();
  } on DatabaseException {
    // abstract, exception-like, and the one a library may leave unexported
  }
  try {
    body();
  } on Shape {
    // abstract, but nothing to do with exceptions
  }
  try {
    body();
  } on Exception {
    // avoid_catching_base_exception's job, not this rule's
  }
}
''';

/// The 1-based line each `on` clause sits on, found by its type name so an
/// edit to the fixture cannot point an expectation at the wrong clause.
int _lineOf(String typeName) {
  final List<String> lines = _fixture.split('\n');
  for (int i = 0; i < lines.length; i++) {
    // The clause shares its line with the closing brace of the `try`.
    if (lines[i].trim().endsWith('on $typeName {')) {
      return i + 1;
    }
  }
  throw ArgumentError('no `on $typeName` clause in the fixture');
}

Future<Set<String>> _reportedTypes({List<String>? sanctionedBases}) async {
  final Directory root = Directory.systemTemp.createTempSync(
    'avoid_catching_abstract_exception_',
  );
  addTearDown(() => root.deleteSync(recursive: true));

  final String subject = p.join(root.path, 'subject.dart');
  File(subject).writeAsStringSync(_fixture);

  final AnalysisContextCollection collection = AnalysisContextCollection(
    includedPaths: <String>[root.path],
  );
  final SomeResolvedUnitResult result = await collection
      .contextFor(subject)
      .currentSession
      .getResolvedUnit(subject);
  if (result is! ResolvedUnitResult) {
    fail('fixture did not resolve — the rule would report nothing');
  }

  final AvoidCatchingAbstractException rule = AvoidCatchingAbstractException(
    sanctionedBases: sanctionedBases,
  );
  final ResolvedLintVisitor visitor = rule.createResolvedVisitor(
    'subject.dart',
    result,
  );
  result.unit.accept(visitor);

  // Reported clauses named by their type, via the line they sit on — the
  // message is prose and the offset is a number, neither of which reads as an
  // assertion.
  return <String>{
    for (final String type in <String>[
      'StorageOfflineException',
      'StorageException',
      'DatabaseException',
      'Shape',
      'Exception',
    ])
      if (visitor.violations.any(
        (LintViolation v) => v.line == _lineOf(type),
      ))
        type,
  };
}

void main() {
  test('reports abstract exception bases and nothing else', () async {
    expect(await _reportedTypes(), <String>{
      'StorageException',
      'DatabaseException',
    });
  });

  test('a sanctioned base is accepted, its siblings are not', () async {
    // The point of the option: a library that exports only its abstract base
    // leaves a consumer nothing narrower to name, and that boundary can be
    // declared without switching the rule off for the whole file.
    expect(
      await _reportedTypes(sanctionedBases: <String>['DatabaseException']),
      <String>{'StorageException'},
    );
  });

  test('sanctioning one base does not sanction the rest', () async {
    expect(
      await _reportedTypes(sanctionedBases: <String>['StorageException']),
      <String>{'DatabaseException'},
    );
  });

  test('an unknown name in the list changes nothing', () async {
    // A typo must not silently widen the rule, and must not narrow it either.
    expect(
      await _reportedTypes(sanctionedBases: <String>['DatabaseExcepion']),
      <String>{'StorageException', 'DatabaseException'},
    );
  });
}
