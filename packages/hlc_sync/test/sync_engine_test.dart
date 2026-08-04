import 'dart:typed_data';

import 'package:hlc_sync/hlc_sync.dart';
import 'package:test/test.dart';

/// A stand-in for one record type on one device.
///
/// Holds records in a map so a test can act as a second device without a
/// second database. The engine only ever talks to this interface, so what it
/// exercises here is exactly what it will do against a real DAO.
/// One device under test: its engine and the records it holds.
class _Device {
  _Device({required this.engine, required this.source});

  final SyncEngine engine;
  final _FakeSource source;
}

class _FakeSource implements SyncableSource {
  _FakeSource(this.records);

  final Map<String, SyncRecord> records;

  @override
  String get recordType => 'tag';

  @override
  List<String> get fields => <String>['name', 'color'];

  @override
  Future<List<SyncRecord>> readAll() async => records.values.toList();

  @override
  Future<void> applyRemote(SyncRecord record) async {
    records[record.id] = record;
  }

  @override
  Future<void> applyMerge(SyncRecord record, List<String> fields) async {
    final SyncRecord? existing = records[record.id];
    if (existing == null) {
      records[record.id] = record;
      return;
    }
    final Map<String, Object?> values = Map<String, Object?>.from(
      existing.values,
    );
    final Map<String, Hlc> stamps = Map<String, Hlc>.from(existing.fieldHlcs);
    for (final String field in fields) {
      values[field] = record.values[field];
      final Hlc? stamp = record.fieldHlcs[field];
      if (stamp != null) {
        stamps[field] = stamp;
      }
    }
    records[record.id] = SyncRecord(
      id: existing.id,
      recordType: existing.recordType,
      values: values,
      createdHlc: existing.createdHlc,
      fieldHlcs: stamps,
    );
  }
}

