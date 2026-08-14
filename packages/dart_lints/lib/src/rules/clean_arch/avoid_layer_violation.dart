import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

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
class AvoidLayerViolation extends LintRule {
  AvoidLayerViolation({
    List<String>? featureRoots,
    List<String>? layers,
    List<String>? exemptFiles,
  }) : layout = FeatureLayout(roots: featureRoots, layers: layers),
       exemptFiles = exemptFiles ?? const <String>[];

  final FeatureLayout layout;

  /// Files that wire every layer by design, so crossing a boundary is their
  /// job rather than a defect.
  final List<String> exemptFiles;

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
  ) => _Visitor(filePath, lineInfo, source, layout, exemptFiles);
}

class _Visitor extends LintVisitor {
  _Visitor(
    super.filePath,
    super.lineInfo,
    super.source,
    this.layout,
    this.exemptFiles,
  );

  final FeatureLayout layout;
  final List<String> exemptFiles;

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

    final String? sourceLayer = layout.layerOf(filePath);
    final String? importLayer = layout.layerOf(importUri);

    if (sourceLayer == null || importLayer == null) {
      super.visitImportDirective(node);
      return;
    }

    final bool isViolation = switch ((sourceLayer, importLayer)) {
      ('domain', 'data') => true,
      ('domain', 'presentation') => true,
      ('presentation', 'data') => true,
      ('data', 'presentation') => true,
      _ => false,
    };

    if (isViolation) {
      report(
        ruleName: 'avoid_layer_violation',
        message:
            'Layer violation: $sourceLayer/ must not import from '
            '$importLayer/.',
        offset: node.uri.offset,
      );
    }

    super.visitImportDirective(node);
  }
}
