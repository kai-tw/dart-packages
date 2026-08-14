/// Where a project keeps its layered features, and what its layers are called.
///
/// Four rules in this bundle ask the same question of a path — "which layer is
/// this, if any?" — so the answer lives here once. Each of them used to carry
/// its own copy of the pattern with `lib/features` written into it, which is
/// how a second layered root (`lib/modules`) can exist in a project and be
/// governed by none of them.
///
/// **A path that matches no root, or a directory under a root that is not a
/// layer, resolves to null and is passed.** That is deliberate, not an
/// oversight: real projects keep unlayered feature folders (`models/`,
/// `widgets/`) beside layered ones, and a layout rule has nothing to say about
/// a file whose layer it cannot identify.
class FeatureLayout {
  FeatureLayout({List<String>? roots, List<String>? layers})
    : roots = roots ?? const <String>['lib/features'],
      layers = layers ?? const <String>['domain', 'data', 'presentation'];

  final List<String> roots;
  final List<String> layers;

  late final RegExp _layerPattern = RegExp(
    '(?:^|/)(?:${roots.map(RegExp.escape).join('|')})'
    '/[^/]+/(${layers.map(RegExp.escape).join('|')})/',
  );

  /// The layer [path] sits in, or null when it sits in none.
  String? layerOf(String path) => _layerPattern.firstMatch(path)?.group(1);

  /// Whether [path] is inside [layer] of some feature, optionally within a
  /// further [subdirectory] of it (`domain/exceptions/`).
  bool isIn(String path, String layer, {String? subdirectory}) {
    final String tail = subdirectory == null
        ? ''
        : '${RegExp.escape(subdirectory)}/';
    return RegExp(
      '(?:^|/)(?:${roots.map(RegExp.escape).join('|')})'
      '/[^/]+/${RegExp.escape(layer)}/$tail',
    ).hasMatch(path);
  }
}
