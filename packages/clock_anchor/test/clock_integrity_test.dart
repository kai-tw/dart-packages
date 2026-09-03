import 'package:clock_anchor/clock_anchor.dart';
import 'package:test/test.dart';

import 'support/recording_watermark_store.dart';

/// `ClockIntegrity` — rollback detection, and the recovery path that keeps it
/// from being a trap.
///
/// The design constraint these tests exist to hold: a watermark left in the
/// future by one clock change must be recoverable. An anti-rollback floor
/// that can only ever rise would leave a device fail-closed for as long as
/// the bogus value stands, which is a worse outcome than the attack it
/// prevents — and it is why the watermark is kept out of the path that
/// produces timestamps entirely.
void main() {
  final DateTime trueNow = DateTime.utc(2026, 9, 3, 12);

  TimeAnchor anchorAt(
    DateTime truth, {
    TimeSourceTrust trust = TimeSourceTrust.transportAuthenticated,
  }) => TimeAnchor(
    referenceUtc: truth,
    ticksAtReference: Duration.zero,
    deviceWallAtReference: truth,
    uncertainty: Duration.zero,
    trust: trust,
    sourceId: 'test',
  );

  group('detection', () {
    test('the first observation establishes the watermark', () async {
      final RecordingWatermarkStore store = RecordingWatermarkStore();
      final ClockIntegrity integrity = ClockIntegrity(store: store);
      await integrity.load();

      final ClockIntegrityReport report = await integrity.observe(trueNow);

      expect(report.verdict, ClockIntegrityVerdict.intact);
      expect(integrity.watermark, trueNow);
      expect(store.writes, <DateTime>[trueNow]);
    });

    test('a clock below the watermark is a rollback', () async {
      final ClockIntegrity integrity = ClockIntegrity(
        store: RecordingWatermarkStore(),
      );
      await integrity.load();
      await integrity.observe(trueNow);

      final ClockIntegrityReport report = await integrity.observe(
        trueNow.subtract(const Duration(hours: 3)),
      );

      expect(report.verdict, ClockIntegrityVerdict.rolledBack);
      expect(report.delta, const Duration(hours: 3));
      expect(integrity.isRolledBack, isTrue);
    });

    test(
      'a watermark left by a previous run still catches the rollback',
      () async {
        // The case worth having persistence for at all: the clock was moved
        // while the app was not running, so nothing in this process saw it.
        final ClockIntegrity integrity = ClockIntegrity(
          store: RecordingWatermarkStore(trueNow),
        );
        await integrity.load();

        final ClockIntegrityReport report = await integrity.observe(
          trueNow.subtract(const Duration(days: 2)),
        );

        expect(report.verdict, ClockIntegrityVerdict.rolledBack);
      },
    );

    test(
      'the flag is sticky: looking normal again does not clear it',
      () async {
        final ClockIntegrity integrity = ClockIntegrity(
          store: RecordingWatermarkStore(),
        );
        await integrity.load();
        await integrity.observe(trueNow);
        await integrity.observe(trueNow.subtract(const Duration(hours: 3)));

        await integrity.observe(trueNow.add(const Duration(minutes: 1)));

        // Clearing on a normal-looking reading would let anyone clear it by
        // waiting, which makes the flag worth nothing.
        expect(integrity.isRolledBack, isTrue);
      },
    );

    test('a forward jump beyond elapsed monotonic time is reported', () async {
      final ClockIntegrity integrity = ClockIntegrity(
        store: RecordingWatermarkStore(),
      );
      await integrity.load();
      await integrity.observe(trueNow);

      final ClockIntegrityReport report = await integrity.observe(
        trueNow.add(const Duration(hours: 4)),
        monotonicAdvance: const Duration(minutes: 1),
      );

      expect(report.verdict, ClockIntegrityVerdict.advanced);
      expect(report.delta, const Duration(hours: 3, minutes: 59));
    });

    test('time simply passing is not a jump', () async {
      final ClockIntegrity integrity = ClockIntegrity(
        store: RecordingWatermarkStore(),
      );
      await integrity.load();
      await integrity.observe(trueNow);

      final ClockIntegrityReport report = await integrity.observe(
        trueNow.add(const Duration(minutes: 10)),
        monotonicAdvance: const Duration(minutes: 10),
      );

      expect(report.verdict, ClockIntegrityVerdict.intact);
    });

    test('a rising watermark does not write on every observation', () async {
      final RecordingWatermarkStore store = RecordingWatermarkStore();
      final ClockIntegrity integrity = ClockIntegrity(
        store: store,
        persistGranularity: const Duration(minutes: 5),
      );
      await integrity.load();

      await integrity.observe(trueNow);
      for (int minute = 1; minute <= 4; minute += 1) {
        await integrity.observe(
          trueNow.add(Duration(minutes: minute)),
          monotonicAdvance: const Duration(minutes: 1),
        );
      }
      expect(store.writes, hasLength(1));

      await integrity.observe(
        trueNow.add(const Duration(minutes: 6)),
        monotonicAdvance: const Duration(minutes: 2),
      );
      expect(store.writes, hasLength(2));
      expect(integrity.watermark, trueNow.add(const Duration(minutes: 6)));
    });
  });

  group('recovery', () {
    test('an unauthenticated anchor may not lower the watermark', () async {
      final RecordingWatermarkStore store = RecordingWatermarkStore();
      final ClockIntegrity integrity = ClockIntegrity(store: store);
      await integrity.load();
      await integrity.observe(trueNow.add(const Duration(days: 3)));
      await integrity.observe(trueNow);

      final bool lowered = await integrity.reconcile(
        anchorAt(trueNow, trust: TimeSourceTrust.unauthenticated),
        Duration.zero,
        trueNow,
      );

      // Whoever set the clock also controls the network, so an SNTP reply is
      // not evidence about the floor that is meant to survive them.
      expect(lowered, isFalse);
      expect(integrity.watermark, trueNow.add(const Duration(days: 3)));
      expect(integrity.isRolledBack, isTrue);
    });

    test('a trusted anchor pulls a future watermark back down', () async {
      final RecordingWatermarkStore store = RecordingWatermarkStore();
      final ClockIntegrity integrity = ClockIntegrity(store: store);
      await integrity.load();

      // The founder's scenario end to end: wind forward three days, wind back
      // to the truth, and the device must not be left fail-closed for three
      // days waiting for real time to catch up.
      await integrity.observe(trueNow.add(const Duration(days: 3)));
      await integrity.observe(trueNow);
      expect(integrity.isRolledBack, isTrue);

      final bool lowered = await integrity.reconcile(
        anchorAt(trueNow),
        Duration.zero,
        trueNow,
      );

      expect(lowered, isTrue);
      expect(integrity.watermark, trueNow);
      expect(integrity.isRolledBack, isFalse);
      expect(store.writes.last, trueNow);
    });

    test(
      'a still-wrong device clock is not vindicated by the correction',
      () async {
        final ClockIntegrity integrity = ClockIntegrity(
          store: RecordingWatermarkStore(),
        );
        await integrity.load();
        await integrity.observe(trueNow.add(const Duration(days: 3)));
        await integrity.observe(trueNow.subtract(const Duration(days: 10)));

        final bool lowered = await integrity.reconcile(
          anchorAt(trueNow),
          Duration.zero,
          trueNow.subtract(const Duration(days: 10)),
        );

        // The watermark is fixed because it was demonstrably in the future; the
        // flag stays because the device clock is still ten days out. The two
        // are separate claims and are decided separately.
        expect(lowered, isTrue);
        expect(integrity.watermark, trueNow);
        expect(integrity.isRolledBack, isTrue);
      },
    );

    test('a watermark that is not in the future is left where it is', () async {
      final RecordingWatermarkStore store = RecordingWatermarkStore();
      final ClockIntegrity integrity = ClockIntegrity(store: store);
      await integrity.load();
      await integrity.observe(trueNow.subtract(const Duration(hours: 1)));
      final int writesBefore = store.writes.length;

      final bool lowered = await integrity.reconcile(
        anchorAt(trueNow),
        Duration.zero,
        trueNow,
      );

      expect(lowered, isFalse);
      expect(integrity.watermark, trueNow.subtract(const Duration(hours: 1)));
      expect(store.writes, hasLength(writesBefore));
    });
  });

  group('thresholds', () {
    test('a jump exactly at the tolerance is not yet a jump', () async {
      final ClockIntegrity integrity = ClockIntegrity(
        store: RecordingWatermarkStore(),
        tolerance: const Duration(seconds: 5),
      );
      await integrity.load();
      await integrity.observe(trueNow);

      final ClockIntegrityReport atLimit = await integrity.observe(
        trueNow.add(const Duration(minutes: 1, seconds: 5)),
        monotonicAdvance: const Duration(minutes: 1),
      );
      expect(atLimit.verdict, ClockIntegrityVerdict.intact);

      final ClockIntegrityReport past = await integrity.observe(
        trueNow.add(const Duration(minutes: 2, seconds: 11)),
        monotonicAdvance: const Duration(minutes: 1),
      );
      expect(past.verdict, ClockIntegrityVerdict.advanced);
    });

    test('a reading inside the tolerance never lowers the watermark', () async {
      final ClockIntegrity integrity = ClockIntegrity(
        store: RecordingWatermarkStore(),
        tolerance: const Duration(seconds: 5),
      );
      await integrity.load();
      await integrity.observe(trueNow);

      // Below the mark but inside the tolerance: not a rollback, and the
      // watermark is a high-water mark, so it does not follow the reading
      // down either.
      final ClockIntegrityReport report = await integrity.observe(
        trueNow.subtract(const Duration(seconds: 2)),
      );

      expect(report.verdict, ClockIntegrityVerdict.intact);
      expect(integrity.watermark, trueNow);
    });

    test('a persisted watermark counts as already written', () async {
      // Loading must remember that the stored value is on disk. Treating it
      // as unwritten makes the very next observation write again, which
      // defeats the granularity entirely.
      final RecordingWatermarkStore store = RecordingWatermarkStore(trueNow);
      final ClockIntegrity integrity = ClockIntegrity(
        store: store,
        persistGranularity: const Duration(minutes: 5),
      );
      await integrity.load();

      await integrity.observe(
        trueNow.add(const Duration(minutes: 1)),
        monotonicAdvance: const Duration(minutes: 1),
      );

      expect(store.writes, isEmpty);
      expect(integrity.watermark, trueNow.add(const Duration(minutes: 1)));
    });

    test('a rise exactly at the granularity is persisted', () async {
      final RecordingWatermarkStore store = RecordingWatermarkStore(trueNow);
      final ClockIntegrity integrity = ClockIntegrity(
        store: store,
        persistGranularity: const Duration(minutes: 5),
      );
      await integrity.load();

      await integrity.observe(
        trueNow.add(const Duration(minutes: 5)),
        monotonicAdvance: const Duration(minutes: 5),
      );

      expect(store.writes, hasLength(1));
    });

    test('vindication is inclusive at the tolerance', () async {
      final ClockIntegrity integrity = ClockIntegrity(
        store: RecordingWatermarkStore(),
        tolerance: const Duration(seconds: 5),
      );
      await integrity.load();
      await integrity.observe(trueNow);
      await integrity.observe(trueNow.subtract(const Duration(hours: 1)));
      expect(integrity.isRolledBack, isTrue);

      await integrity.reconcile(
        anchorAt(trueNow),
        Duration.zero,
        trueNow.subtract(const Duration(seconds: 5)),
      );
      expect(integrity.isRolledBack, isFalse);
    });

    test('a watermark exactly at the tolerance is not pulled down', () async {
      final RecordingWatermarkStore store = RecordingWatermarkStore();
      final ClockIntegrity integrity = ClockIntegrity(
        store: store,
        tolerance: const Duration(seconds: 5),
      );
      await integrity.load();
      await integrity.observe(trueNow.add(const Duration(seconds: 5)));

      expect(
        await integrity.reconcile(anchorAt(trueNow), Duration.zero, trueNow),
        isFalse,
      );
      expect(integrity.watermark, trueNow.add(const Duration(seconds: 5)));

      await integrity.observe(trueNow.add(const Duration(seconds: 11)));
      expect(
        await integrity.reconcile(anchorAt(trueNow), Duration.zero, trueNow),
        isTrue,
      );
      expect(integrity.watermark, trueNow);
    });

    test('a correction is remembered as written', () async {
      final RecordingWatermarkStore store = RecordingWatermarkStore();
      final ClockIntegrity integrity = ClockIntegrity(
        store: store,
        persistGranularity: const Duration(minutes: 5),
      );
      await integrity.load();
      await integrity.observe(trueNow.add(const Duration(days: 3)));
      await integrity.reconcile(anchorAt(trueNow), Duration.zero, trueNow);
      final int afterCorrection = store.writes.length;

      // Past the granularity measured from the CORRECTED value. Measured
      // from the stale pre-correction one it would still look like a
      // backwards step and write nothing.
      await integrity.observe(trueNow.add(const Duration(minutes: 6)));

      expect(store.writes, hasLength(afterCorrection + 1));
      expect(store.writes.last, trueNow.add(const Duration(minutes: 6)));
    });
  });
}
