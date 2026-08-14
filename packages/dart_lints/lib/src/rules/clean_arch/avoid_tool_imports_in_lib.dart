import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;

import '../../lint_rule_base.dart';

/// Forbids any file under `lib/` from importing code under the
/// repository's sibling `tool/` directory (e.g. `tool/screenshots/`).
///
/// `tool/` holds developer-only tooling — the golden-render screenshot
/// harness — that depends on dev_dependencies (`flutter_test`,
/// `bloc_test`, `mocktail`). Nothing reachable from `lib/main.dart` may
/// pull it in: a single `lib/ -> tool/` import would either break the
/// release build (dev deps unresolvable from production code) or drag
/// test scaffolding toward the app bundle. The directory boundary and
/// the dev-dependency wall already make accidental contamination loud,
/// but this rule makes the boundary a hard lint error rather than a
/// convention.
class AvoidToolImportsInLib extends LintRule {
  AvoidToolImportsInLib({String? sourceRoot, String? forbiddenRoot})
    : sourceRoot = sourceRoot ?? 'lib',
      forbiddenRoot = forbiddenRoot ?? 'tool';

  /// The production compilation root this rule protects.
  final String sourceRoot;

  /// The sibling directory it must not reach into.
  final String forbiddenRoot;

  @override
  String get name => 'avoid_tool_imports_in_lib';

  @override
  String get description =>
      'Files under / must not import / (developer-only '
      'tooling). Keep dev-only tooling out of the production compilation root.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source, sourceRoot, forbiddenRoot);
}

class _Visitor extends LintVisitor {
  _Visitor(
    super.filePath,
    super.lineInfo,
    super.source,
    this.sourceRoot,
    this.forbiddenRoot,
  );

  final String sourceRoot;
  final String forbiddenRoot;

  @override
  void visitImportDirective(ImportDirective node) {
    // Locate the importing file's own `lib/` so the project root is
    // derived from the file under analysis, not from a stray `lib`
    // segment elsewhere in the absolute path.
    final List<String> fileSegments = p.split(filePath);
    final int libIndex = fileSegments.lastIndexOf(sourceRoot);
    if (libIndex < 0) {
      return; // not under a lib/ directory — rule is lib-scoped
    }

    final String? uri = node.uri.stringValue;
    // Only relative imports can reach the sibling tool/: it is not part
    // of any package, so `package:` / `dart:` URIs never resolve into it.
    if (uri == null || uri.startsWith('package:') || uri.startsWith('dart:')) {
      return;
    }

    // Project root = the path up to (not including) the importing file's
    // `lib/`. With an absolute filePath this is unconditionally correct; with
    // a relative filePath the resolution below is relative to the CWD, which
    // is the project root under the documented `dart run dart_lints`
    // contract.
    // review-dismiss: the CWD assumption is the runner's documented contract.
    final String projectRoot = p.joinAll(fileSegments.sublist(0, libIndex));
    final String toolRoot = p.join(projectRoot, forbiddenRoot);
    final String resolved = p.normalize(p.join(p.dirname(filePath), uri));

    if (p.equals(toolRoot, resolved) || p.isWithin(toolRoot, resolved)) {
      report(
        ruleName: 'avoid_tool_imports_in_lib',
        message:
            'lib/ code must not import tool/ ($uri). tool/ is dev-only '
            'tooling (depends on dev_dependencies) and must never enter the '
            'production compilation root.',
        offset: node.uri.offset,
      );
    }
  }
}
