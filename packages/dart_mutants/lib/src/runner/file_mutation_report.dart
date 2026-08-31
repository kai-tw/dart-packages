import 'mutant_result.dart';

/// One file's mutants, scored.
///
/// [total] is [detected] + [undetected] — [invalid] and [timedOut] are
/// deliberately not folded in. Neither was a real question about this
/// file's tests, so counting either either way would move the score without
/// the tests having done anything to earn or lose it. They still matter as
/// a signal of their own, separate from the score: a file where most
/// candidates ended up `invalid` has a hollow-looking 100% the same way a
/// file with only one real mutant does — a policy layer comparing
/// `invalid`/`timedOut` against `total` is how that gets caught, which is
/// exactly why both stay in this report instead of being summed away.
///
/// **That comparison tells a caller THAT something went unmeasured, never
/// WHICH.** For the timed-out ones that is the difference between a number
/// and a gap somebody can act on, so [timedOutMutants] carries their
/// identities too. `invalid` deliberately gets no such list: an invalid
/// mutant is not legal code and never needed measuring, so there is nothing
/// there to go and look at.
class FileMutationReport {
  const FileMutationReport({
    required this.filePath,
    required this.detected,
    required this.undetected,
    required this.invalid,
    required this.timedOut,
    required this.undetectedMutants,
    required this.timedOutMutants,
  });

  final String filePath;
  final int detected;
  final int undetected;
  final int invalid;
  final int timedOut;

  /// The actual survivors, not just their count — a policy layer deciding
  /// pass/fail per file needs to show a person which ones, so they can write
  /// down why each is acceptable (an equivalent mutant, say) or fix the gap.
  final List<MutantResult> undetectedMutants;

  /// The mutants that ran out of time, not just how many.
  ///
  /// A timed-out mutant is **real code that went unmeasured**, which is the
  /// difference between it and an `invalid` one — an invalid mutant is not
  /// legal code and never needed measuring. So this is the gap a caller can
  /// actually act on, and a count alone does not let them: it says something
  /// went unmeasured without saying what, so nobody can look at it, and across
  /// runs nobody can see it is the same one every time.
  ///
  /// Measured: a file carried a mutant that timed out on **every** round, was
  /// therefore never scored once, and stayed invisible behind a number that no
  /// caller reads per-mutant. The class doc above used to claim that comparing
  /// `timedOut` against `total` is how that gets caught; that is only half
  /// true, and this list is the other half.
  final List<MutantResult> timedOutMutants;

  int get total => detected + undetected;

  /// `null` when [total] is 0 — a file with no mutants at all has no rate to
  /// report, and `0/0` is not `1.0`.
  double? get detectionRate => total == 0 ? null : detected / total;

  Map<String, Object?> toJson() => <String, Object?>{
    'filePath': filePath,
    'total': total,
    'detected': detected,
    'undetected': undetected,
    'invalid': invalid,
    'timedOut': timedOut,
    'undetectedMutants': undetectedMutants
        .map((MutantResult r) => r.toJson())
        .toList(),
    'timedOutMutants': timedOutMutants
        .map((MutantResult r) => r.toJson())
        .toList(),
  };
}
