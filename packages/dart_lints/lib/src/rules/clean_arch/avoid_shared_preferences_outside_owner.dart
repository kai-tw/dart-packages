import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when a Dart file imports `package:shared_preferences/...` from
/// outside the paths that own it.
///
/// A key-value store with two owners has no key namespace: any file can
/// mint any key, nothing can enumerate what the app persists, and
/// "reset this domain to its defaults" has no single place to live.
/// Naming an owner is what lets everything else take a typed repository
/// instead, and the rule is what keeps the second owner from appearing
/// by accident.
///
/// **Bad** (outside an owner path):
/// ```dart
/// import 'package:shared_preferences/shared_preferences.dart';
/// ```
///
/// **Good:**
/// ```dart
/// import 'package:my_app/core/preferences/preference_repository.dart';
/// ```
///
/// Scoped by the [ownerPaths] option.
class AvoidSharedPreferencesOutsideOwner extends LintRule {
  AvoidSharedPreferencesOutsideOwner({List<String>? ownerPaths})
    : ownerPaths = ownerPaths ?? const <String>[];

  /// Path fragments whose files may import the package.
  ///
  /// Matched with `contains`, against a path using forward slashes — so
  /// `core/preferences/` names a directory, `lib/main.dart` names a file, and
  /// either may appear.
  ///
  /// **Empty means no file is an owner, so every import is reported.** The
  /// alternative — treating "unconfigured" as "allow everything" — would make
  /// enabling the rule look like it had passed while it was in fact inert, and
  /// a linter that silently excuses is the one failure it cannot report about
  /// itself. An unconfigured run is loud instead, and the noise names exactly
  /// the paths that need listing.
  final List<String> ownerPaths;

  @override
  String get name => 'avoid_shared_preferences_outside_owner';

  @override
  String get description =>
      'shared_preferences may only be imported by the paths named in '
      'ownerPaths.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source, ownerPaths);
}

class _Visitor extends LintVisitor {
  _Visitor(super.filePath, super.lineInfo, super.source, this.ownerPaths);

  final List<String> ownerPaths;

  bool get _isOwner => ownerPaths.any(filePath.contains);

  @override
  void visitImportDirective(ImportDirective node) {
    if (_isOwner) {
      return;
    }
    final String? uri = node.uri.stringValue;
    if (uri != null && uri.startsWith('package:shared_preferences/')) {
      report(
        ruleName: 'avoid_shared_preferences_outside_owner',
        message:
            'shared_preferences must be reached through the preference layer '
            'that owns it. Direct imports outside ownerPaths break the '
            'single-owner contract.',
        offset: node.uri.offset,
      );
    }
  }
}
