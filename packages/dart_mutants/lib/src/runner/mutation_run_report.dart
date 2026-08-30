import 'file_mutation_report.dart';

/// The outcome of one whole run: why it stopped, if it stopped before
/// scoring anything, or the per-file scores if it ran to completion.
class MutationRunReport {
  const MutationRunReport.aborted(this.abortReason)
    : files = const <FileMutationReport>[];

  const MutationRunReport.completed(this.files) : abortReason = null;

  /// Non-null only when the run never produced any scores at all — the
  /// baseline test suite was already red (see `MutationTestRunner`'s
  /// pre-flight check). A partial run still completes normally: a mutant
  /// that could not be scored is `invalid`, not an abort.
  final String? abortReason;

  final List<FileMutationReport> files;

  bool get aborted => abortReason != null;

  Map<String, Object?> toJson() => <String, Object?>{
    if (abortReason != null) 'abortReason': abortReason,
    'files': <String, Object?>{
      for (final FileMutationReport f in files) f.filePath: f.toJson(),
    },
  };
}
