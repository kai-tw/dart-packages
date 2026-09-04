import 'package:dart_mutants/src/runner/file_mutation_report.dart';
import 'package:dart_mutants/src/runner/mutant_result.dart';
import 'package:dart_mutants/src/runner/mutation_run_report.dart';
import 'package:test/test.dart';

FileMutationReport _report(String filePath) => FileMutationReport(
  filePath: filePath,
  detected: 1,
  undetected: 0,
  invalid: 0,
  timedOut: 0,
  undetectedMutants: const <MutantResult>[],
  timedOutMutants: const <MutantResult>[],
);

void main() {
  group('.aborted', () {
    test(
      '[partition] carries the reason, and files is empty — an aborted run '
      'never scored anything',
      () {
        const MutationRunReport report = MutationRunReport.aborted(
          'the test command failed against unmodified code',
        );

        expect(report.aborted, isTrue);
        expect(
          report.abortReason,
          'the test command failed against unmodified code',
        );
        expect(report.files, isEmpty);
      },
    );

    test(
      '[boundary] toJson includes abortReason and an empty files map',
      () {
        const MutationRunReport report = MutationRunReport.aborted('red');

        expect(report.toJson(), <String, Object?>{
          'abortReason': 'red',
          'files': <String, Object?>{},
        });
      },
    );
  });

  group('.completed', () {
    test('[partition] aborted is false and abortReason is null', () {
      final MutationRunReport report = MutationRunReport.completed(
        <FileMutationReport>[_report('lib/src/foo.dart')],
      );

      expect(report.aborted, isFalse);
      expect(report.abortReason, isNull);
      expect(report.files, hasLength(1));
    });

    test(
      '[boundary] toJson omits the abortReason key entirely — not just '
      'null — and keys files by their own filePath',
      () {
        final MutationRunReport report = MutationRunReport.completed(
          <FileMutationReport>[_report('lib/src/foo.dart')],
        );

        final Map<String, Object?> json = report.toJson();
        expect(json.containsKey('abortReason'), isFalse);
        expect(
          (json['files']! as Map<String, Object?>).keys,
          <String>['lib/src/foo.dart'],
        );
      },
    );
  });
}
