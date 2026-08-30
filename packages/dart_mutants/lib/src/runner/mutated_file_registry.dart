import 'dart:async';
import 'dart:io';

/// Tracks every file currently sitting on disk in a mutated state, so it can
/// be put back the moment something goes wrong — a real incident, not a
/// hypothetical: a `mutation_test` run killed by a timeout once left a
/// parameter-swap mutation sitting in a NovelGlide file's working tree. That
/// one happened to fail to compile, which is how it got noticed; most
/// mutants compile fine, so most would not have been.
///
/// [armSignalRestore] catches `SIGINT` (Ctrl-C) and `SIGTERM` (what `kill`
/// sends by default, and what most timeout wrappers send before escalating)
/// and restores everything tracked before the process exits. It cannot catch
/// `SIGKILL` — no process can, by design of the signal itself — so a `kill
/// -9` or an immediate-hard-kill timeout wrapper is still a real gap. Nothing
/// short of not writing mutated content to the real file at all closes that
/// gap completely, and this package writes to the real file because the test
/// command needs to see it there. Restoring after every individual mutant
/// (rather than only at the very end) is the actual mitigation: at any
/// moment during a run, at most one file is in a mutated state.
class MutatedFileRegistry {
  final Map<String, String> _originalContent = <String, String>{};
  StreamSubscription<ProcessSignal>? _sigintSubscription;
  StreamSubscription<ProcessSignal>? _sigtermSubscription;

  bool get isArmed => _sigintSubscription != null;

  /// Starts watching for `SIGINT`/`SIGTERM`. Idempotent — calling it twice
  /// does not double-register.
  void armSignalRestore() {
    if (isArmed) {
      return;
    }
    _sigintSubscription = ProcessSignal.sigint.watch().listen(
      (ProcessSignal _) => _onSignal(),
    );
    try {
      _sigtermSubscription = ProcessSignal.sigterm.watch().listen(
        (ProcessSignal _) => _onSignal(),
      );
    } on SignalException catch (e) {
      // Not every platform can watch SIGTERM (Windows cannot). Worth saying
      // out loud, not just silently degrading — SIGINT alone still covers
      // interactive Ctrl-C, but a `kill`/timeout wrapper that sends SIGTERM
      // will not trigger a restore on this run.
      stderr.writeln(
        'dart_mutants: cannot watch SIGTERM on this platform (${e.message}) '
        '— only SIGINT (Ctrl-C) will trigger a restore.',
      );
    }
  }

  void _onSignal() {
    restoreAll();
    exit(1);
  }

  /// Records [originalContent] for [filePath] the first time it is mutated,
  /// so [restore] knows what to put back regardless of how many mutants run
  /// against that file across a whole session.
  void track(String filePath, String originalContent) {
    _originalContent.putIfAbsent(filePath, () => originalContent);
  }

  /// Writes [filePath]'s tracked original content back and stops tracking
  /// it. A no-op if [filePath] was never tracked or was already restored.
  void restore(String filePath) {
    final String? original = _originalContent.remove(filePath);
    if (original != null) {
      File(filePath).writeAsStringSync(original);
    }
  }

  /// Restores every currently-tracked file. Safe to call from a signal
  /// handler: synchronous, and touches only files this registry itself
  /// wrote.
  void restoreAll() {
    for (final MapEntry<String, String> entry in _originalContent.entries) {
      File(entry.key).writeAsStringSync(entry.value);
    }
    _originalContent.clear();
  }

  /// Stops watching signals. Call once a run has finished normally.
  Future<void> disarm() async {
    await _sigintSubscription?.cancel();
    await _sigtermSubscription?.cancel();
    _sigintSubscription = null;
    _sigtermSubscription = null;
  }
}
