import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Forbids any file under the app's `lib/` from importing the dev-only
/// `novel_glide_harness_support` package.
///
/// That package is the shared render + data-mocking foundation for the dev
/// render harnesses (`tool/screenshots`, `tool/design_mockups`). It is an
/// **app-dependent dev_dependency**: it depends on `flutter_test`,
/// `bloc_test`, and `mocktail`. A single
/// `lib/ -> package:novel_glide_harness_support` import would drag that test
/// scaffolding into the production compilation root — breaking the release
/// build or bloating the bundle.
///
/// The sibling `avoid_tool_imports_in_lib` only catches *relative*
/// `lib -> tool/` imports — it early-returns on `package:` URIs, so it cannot
/// see this `package:`-form import. This rule closes that gap and makes the
/// one-way boundary `tool/ -> harness -> novel_glide` a hard lint error rather
/// than a convention.
///
/// Scope: registered only for `Zone.production` in `runner.dart` —
/// `tool/`/`integration_test/`/`patrol_test/` are the package's sanctioned
/// consumers and `test/` is its intended future one, so this rule does not
/// scope itself to a directory.
///
/// **Bad** (in `lib/`):
/// ```dart
/// import 'package:novel_glide_harness_support/novel_glide_harness_support.dart';
/// ```
class NovelglideAvoidHarnessSupportImportsInLib extends LintRule {
  @override
  String get name => 'novelglide_avoid_harness_support_imports_in_lib';

  @override
  String get description =>
      'Files under lib/ must not import package:novel_glide_harness_support '
      '(dev-only render-harness support). Keep test-support dependencies out '
      'of the production compilation root.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source);
}

const String _harnessPackageUri = 'package:novel_glide_harness_support';

class _Visitor extends LintVisitor {
  _Visitor(super.filePath, super.lineInfo, super.source);

  @override
  void visitImportDirective(ImportDirective node) {
    final String? uri = node.uri.stringValue;
    if (uri == null || !uri.startsWith(_harnessPackageUri)) {
      return;
    }

    report(
      ruleName: 'novelglide_avoid_harness_support_imports_in_lib',
      message:
          'lib/ code must not import $_harnessPackageUri ($uri). It is a '
          'dev-only render-harness support package (depends on '
          'flutter_test / bloc_test / mocktail) and must never enter the '
          'production compilation root. Import it only from tool/.',
      offset: node.uri.offset,
    );
  }
}
