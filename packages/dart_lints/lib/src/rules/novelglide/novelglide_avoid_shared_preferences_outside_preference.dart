import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when a Dart file imports `package:shared_preferences/...` from
/// outside the preference feature's data layer or the migration
/// processes.
///
/// `architecture.md` makes the preference feature the single owner of
/// `SharedPreferences`. Other features must take a typed
/// `PreferenceRepository<T>` so the key namespace, observability, and
/// reset-to-default behavior are uniform across the app.
class NovelglideAvoidSharedPreferencesOutsidePreference extends LintRule {
  @override
  String get name => 'novelglide_avoid_shared_preferences_outside_preference';

  @override
  String get description =>
      'shared_preferences may only be imported by the preference feature '
      'data layer and migration processes.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source);
}

class _Visitor extends LintVisitor {
  _Visitor(super.filePath, super.lineInfo, super.source);

  static final RegExp _allowedPath = RegExp(
    r'(?:^|/)(?:'
    r'features/preference/'
    r'|features/migration/processes/'
    r'|core/setup_dependencies\.dart$'
    r')',
  );

  bool get _isAllowedFile =>
      _allowedPath.hasMatch(filePath) || filePath.endsWith('lib/main.dart');

  @override
  void visitImportDirective(ImportDirective node) {
    if (_isAllowedFile) {
      return;
    }
    final String? uri = node.uri.stringValue;
    if (uri != null && uri.startsWith('package:shared_preferences/')) {
      report(
        ruleName: 'novelglide_avoid_shared_preferences_outside_preference',
        message:
            'shared_preferences must be accessed via PreferenceRepository<T> '
            '(features/preference). Direct imports outside the preference '
            'feature break the single-owner contract.',
        offset: node.uri.offset,
      );
    }
  }
}
