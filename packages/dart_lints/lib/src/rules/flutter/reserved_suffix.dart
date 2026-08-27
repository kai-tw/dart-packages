/// One reserved suffix, why it is reserved, and the longer name that is the
/// exception to it.
///
/// A flat list of suffix strings cannot express this. `Sheet` is reserved only
/// when it is *bare* — `BottomSheet` is the spelling the rule steers toward —
/// and each suffix needs its own guidance, because "rename to View /
/// Placeholder / Indicator" is useless advice for a class named `FooCubit`.
class ReservedSuffix {
  const ReservedSuffix({required this.suffix, required this.hint, this.unless});

  factory ReservedSuffix.fromMap(Map<String, Object?> map) => ReservedSuffix(
    suffix: map['suffix']! as String,
    hint: map['hint']! as String,
    unless: map['unless'] as String?,
  );

  final String suffix;
  final String hint;

  /// A longer suffix that is the sanctioned form, so it must not be reported.
  final String? unless;

  bool matches(String name) =>
      name.endsWith(suffix) && !(unless != null && name.endsWith(unless!));
}
