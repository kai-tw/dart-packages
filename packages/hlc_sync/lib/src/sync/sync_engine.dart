import 'dart:typed_data';

import '../hlc/hlc.dart';
import '../mutex.dart';
import 'cloud/cloud_storage.dart';
import 'mirror_store.dart';
import 'record_resolution.dart';
import 'sync_record.dart';

/// Told about work the engine stepped over — a record it could not read, or a
/// cloud file that does not match its own location.
///
/// A seam rather than a logger dependency. The engine has no opinion about
/// where these go, and the messages are deliberately shaped so it does not
/// need one: they name types and record types, never field values.
///
/// Be careful what you wire this to. If your sink forwards to a crash
/// reporter, everything passed here leaves the device.
typedef SyncWarning = void Function(String message);

/// What one record type has to provide for the engine to sync it.
///
/// Deliberately small. The engine decides *which* side wins; the source knows
/// how to read and write its own rows. Neither needs the other's knowledge.
abstract class SyncableSource {
  /// A stable identifier for this record type, such as `'customer'`.
  ///
  /// It names the record's directory in cloud storage and partitions the
  /// mirror, so changing it orphans everything already synced under the old
  /// name — treat it as part of the on-disk format, not as a label.
  String get recordType;

  /// Field names that participate in conflict detection.
  List<String> get fields;

  /// Every record, tombstoned ones included.
  ///
  /// Tombstones must be in here. Omitting them is what makes a delete look
  /// like a record the other side has simply not received, so it comes back.
  Future<List<SyncRecord>> readAll();

  /// Applies a record decided elsewhere, overwriting whatever is local.
  Future<void> applyRemote(SyncRecord record);

  /// Applies a per-field merge: [record] holds the winning value for each
  /// named field, and everything else keeps its local value.
  Future<void> applyMerge(SyncRecord record, List<String> fields);
}

/// The outcome of one sync round.
class SyncReport {
  const SyncReport({
    this.pushed = 0,
    this.pulled = 0,
    this.merged = 0,
    this.skipped = 0,
    this.conflicts = const <SyncConflict>[],
  });

  final int pushed;
  final int pulled;
  final int merged;

  /// Records the round could not apply and stepped over.
  ///
  /// Non-zero means the cloud holds something this build cannot read — a value
  /// of the wrong type, or a file that does not match its own location. The
  /// round still completed; those records simply did not move.
  final int skipped;

  /// Records needing a human. Nothing is applied for these — both sides keep
  /// what they had until someone chooses.
  final List<SyncConflict> conflicts;

  bool get hasConflicts => conflicts.isNotEmpty;
}

/// Which side of a conflict the user chose to keep.
enum ConflictChoice { keepLocal, keepCloud }

/// Both sides of a conflicted record, for a human to compare.
///
/// Assembled on demand rather than snapshotted when the conflict was detected.
/// A snapshot would be a second at-rest copy of someone else's personal data
/// with its own lifetime to get wrong, and it would go stale — what the user
/// needs to see is what the other device says *now*, not what it said when the
/// round ran.
class ConflictDetail {
  const ConflictDetail({
    required this.recordType,
    required this.id,
    required this.fields,
    required this.local,
    required this.cloud,
  });

  final String recordType;
  final String id;

  /// The fields in disagreement. Empty when the disagreement is about whether
  /// the record should exist at all.
  final List<String> fields;

  final SyncRecord? local;
  final SyncRecord? cloud;

  /// True when one side deleted the record and the other did not.
  bool get isDeletionConflict =>
      local?.deletedHlc != null || cloud?.deletedHlc != null;
}

/// A record both sides changed.
class SyncConflict {
  const SyncConflict({
    required this.recordType,
    required this.id,
    required this.fields,
  });

  final String recordType;
  final String id;

  /// The specific fields in disagreement. Empty when the disagreement is about
  /// whether the record should exist at all.
  final List<String> fields;
}

