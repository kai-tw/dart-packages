import 'package:dart_mutants/src/mutant.dart';
import 'package:dart_mutants/src/runner/file_mutation_report.dart';
import 'package:dart_mutants/src/runner/mutant_result.dart';
import 'package:dart_mutants/src/runner/mutant_verdict.dart';
import 'package:test/test.dart';

Mutant _mutant(int line) => Mutant(
  filePath: 'lib/src/foo.dart',
  offset: 10,
  length: 1,
  line: line,
  column: 1,
  original: 'true',
  replacement: 'false',
  operatorName: 'condition_negation',
  description: 'true -> false',
);

void main() {
  test(
    '[partition] total is detected + undetected — invalid and timedOut are '
    'deliberately not folded in',
    () {
      const FileMutationReport report = FileMutationReport(
        filePath: 'lib/src/foo.dart',
        detected: 3,
        undetected: 2,
        invalid: 10,
        timedOut: 5,
        undetectedMutants: <MutantResult>[],
        timedOutMutants: <MutantResult>[],
      );

      expect(report.total, 5);
    },
  );

  group('detectionRate', () {
    test('[boundary] is null when total is 0 — 0/0 is not 1.0', () {
      const FileMutationReport report = FileMutationReport(
        filePath: 'lib/src/foo.dart',
        detected: 0,
        undetected: 0,
        invalid: 4,
        timedOut: 0,
        undetectedMutants: <MutantResult>[],
        timedOutMutants: <MutantResult>[],
      );

      expect(report.detectionRate, isNull);
    });

    test('[partition] is detected / total when there is at least one', () {
      const FileMutationReport report = FileMutationReport(
        filePath: 'lib/src/foo.dart',
        detected: 3,
        undetected: 1,
        invalid: 0,
        timedOut: 0,
        undetectedMutants: <MutantResult>[],
        timedOutMutants: <MutantResult>[],
      );

      expect(report.detectionRate, 0.75);
    });
  });

  test(
    '[partition] toJson carries total plus every count, and both mutant '
    'lists rendered as their own JSON, not the raw objects',
    () {
      final MutantResult undetected = MutantResult(
        mutant: _mutant(7),
        verdict: MutantVerdict.undetected,
      );
      final MutantResult timedOut = MutantResult(
        mutant: _mutant(9),
        verdict: MutantVerdict.timeout,
      );
      final FileMutationReport report = FileMutationReport(
        filePath: 'lib/src/foo.dart',
        detected: 1,
        undetected: 1,
        invalid: 2,
        timedOut: 1,
        undetectedMutants: <MutantResult>[undetected],
        timedOutMutants: <MutantResult>[timedOut],
      );

      expect(report.toJson(), <String, Object?>{
        'filePath': 'lib/src/foo.dart',
        'total': 2,
        'detected': 1,
        'undetected': 1,
        'invalid': 2,
        'timedOut': 1,
        'undetectedMutants': <Object?>[undetected.toJson()],
        'timedOutMutants': <Object?>[timedOut.toJson()],
      });
    },
  );
}
