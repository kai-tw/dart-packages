import 'field_divergence.dart';
import 'mirror_store.dart';
import 'sync_entity_presence.dart';

/// What a sync round should do with one record.
enum RecordOutcome {
  /// Nothing to do — both sides already agree.
  inSync,

  /// Local is ahead. Push it to the cloud.
  takeLocal,

  /// Cloud is ahead. Apply it locally.
  takeCloud,

  /// Each side moved different fields. Take each side's changes for the fields
  /// it touched — no one has to choose, and nobody's edit is lost.
  merge,

  /// Both sides changed since the base. A human has to choose.
  conflict,
}

/// The result of comparing one record across local, cloud and base.
class RecordResolution {
  const RecordResolution({
    required this.outcome,
    this.conflictingFields = const <String>[],
    this.localFields = const <String>[],
    this.cloudFields = const <String>[],
  });

  final RecordOutcome outcome;

  /// Fields to take from local, when [outcome] is [RecordOutcome.merge].
  final List<String> localFields;

  /// Fields to take from the cloud, when [outcome] is [RecordOutcome.merge].
  final List<String> cloudFields;

  /// Which fields diverged, when [outcome] is [RecordOutcome.conflict] and the
  /// disagreement is field-level rather than about existence.
  ///
  /// Empty on an existence conflict — there is no field to choose between when
  /// the question is whether the record should exist at all.
  final List<String> conflictingFields;
}

/// Decides what to do with one record.
///
/// ## Existence is decided before content
///
/// If one side deleted a record and the other edited it, there is no useful
/// field-level answer — the question is whether the record should exist, and
/// merging field values into something the user deleted would be worse than
/// asking. So presence is resolved first, and only records live on both sides
/// go on to a field comparison.
///
/// ## Why "absent" is three states, not one
///
/// A side that never had the record and a side that deleted it must be handled
/// differently. Treating both as "absent" is what makes a delete on one device
/// look like a missing record on the other, and resurrects it on the next
/// round. That is why [SyncEntityPresence] has [SyncEntityPresence.untracked]
/// separately from [SyncEntityPresence.deleted].
RecordResolution resolveRecord({
  required SyncSideState local,
  required SyncSideState cloud,
  required SyncSideState base,
  required List<String> fields,
}) {
  final SyncEntityPresence l = local.presence;
  final SyncEntityPresence c = cloud.presence;

  // Neither side has it. Nothing to reconcile.
  if (l == SyncEntityPresence.untracked && c == SyncEntityPresence.untracked) {
    return const RecordResolution(outcome: RecordOutcome.inSync);
  }

  // One side has never seen it.
  //
  // Whether that is "new here" or "deleted there and the tombstone was
  // dropped" cannot be told apart, so this takes the additive reading: a
  // record the other side still holds gets propagated. The alternative —
  // assuming a purged tombstone — would delete real data on the strength of
  // an absence, which is not a trade worth making.
  if (l == SyncEntityPresence.untracked) {
    return RecordResolution(
      outcome: c == SyncEntityPresence.deleted
          ? RecordOutcome.inSync
          : RecordOutcome.takeCloud,
    );
  }
  if (c == SyncEntityPresence.untracked) {
    return RecordResolution(
      outcome: l == SyncEntityPresence.deleted
          ? RecordOutcome.inSync
          : RecordOutcome.takeLocal,
    );
  }

  // Both sides deleted it. They agree.
  if (l == SyncEntityPresence.deleted && c == SyncEntityPresence.deleted) {
    return const RecordResolution(outcome: RecordOutcome.inSync);
  }

  // One deleted, one still has it — the interesting case.
  if (l == SyncEntityPresence.deleted || c == SyncEntityPresence.deleted) {
    final bool localDeleted = l == SyncEntityPresence.deleted;
    final SyncSideState liveSide = localDeleted ? cloud : local;

    // Was the live side's copy created *after* the base? If so it is not the
    // record the other side deleted — it was deleted and then made again, and
    // silently re-applying the tombstone would throw away the new one.
    //
    // Without createdHlc these two are indistinguishable, which is exactly
    // why the base records it.
    final bool revived =
        base.createdHlc != null &&
        liveSide.createdHlc != null &&
        liveSide.createdHlc!.compareTo(base.createdHlc!) > 0;
    if (revived) {
      return const RecordResolution(outcome: RecordOutcome.conflict);
    }

    // Did the live side edit it after the base? Deleting something the other
    // person was still working on is worth asking about.
    final bool editedSinceBase = fields.any(
      (String f) =>
          classifyField(
            local: liveSide.fieldHlcs[f],
            cloud: base.fieldHlcs[f],
            base: base.fieldHlcs[f],
          ) !=
          FieldDivergence.unchanged,
    );
    if (editedSinceBase) {
      return const RecordResolution(outcome: RecordOutcome.conflict);
    }

    // Untouched since the base — the delete simply hasn't reached the other
    // side yet. Fast-forward it.
    return RecordResolution(
      outcome: localDeleted ? RecordOutcome.takeLocal : RecordOutcome.takeCloud,
    );
  }

  // Live on both sides. Compare field by field.
  final List<String> conflicting = <String>[];
  final List<String> localFields = <String>[];
  final List<String> cloudFields = <String>[];

  for (final String field in fields) {
    switch (classifyField(
      local: local.fieldHlcs[field],
      cloud: cloud.fieldHlcs[field],
      base: base.fieldHlcs[field],
    )) {
      case FieldDivergence.unchanged:
        break;
      case FieldDivergence.localOnly:
        localFields.add(field);
      case FieldDivergence.cloudOnly:
        cloudFields.add(field);
      case FieldDivergence.concurrent:
        conflicting.add(field);
    }
  }

  // Only the same field moving on both sides is a real conflict. Anything
  // else is answerable without troubling the user.
  if (conflicting.isNotEmpty) {
    return RecordResolution(
      outcome: RecordOutcome.conflict,
      conflictingFields: conflicting,
      localFields: localFields,
      cloudFields: cloudFields,
    );
  }
  if (localFields.isNotEmpty && cloudFields.isNotEmpty) {
    // Each side touched fields the other did not. This is the case per-field
    // clocks exist for: one device edits one field while another device edits
    // a different field of the same record, and both survive. Whole-record
    // last-write-wins would throw one of them away without telling anyone.
    return RecordResolution(
      outcome: RecordOutcome.merge,
      localFields: localFields,
      cloudFields: cloudFields,
    );
  }
  if (localFields.isNotEmpty) {
    return RecordResolution(
      outcome: RecordOutcome.takeLocal,
      localFields: localFields,
    );
  }
  if (cloudFields.isNotEmpty) {
    return RecordResolution(
      outcome: RecordOutcome.takeCloud,
      cloudFields: cloudFields,
    );
  }
  return const RecordResolution(outcome: RecordOutcome.inSync);
}