/// Runs sync rounds.
///
/// ## Ordering
///
/// A record is written cloud-first, then local, then the mirror. That order is
/// not arbitrary — it is failure-ordered. The cloud write is the one most
/// likely to fail, so it goes first: if it does, local and the mirror are
/// untouched and the next round retries from a clean, consistent state. Doing
/// it the other way round leaves local ahead of a cloud that never received
/// the change, and a mirror claiming they agreed.
///
/// The mirror advances **last, and only on success**. Advancing it earlier
/// would tell the next round that an unsynced change had already been agreed,
/// and it would stop being offered for merge — a silent loss.
class SyncEngine {
  SyncEngine({
    required CloudStorage storage,
    required MirrorStore mirror,
    required List<SyncableSource> sources,
    required DateTime Function() now,
    SyncWarning? onWarning,
  }) : _storage = storage,
       _mirror = mirror,
       _sources = sources,
       _now = now,
       _onWarning = onWarning;

  final CloudStorage _storage;
  final MirrorStore _mirror;
  final List<SyncableSource> _sources;
  final DateTime Function() _now;

  /// Optional. Rounds still report skipped records through
  /// [SyncReport.skipped], so dropping this loses the detail but never the
  /// fact that something was stepped over.
  final SyncWarning? _onWarning;

  void _warn(String message) => _onWarning?.call(message);

  /// Serialises rounds. Two overlapping rounds would each read the base before
  /// the other advanced it, and both would then decide against stale ancestry.
  final Mutex _mutex = Mutex();

  Future<SyncReport> syncAll() async {
    await _mutex.lock();
    try {
      int pushed = 0;
      int pulled = 0;
      int merged = 0;
      int skipped = 0;
      final List<SyncConflict> conflicts = <SyncConflict>[];

      for (final SyncableSource source in _sources) {
        final SyncReport report = await _syncSource(source);
        pushed += report.pushed;
        pulled += report.pulled;
        merged += report.merged;
        skipped += report.skipped;
        conflicts.addAll(report.conflicts);
      }

      return SyncReport(
        pushed: pushed,
        pulled: pulled,
        merged: merged,
        skipped: skipped,
        conflicts: conflicts,
      );
    } finally {
      _mutex.release();
    }
  }

  /// Both sides of a conflicted record, read fresh.
  ///
  /// Returns null when the record type is unknown or the record has since
  /// stopped existing on both sides.
  Future<ConflictDetail?> readConflict({
    required String recordType,
    required String id,
  }) async {
    await _mutex.lock();
    try {
      final SyncableSource? source = _sourceFor(recordType);
      if (source == null) {
        return null;
      }

      final SyncRecord? local = await _localRecord(source, id);
      final SyncRecord? cloud = await _readCloudRecord(recordType, id);
      if (local == null && cloud == null) {
        return null;
      }

      // Re-run detection rather than trusting the field list the round
      // reported. The cloud can have moved on while the user was deciding, and
      // showing them a disagreement that no longer exists is worse than
      // showing none.
      final RecordResolution resolution = resolveRecord(
        local: local?.sideState ?? const SyncSideState.untracked(),
        cloud: cloud?.sideState ?? const SyncSideState.untracked(),
        base: await _mirror.baseFor(recordType, id),
        fields: source.fields,
      );

      return ConflictDetail(
        recordType: recordType,
        id: id,
        fields: resolution.conflictingFields,
        local: local,
        cloud: cloud,
      );
    } finally {
      _mutex.release();
    }
  }

  /// Applies the user's choice to one record.
  ///
  /// This is deliberately the same work the engine would do for
  /// [RecordOutcome.takeLocal] or [RecordOutcome.takeCloud]: write the winning
  /// side to the loser and advance the base past both, so the next round sees
  /// agreement rather than the same conflict again.
  ///
  /// Both sides are re-read here rather than passed in from the screen. The
  /// cloud may have changed while the user was reading, and "the other device
  /// is right" means the other device as it is now — applying a stale copy
  /// would resurrect data the user never saw.
  Future<void> resolveConflict({
    required String recordType,
    required String id,
    required ConflictChoice choice,
  }) async {
    await _mutex.lock();
    try {
      final SyncableSource? source = _sourceFor(recordType);
      if (source == null) {
        return;
      }

      switch (choice) {
        case ConflictChoice.keepLocal:
          final SyncRecord? local = await _localRecord(source, id);
          if (local == null) {
            return;
          }
          await _push('/records/$recordType', local);
          await _advanceBase(recordType, local);

        case ConflictChoice.keepCloud:
          final SyncRecord? cloud = await _readCloudRecord(recordType, id);
          if (cloud == null) {
            return;
          }
          await source.applyRemote(cloud);
          await _advanceBase(recordType, cloud);
      }
    } finally {
      _mutex.release();
    }
  }

