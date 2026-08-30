import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;

import '../../lint_rule_base.dart';
import 'feature_layout.dart';

/// Warns when a file imports from a forbidden architecture layer.
///
/// Clean Architecture dependency rule: `presentation -> domain <- data`.
/// - `domain/` must not import from `data/` or `presentation/`.
/// - `presentation/` must not import from `data/`.
/// - `data/` must not import from `presentation/`.
///
/// `setup_dependencies.dart` files are exempt — they wire all layers.
///
/// **[packageName] is what makes this rule fire at all in a project that
/// requires `package:` imports** (`always_use_package_imports`, or just house
/// style — the common case). An import URI never contains a literal `lib/`:
/// a relative import omits the whole prefix, and a `package:` import replaces
/// it with the package name — `package:myapp/features/x/domain/y.dart`, not
/// `package:myapp/lib/features/x/domain/y.dart`. Comparing that URI directly
/// against a path pattern built around `lib/features/...` therefore never
/// matches, on either side of the fraction that uses `package:` imports —
/// every violation in such a codebase reads as a no-op, silently, forever,
/// with the rule reporting nothing to say it never engaged. [packageName]
/// lets a self `package:<name>/...` import resolve back to `lib/...` before
/// that comparison; [DartLintsConfigLoader] fills it in automatically from
/// the consuming project's own `pubspec.yaml`, so most consumers never set it
/// by hand. An import of any *other* package is never a layer violation and
/// is left alone, matched or not.
class AvoidLayerViolation extends LintRule {
  AvoidLayerViolation({
    List<String>? featureRoots,
    List<String>? layers,
    List<String>? exemptFiles,
    this.packageName,
  }) : layout = FeatureLayout(roots: featureRoots, layers: layers),
       exemptFiles = exemptFiles ?? const <String>[];

  final FeatureLayout layout;

  /// Files that wire every layer by design, so crossing a boundary is their
  /// job rather than a defect.
  final List<String> exemptFiles;

  /// This project's own package name, so a self `package:` import can be told
  /// apart from a dependency's. See the class doc for why this is load-bearing.
  final String? packageName;

  @override
  String get name => 'avoid_layer_violation';

  @override
  String get description =>
      'Avoid importing across architecture layers. '
      'presentation -> domain <- data.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source, layout, exemptFiles, packageName);
}

class _Visitor extends LintVisitor {
  _Visitor(
    super.filePath,
    super.lineInfo,
    super.source,
    this.layout,
    this.exemptFiles,
    this.packageName,
  );

  final FeatureLayout layout;
  final List<String> exemptFiles;
  final String? packageName;

  /// The project-relative path [importUri] refers to, as something
  /// [FeatureLayout.layerOf] can compare against a source file's own path —
  /// or null when [importUri] cannot refer to a file in this project at all
  /// (`dart:`, or a `package:` importing anything other than [packageName]).
  String? _resolveImportPath(String importUri) {
    if (importUri.startsWith('package:')) {
      final String rest = importUri.substring('package:'.length);
      final int slash = rest.indexOf('/');
      if (slash == -1) {
        return null;
      }
      final String importedPackage = rest.substring(0, slash);
      if (packageName == null || importedPackage != packageName) {
        return null;
      }
      return p.posix.join('lib', rest.substring(slash + 1));
    }
    if (importUri.contains(':')) {
      // dart:, or another URI scheme this rule has no opinion about.
      return null;
    }
    return p.posix.normalize(
      p.posix.join(p.posix.dirname(filePath), importUri),
    );
  }

  /// The (source, imported) layer pair to compare, or null when either side
  /// of [importUri] does not resolve to one of the four recognised layers —
  /// mirrors [_resolveImportPath]'s own null-when-inapplicable shape.
  _LayerPair? _layersToCompare(String importUri) {
    final String? resolvedImportPath = _resolveImportPath(importUri);
    final String? sourceLayer = layout.layerOf(filePath);
    final String? importLayer = resolvedImportPath == null
        ? null
        : layout.layerOf(resolvedImportPath);
    if (sourceLayer == null || importLayer == null) {
      return null;
    }
    return _LayerPair(sourceLayer: sourceLayer, importLayer: importLayer);
  }

  /// The Clean Architecture dependency rule this rule enforces — see the
  /// class doc for the direction rules this switch encodes.
  bool _isViolation(_LayerPair layers) =>
      switch ((layers.sourceLayer, layers.importLayer)) {
        ('domain', 'data') => true,
        ('domain', 'presentation') => true,
        ('presentation', 'data') => true,
        ('data', 'presentation') => true,
        _ => false,
      };

  @override
  void visitImportDirective(ImportDirective node) {
    // A wiring container crosses every layer by design.
    if (exemptFiles.any(filePath.endsWith)) {
      super.visitImportDirective(node);
      return;
    }

    final String? importUri = node.uri.stringValue;
    if (importUri == null) {
      super.visitImportDirective(node);
      return;
    }

    final _LayerPair? layers = _layersToCompare(importUri);
    if (layers == null) {
      super.visitImportDirective(node);
      return;
    }

    if (_isViolation(layers)) {
      report(
        ruleName: 'avoid_layer_violation',
        message:
            'Layer violation: ${layers.sourceLayer}/ must not import from '
            '${layers.importLayer}/.',
        offset: node.uri.offset,
      );
    }

    super.visitImportDirective(node);
  }
}

/// The (source, imported) layer pair a single import is checked against.
class _LayerPair {
  const _LayerPair({required this.sourceLayer, required this.importLayer});

  final String sourceLayer;
  final String importLayer;
}
