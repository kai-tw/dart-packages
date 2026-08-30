/// The shape a rule option must take in YAML.
///
/// Declared rather than inferred so a wrong-typed value is caught while reading
/// the config. Left to the rule's constructor it would surface as a `TypeError`
/// — an `Error`, not an `Exception` — escaping the analysis-phase guards and
/// ending the run in a raw Dart stack instead of a message naming the key.
enum OptionKind {
  /// A single scalar, e.g. `scope: app`.
  string,

  /// A list of scalars, e.g. `layers: [domain, data, presentation]`.
  stringList,

  /// A list of maps, e.g. `reservedSuffixes: [{suffix: Sheet, unless: …}]`.
  mapList,

  /// A single whole number, e.g. `maxComplexity: 6`.
  integer,
}

/// The registry's entry for one rule: its identity, the bundle it ships in, the
/// options it accepts, and how to build it.
///
/// [options] is what makes a mistyped key a hard error rather than a silent
/// no-op. Without it, `layer:` written for `layers:` yields an empty layer list
/// and a rule that quietly passes everything — the one failure mode a linter
/// cannot detect about itself.
class RuleDescriptor {
  const RuleDescriptor({
    required this.name,
    required this.bundle,
    required this.create,
    this.options = const <String, OptionKind>{},
    this.requiredOptions = const <String>{},
  });

  final String name;
  final String bundle;
  final Map<String, OptionKind> options;

  /// Keys in [options] that must be present in the merged view — after area
  /// overrides are resolved — for this rule to be enabled.
  ///
  /// [options] alone only catches a wrong-typed value; a key that is simply
  /// absent sails through it and reaches [create] as `null`, which fails as
  /// a raw [TypeError] instead of a message naming the rule and the option —
  /// the same silent-failure shape [options] itself exists to prevent.
  final Set<String> requiredOptions;

  /// Builds the rule from its already-validated options.
  final Object Function(Map<String, Object?> options) create;
}