  SyncableSource? _sourceFor(String recordType) {
    for (final SyncableSource source in _sources) {
      if (source.recordType == recordType) {
        return source;
      }
    }
    return null;
  }

  /// One local record by id, tombstones included.
  ///
  /// A filter over [SyncableSource.readAll] rather than a keyed query on the
  /// interface, because three of the four sources assemble a record from
  /// several tables — a keyed variant would duplicate that assembly for a path
  /// only reached when a human is resolving a conflict. The cost of reading
  /// everything is real but it is the same cost a round already pays, and it
  /// is tracked as its own problem (issue #18).
  Future<SyncRecord?> _localRecord(SyncableSource source, String id) async {
    for (final SyncRecord record in await source.readAll()) {
      if (record.id == id) {
        return record;
      }
    }
    return null;
  }

  Future<SyncRecord?> _readCloudRecord(String recordType, String id) async {
    final Uint8List? bytes = await _storage.read(
      '/records/$recordType/$id.json',
    );
    if (bytes == null) {
      return null;
    }
    final SyncRecord? record = SyncRecord.decode(bytes);
    // Same binding as _readCloud: the conflict screen reads by path, so a file
    // claiming to be a different record or a different type is not the one the
    // user is being asked about.
    if (record == null || record.recordType != recordType || record.id != id) {
      return null;
    }
    return record;
  }

  Future<SyncReport> _syncSource(SyncableSource source) async {
    final String dir = '/records/${source.recordType}';

    final Map<String, SyncRecord> local = <String, SyncRecord>{
      for (final SyncRecord r in await source.readAll()) r.id: r,
    };
    final Map<String, SyncRecord> remote = await _readCloud(source, dir);

    int pushed = 0;
    int pulled = 0;
    int merged = 0;
    int skipped = 0;
    final List<SyncConflict> conflicts = <SyncConflict>[];

    // The union: a record present on only one side still has to be considered,
    // which is how new records travel in both directions.
    for (final String id in <String>{...local.keys, ...remote.keys}) {
      final SyncRecord? localRecord = local[id];
      final SyncRecord? remoteRecord = remote[id];
      final SyncSideState base = await _mirror.baseFor(source.recordType, id);

      final RecordResolution resolution = resolveRecord(
        local: localRecord?.sideState ?? const SyncSideState.untracked(),
        cloud: remoteRecord?.sideState ?? const SyncSideState.untracked(),
        base: base,
        fields: source.fields,
      );

      // Applying is where cloud values are finally cast to their real types,
      // so a field holding the wrong JSON type throws here rather than at
      // decode. Without this the throw would unwind the whole round — every
      // later record and every later record type — and because the base is
      // never advanced, the next round would replay the same file and fail
      // identically. Sync would be dead until someone deleted a file they
      // cannot see, `drive.appdata` being invisible in the Drive UI.
      try {
        switch (resolution.outcome) {
          case RecordOutcome.inSync:
            // Still advance the base: the two sides agree now, and recording
            // that is what lets a later one-sided edit fast-forward instead of
            // looking like a conflict against stale ancestry.
            final SyncRecord? agreed = localRecord ?? remoteRecord;
            if (agreed != null) {
              await _advanceBase(source.recordType, agreed);
            }

          case RecordOutcome.takeLocal:
            await _push(dir, localRecord!);
            await _advanceBase(source.recordType, localRecord);
            pushed++;

          case RecordOutcome.takeCloud:
            await source.applyRemote(remoteRecord!);
            await _advanceBase(source.recordType, remoteRecord);
            pulled++;

          case RecordOutcome.merge:
            // Each side keeps the fields it moved. The merged record is then
            // pushed so the cloud carries the union too, otherwise the next
            // round would see the same divergence again.
            await source.applyMerge(remoteRecord!, resolution.cloudFields);
            final SyncRecord mergedRecord = _mergeRecords(
              local: localRecord!,
              cloud: remoteRecord,
              cloudFields: resolution.cloudFields,
            );
            await _push(dir, mergedRecord);
            await _advanceBase(source.recordType, mergedRecord);
            merged++;

          case RecordOutcome.conflict:
            // Nothing is written and the base is not advanced. Both sides keep
            // what they had, and the record stays divergent until someone
            // chooses — which is the point: an unresolved conflict must not
            // quietly resolve itself on the next round.
            conflicts.add(
              SyncConflict(
                recordType: source.recordType,
                id: id,
                fields: resolution.conflictingFields,
              ),
            );
        }
      } on CloudOfflineException {
        // Not this record's fault and not survivable by moving to the next
        // one. Letting it past is what keeps a round whose uploads all failed
        // from reporting success — the catch below would otherwise turn a dead
        // connection into "synced, a few records skipped".
        rethrow;
      } on CloudStorageException {
        rethrow;
      } on Object catch (error) {
        // The type only: the exception can carry the record's own field
        // values — a database driver may put bound statement parameters in
        // `toString` — and the sink behind [SyncWarning] may well forward off
        // the device.
        _warn(
          'Skipped a ${source.recordType} record: ${error.runtimeType}',
        );
        skipped++;
      }
    }

    return SyncReport(
      pushed: pushed,
      pulled: pulled,
      merged: merged,
      skipped: skipped,
      conflicts: conflicts,
    );
  }

