import '../hlc/hlc.dart';
import 'sync_entity_presence.dart';

/// One side of a sync, reduced to what conflict detection actually needs.
class SyncSideState {
  const SyncSideState({
    required this.presence,
    this.createdHlc,
    this.deletedHlc,
    this.fieldHlcs = const <String, Hlc>{},
  });

  /// The state of a side that has never heard of this record.
  const SyncSideState.untracked()
    : presence = SyncEntityPresence.untracked,
      createdHlc = null,
      deletedHlc = null,
      fieldHlcs = const <String, Hlc>{};

  final SyncEntityPresence presence;
  final Hlc? createdHlc;
  final Hlc? deletedHlc;
  final Map<String, Hlc> fieldHlcs;
}

/// The sync base — what each record looked like the last time both sides
/// agreed on it. Implement this over whatever your app already stores in.
///
/// ## The single-writer rule
///
/// The mirror's single writer is the sync layer, and that is load-bearing.
/// Local edits write the live tables; the cloud writes its own copy; only a
/// completed sync round advances the mirror. Because each of the three has
/// exactly one writer, a difference between any two of them is attributable —
/// which is what makes "both sides changed" distinguishable from "one side is
/// merely behind". If anything else wrote here, that attribution would be lost
/// and the merge would degrade to last-write-wins.
///
/// ## Implementing it
///
/// A row keyed by `(recordType, id)` is enough. The three HLC fields and the
/// stamp map are all that conflict detection reads back, and `FieldHlcs` will
/// encode the map to a single string column for you.
///
/// A corrupt or unreadable entry should be returned as
/// [SyncSideState.untracked] rather than surfaced as an error: "no common
/// ancestor" merges additively, which is recoverable, whereas a garbage
/// ancestor could mark a real edit as unchanged and drop it.
abstract class MirrorStore {
  /// The base's view of one record.
  ///
  /// Return [SyncSideState.untracked] when there is no entry. On a first sync
  /// that is every record, which is correct: with no common ancestor there is
  /// nothing to have diverged *from*, so both sides get merged additively
  /// rather than treated as conflicting.
  Future<SyncSideState> baseFor(String recordType, String id);

  /// Records what a record looked like once a sync round agreed on it.
  ///
  /// Called by `SyncEngine` only after the round succeeded. Advancing the base
  /// before the cloud write lands would make the next round believe an unsynced
  /// change had already been agreed, and it would stop being offered for merge.
  Future<void> recordBase({
    required String recordType,
    required String id,
    required Hlc? createdHlc,
    required Hlc? deletedHlc,
    required Map<String, Hlc> fieldHlcs,
    required DateTime syncedAt,
  });

  /// Drops the whole base.
  ///
  /// Call this on sign-out. Two reasons it must happen: the next account's
  /// sync would otherwise diff against the previous account's ancestry, and
  /// the base is itself a record of what the previous account's data looked
  /// like.
  Future<void> clear();
}
