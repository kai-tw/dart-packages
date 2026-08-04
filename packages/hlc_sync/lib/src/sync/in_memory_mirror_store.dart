import '../hlc/hlc.dart';
import 'mirror_store.dart';
import 'sync_entity_presence.dart';

/// A [MirrorStore] held in a map, for tests and for a first run against a
/// storage backend you have not written yet.
///
/// Matches the real contract where it matters: a record with no entry reads
/// back as [SyncSideState.untracked], and recording a base replaces whatever
/// was there rather than merging into it.
///
/// It forgets everything when the process ends, so a sync round that used one
/// of these will re-derive every record from scratch next time. That is safe —
/// no common ancestor means additive merge — but it is not what you want in
/// production, where the whole value of the base is that it survives.
class InMemoryMirrorStore implements MirrorStore {
  final Map<String, SyncSideState> _entries = <String, SyncSideState>{};

  /// Number of records currently in the base. Test convenience.
  int get length => _entries.length;

  @override
  Future<SyncSideState> baseFor(String recordType, String id) async =>
      _entries[_key(recordType, id)] ?? const SyncSideState.untracked();

  @override
  Future<void> recordBase({
    required String recordType,
    required String id,
    required Hlc? createdHlc,
    required Hlc? deletedHlc,
    required Map<String, Hlc> fieldHlcs,
    required DateTime syncedAt,
  }) async {
    _entries[_key(recordType, id)] = SyncSideState(
      presence: deletedHlc == null
          ? SyncEntityPresence.present
          : SyncEntityPresence.deleted,
      createdHlc: createdHlc,
      deletedHlc: deletedHlc,
      // Copied, not aliased: the caller owns its map and may go on mutating it.
      fieldHlcs: Map<String, Hlc>.from(fieldHlcs),
    );
  }

  @override
  Future<void> clear() async => _entries.clear();

  static String _key(String recordType, String id) => '$recordType/$id';
}