  Future<Map<String, SyncRecord>> _readCloud(
    SyncableSource source,
    String dir,
  ) async {
    final Map<String, SyncRecord> records = <String, SyncRecord>{};
    for (final CloudFile file in await _storage.list(dir)) {
      final Uint8List? bytes = await _storage.read(file.path);
      if (bytes == null) {
        continue;
      }
      final SyncRecord? record = SyncRecord.decode(bytes);
      // Undecodable files are skipped rather than fatal. One corrupt record
      // must not stop the other several hundred from syncing.
      if (record == null) {
        continue;
      }

      // A file has to be what its location says it is. Nothing in the cloud
      // enforces that: the record's own `recordType` and `id` are just fields
      // in a document anyone with write access to the appDataFolder can author,
      // and the path is metadata on the same document. Trusting either on its
      // own lets a task be applied as a customer, or a file claiming another
      // record's id shadow the real one — an entry the app can then never
      // overwrite, because its writes go to the genuine id's path.
      //
      // security.md S-CRM4.1: data from Drive is untrusted, and a record that
      // fails this is dropped rather than allowed to abort the round.
      if (record.recordType != source.recordType ||
          file.path != '$dir/${record.id}.json') {
        _warn(
          'Discarding a ${source.recordType} file that does not match its '
          'location',
        );
        continue;
      }
      records[record.id] = record;
    }
    return records;
  }

  Future<void> _push(String dir, SyncRecord record) async {
    await _storage.write('$dir/${record.id}.json', record.encode());
  }

  Future<void> _advanceBase(String recordType, SyncRecord record) async {
    await _mirror.recordBase(
      recordType: recordType,
      id: record.id,
      createdHlc: record.createdHlc,
      deletedHlc: record.deletedHlc,
      fieldHlcs: record.fieldHlcs,
      syncedAt: _now(),
    );
  }

  SyncRecord _mergeRecords({
    required SyncRecord local,
    required SyncRecord cloud,
    required List<String> cloudFields,
  }) {
    final Map<String, Object?> values = Map<String, Object?>.from(local.values);
    final Map<String, Hlc> stamps = Map<String, Hlc>.from(local.fieldHlcs);
    for (final String field in cloudFields) {
      values[field] = cloud.values[field];
      final Hlc? stamp = cloud.fieldHlcs[field];
      if (stamp != null) {
        stamps[field] = stamp;
      }
    }

    return SyncRecord(
      id: local.id,
      recordType: local.recordType,
      values: values,
      // The earlier creation stamp wins: whichever device made it first is
      // when the record actually came into existence.
      createdHlc: _earlier(local.createdHlc, cloud.createdHlc),
      fieldHlcs: stamps,
    );
  }

  static Hlc? _earlier(Hlc? a, Hlc? b) {
    if (a == null) {
      return b;
    }
    if (b == null) {
      return a;
    }
    return a.compareTo(b) <= 0 ? a : b;
  }
}
