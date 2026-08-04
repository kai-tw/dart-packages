import 'package:hlc_sync/hlc_sync.dart';
import 'package:test/test.dart';

void main() {
  const Hlc t0 = Hlc(physicalMs: 100, logical: 0, nodeId: 'node-a');
  const Hlc t1Local = Hlc(physicalMs: 200, logical: 0, nodeId: 'node-a');
  const Hlc t1Cloud = Hlc(physicalMs: 200, logical: 0, nodeId: 'node-b');
  const Hlc t2 = Hlc(physicalMs: 300, logical: 0, nodeId: 'node-a');

  const List<String> fields = <String>['name', 'phone'];

  SyncSideState live({
    Hlc? created = t0,
    Map<String, Hlc> stamps = const <String, Hlc>{'name': t0, 'phone': t0},
  }) {
    return SyncSideState(
      presence: SyncEntityPresence.present,
      createdHlc: created,
      fieldHlcs: stamps,
    );
  }

  SyncSideState tombstoned({Hlc? created = t0}) {
    return SyncSideState(
      presence: SyncEntityPresence.deleted,
      createdHlc: created,
      deletedHlc: t2,
      fieldHlcs: const <String, Hlc>{'name': t0, 'phone': t0},
    );
  }

  RecordOutcome outcomeOf({
    required SyncSideState local,
    required SyncSideState cloud,
    required SyncSideState base,
  }) {
    return resolveRecord(
      local: local,
      cloud: cloud,
      base: base,
      fields: fields,
    ).outcome;
  }

  group('presence', () {
    test('neither side has it', () {
      expect(
        outcomeOf(
          local: const SyncSideState.untracked(),
          cloud: const SyncSideState.untracked(),
          base: const SyncSideState.untracked(),
        ),
        RecordOutcome.inSync,
      );
    });

    test('new on the cloud propagates down', () {
      expect(
        outcomeOf(
          local: const SyncSideState.untracked(),
          cloud: live(),
          base: const SyncSideState.untracked(),
        ),
        RecordOutcome.takeCloud,
      );
    });

    test('new locally propagates up', () {
      expect(
        outcomeOf(
          local: live(),
          cloud: const SyncSideState.untracked(),
          base: const SyncSideState.untracked(),
        ),
        RecordOutcome.takeLocal,
      );
    });

    test('an unseen tombstone needs no action', () {
      // Nothing to delete on a side that never had the record.
      expect(
        outcomeOf(
          local: const SyncSideState.untracked(),
          cloud: tombstoned(),
          base: const SyncSideState.untracked(),
        ),
        RecordOutcome.inSync,
      );
    });

    test('both deleted', () {
      expect(
        outcomeOf(
          local: tombstoned(),
          cloud: tombstoned(),
          base: live(),
        ),
        RecordOutcome.inSync,
      );
    });
  });

  group('delete versus edit', () {
    test('an untouched record accepts the other side delete', () {
      // Nobody edited it since the base, so the delete is simply news.
      expect(
        outcomeOf(local: tombstoned(), cloud: live(), base: live()),
        RecordOutcome.takeLocal,
      );
      expect(
        outcomeOf(local: live(), cloud: tombstoned(), base: live()),
        RecordOutcome.takeCloud,
      );
    });

    test('deleting something the other side edited asks first', () {
      // Applying the tombstone would throw away an edit nobody saw.
      expect(
        outcomeOf(
          local: tombstoned(),
          cloud: live(
            stamps: const <String, Hlc>{'name': t1Cloud, 'phone': t0},
          ),
          base: live(),
        ),
        RecordOutcome.conflict,
      );
    });

    test('a re-created record is not the one that was deleted', () {
      // Deleted on one device, made again on the other. Re-applying the
      // tombstone would silently destroy the new record. Distinguishing this
      // from "never deleted" is the entire reason createdHlc is stored.
      expect(
        outcomeOf(
          local: tombstoned(),
          cloud: live(created: t2),
          base: live(created: t0),
        ),
        RecordOutcome.conflict,
      );
    });
  });

  group('field-level', () {
    test('nothing moved', () {
      expect(
        outcomeOf(local: live(), cloud: live(), base: live()),
        RecordOutcome.inSync,
      );
    });

    test('one side ahead fast-forwards without asking', () {
      expect(
        outcomeOf(
          local: live(
            stamps: const <String, Hlc>{'name': t1Local, 'phone': t0},
          ),
          cloud: live(),
          base: live(),
        ),
        RecordOutcome.takeLocal,
      );
    });

    test('different fields on each side merge, they do not conflict', () {
      // The case per-field clocks exist for: one device renames the customer
      // while the other adds a phone number. Whole-record last-write-wins
      // would discard one of them without telling anyone.
      final RecordResolution result = resolveRecord(
        local: live(stamps: const <String, Hlc>{'name': t1Local, 'phone': t0}),
        cloud: live(stamps: const <String, Hlc>{'name': t0, 'phone': t1Cloud}),
        base: live(),
        fields: fields,
      );

      expect(result.outcome, RecordOutcome.merge);
      expect(result.localFields, <String>['name']);
      expect(result.cloudFields, <String>['phone']);
    });

    test('the same field on both sides is a real conflict', () {
      final RecordResolution result = resolveRecord(
        local: live(stamps: const <String, Hlc>{'name': t1Local, 'phone': t0}),
        cloud: live(stamps: const <String, Hlc>{'name': t1Cloud, 'phone': t0}),
        base: live(),
        fields: fields,
      );

      expect(result.outcome, RecordOutcome.conflict);
      expect(result.conflictingFields, <String>['name']);
    });

    test('one write observed twice is not a conflict', () {
      // Both sides carry the same clock: one already received the other's
      // write. Asking the user to choose between a value and itself would be
      // the most obviously wrong thing this could do.
      expect(
        outcomeOf(
          local: live(
            stamps: const <String, Hlc>{'name': t1Local, 'phone': t0},
          ),
          cloud: live(
            stamps: const <String, Hlc>{'name': t1Local, 'phone': t0},
          ),
          base: live(),
        ),
        RecordOutcome.inSync,
      );
    });

    test('a first sync with data on both sides conflicts, not overwrites', () {
      // No base at all. Neither side can be fast-forwarded because there is no
      // ancestor to have moved away from, so picking one silently would drop
      // the other device's entire history for this record.
      expect(
        outcomeOf(
          local: live(stamps: const <String, Hlc>{'name': t1Local}),
          cloud: live(stamps: const <String, Hlc>{'name': t1Cloud}),
          base: const SyncSideState.untracked(),
        ),
        RecordOutcome.conflict,
      );
    });
  });
}