void main() {
  const Hlc t0 = Hlc(physicalMs: 100, logical: 0, nodeId: 'device-a');
  const Hlc tA = Hlc(physicalMs: 200, logical: 0, nodeId: 'device-a');
  const Hlc tB = Hlc(physicalMs: 200, logical: 0, nodeId: 'device-b');
  const Hlc tDelete = Hlc(physicalMs: 300, logical: 0, nodeId: 'device-a');

  late InMemoryCloudStorage cloud;
  late InMemoryMirrorStore mirrorA;
  late InMemoryMirrorStore mirrorB;

  setUp(() {
    cloud = InMemoryCloudStorage();
    mirrorA = InMemoryMirrorStore();
    mirrorB = InMemoryMirrorStore();
  });

  SyncRecord tag({
    String id = 'tag-1',
    String name = 'VIP',
    Object? color,
    Hlc? created = t0,
    Hlc? deleted,
    Map<String, Hlc> stamps = const <String, Hlc>{'name': t0, 'color': t0},
  }) {
    return SyncRecord(
      id: id,
      recordType: 'tag',
      values: <String, Object?>{'name': name, 'color': color},
      createdHlc: created,
      deletedHlc: deleted,
      fieldHlcs: stamps,
    );
  }

  _Device device(MirrorStore mirror, Map<String, SyncRecord> records) {
    final _FakeSource source = _FakeSource(records);
    return _Device(
      engine: SyncEngine(
        storage: cloud,
        mirror: mirror,
        sources: <SyncableSource>[source],
        now: () => DateTime.utc(2026, 1, 1),
      ),
      source: source,
    );
  }

  test('a record created on one device reaches the other', () async {
    final _Device a = device(mirrorA, <String, SyncRecord>{'tag-1': tag()});
    final _Device b = device(mirrorB, <String, SyncRecord>{});

    expect((await a.engine.syncAll()).pushed, 1);
    expect((await b.engine.syncAll()).pulled, 1);

    expect(b.source.records['tag-1']!.values['name'], 'VIP');
  });

  test('a second round does nothing', () async {
    // Convergence has to be stable. A round that keeps finding work would
    // rewrite the cloud forever and burn quota on an unchanged database.
    final _Device a = device(mirrorA, <String, SyncRecord>{'tag-1': tag()});
    await a.engine.syncAll();

    final SyncReport second = await a.engine.syncAll();
    expect(second.pushed, 0);
    expect(second.pulled, 0);
    expect(second.hasConflicts, isFalse);
  });

  test('an edit on one side fast-forwards the other', () async {
    final _Device a = device(mirrorA, <String, SyncRecord>{'tag-1': tag()});
    final _Device b = device(mirrorB, <String, SyncRecord>{});
    await a.engine.syncAll();
    await b.engine.syncAll();

    // A renames it; B has not touched it.
    a.source.records['tag-1'] = tag(
      name: 'Premium',
      stamps: const <String, Hlc>{'name': tA, 'color': t0},
    );
    await a.engine.syncAll();
    await b.engine.syncAll();

    expect(b.source.records['tag-1']!.values['name'], 'Premium');
  });

  test('different fields on each device both survive', () async {
    // The reason per-field clocks exist. Whole-record last-write-wins would
    // silently discard whichever device synced first.
    final _Device a = device(mirrorA, <String, SyncRecord>{'tag-1': tag()});
    final _Device b = device(mirrorB, <String, SyncRecord>{});
    await a.engine.syncAll();
    await b.engine.syncAll();

    a.source.records['tag-1'] = tag(
      name: 'Premium',
      stamps: const <String, Hlc>{'name': tA, 'color': t0},
    );
    b.source.records['tag-1'] = tag(
      color: 255,
      stamps: const <String, Hlc>{'name': t0, 'color': tB},
    );

    await a.engine.syncAll();
    final SyncReport report = await b.engine.syncAll();

    expect(report.merged, 1);
    expect(report.hasConflicts, isFalse);
    expect(b.source.records['tag-1']!.values['name'], 'Premium');
    expect(b.source.records['tag-1']!.values['color'], 255);
  });

  test('the same field on both devices is reported, not resolved', () async {
    final _Device a = device(mirrorA, <String, SyncRecord>{'tag-1': tag()});
    final _Device b = device(mirrorB, <String, SyncRecord>{});
    await a.engine.syncAll();
    await b.engine.syncAll();

    a.source.records['tag-1'] = tag(
      name: 'FromA',
      stamps: const <String, Hlc>{'name': tA, 'color': t0},
    );
    b.source.records['tag-1'] = tag(
      name: 'FromB',
      stamps: const <String, Hlc>{'name': tB, 'color': t0},
    );

    await a.engine.syncAll();
    final SyncReport report = await b.engine.syncAll();

    expect(report.conflicts, hasLength(1));
    expect(report.conflicts.single.fields, <String>['name']);
    // Nothing was applied: B keeps its own value until someone chooses.
    expect(b.source.records['tag-1']!.values['name'], 'FromB');
  });

  test('an unresolved conflict does not settle itself next round', () async {
    // The base must not advance on a conflict. If it did, the next round
    // would read the divergence as already agreed and silently pick a side.
    final _Device a = device(mirrorA, <String, SyncRecord>{'tag-1': tag()});
    final _Device b = device(mirrorB, <String, SyncRecord>{});
    await a.engine.syncAll();
    await b.engine.syncAll();

    a.source.records['tag-1'] = tag(
      name: 'FromA',
      stamps: const <String, Hlc>{'name': tA, 'color': t0},
    );
    b.source.records['tag-1'] = tag(
      name: 'FromB',
      stamps: const <String, Hlc>{'name': tB, 'color': t0},
    );
    await a.engine.syncAll();

    expect((await b.engine.syncAll()).conflicts, hasLength(1));
    expect((await b.engine.syncAll()).conflicts, hasLength(1));
    expect(b.source.records['tag-1']!.values['name'], 'FromB');
  });

  test('a delete propagates instead of being resurrected', () async {
    // The failure this whole design exists to prevent: B has the record, A
    // deletes it, and the next round has to remove it from B rather than
    // pushing B's copy back up as though it were new.
    final _Device a = device(mirrorA, <String, SyncRecord>{'tag-1': tag()});
    final _Device b = device(mirrorB, <String, SyncRecord>{});
    await a.engine.syncAll();
    await b.engine.syncAll();
    expect(b.source.records['tag-1']!.isDeleted, isFalse);

    a.source.records['tag-1'] = tag(deleted: tDelete);
    await a.engine.syncAll();
    await b.engine.syncAll();

    expect(b.source.records['tag-1']!.isDeleted, isTrue);
  });

  test('a deleted record stays deleted across further rounds', () async {
    final _Device a = device(mirrorA, <String, SyncRecord>{
      'tag-1': tag(deleted: tDelete),
    });
    final _Device b = device(mirrorB, <String, SyncRecord>{});

    await a.engine.syncAll();
    await b.engine.syncAll();
    await b.engine.syncAll();
    await a.engine.syncAll();

    expect(b.source.records['tag-1']?.isDeleted ?? true, isTrue);
    expect(a.source.records['tag-1']!.isDeleted, isTrue);
  });

  test('offline leaves everything untouched', () async {
    final _Device a = device(mirrorA, <String, SyncRecord>{'tag-1': tag()});
    cloud.offline = true;

    await expectLater(a.engine.syncAll(), throwsA(anything));

    // Nothing was written locally, and no base was advanced — so coming back
    // online resumes from a clean state rather than a half-applied one.
    cloud.offline = false;
    expect((await a.engine.syncAll()).pushed, 1);
  });

  test('a corrupt cloud file does not abort the round', () async {
    // One unreadable record must not stop the other several hundred. A round
    // that dies on the first bad byte would never recover on its own.
    final _Device a = device(mirrorA, <String, SyncRecord>{'tag-1': tag()});
    await a.engine.syncAll();
    await cloud.write(
      '/records/tag/garbage.json',
      Uint8List.fromList('this is not json'.codeUnits),
    );

    final _Device b = device(mirrorB, <String, SyncRecord>{});
    expect((await b.engine.syncAll()).pulled, 1);
  });
}
