import 'package:clock/clock.dart';
import 'package:clock_anchor/clock_anchor.dart';
import 'package:hybrid_logical_clock/hybrid_logical_clock.dart';
import 'package:test/test.dart';

import 'support/fake_monotonic_ticks.dart';
import 'support/mutable_wall_clock.dart';
import 'support/recording_watermark_store.dart';

/// The claim this package was built to make, tested against the real
/// `hybrid_logical_clock` rather than a stand-in.
///
/// "Moving the phone's clock must not move an HLC stamp" is a statement about
/// the two packages together. A test that faked either half would prove
/// nothing about the pair, which is why `hybrid_logical_clock` is a
/// dev-dependency here.
void main() {
  final DateTime trueStart = DateTime.utc(2026, 9, 3, 12);
  const String nodeId = 'device-a';

  late FakeMonotonicTicks ticks;
  late MutableWallClock device;
  late ClockAnchorService service;

  setUp(() {
    ticks = FakeMonotonicTicks();
    device = MutableWallClock(trueStart);
    service = ClockAnchorService(
      ticks: ticks,
      integrity: ClockIntegrity(store: RecordingWatermarkStore()),
      deviceClock: device.clock,
    );
    service.observe(
      TimeSample(
        remoteUtc: trueStart,
        ticksAtReceipt: ticks.elapsed,
        deviceWallAtReceipt: device.read(),
        uncertainty: Duration.zero,
        trust: TimeSourceTrust.serverAttested,
        sourceId: 'test',
      ),
    );
  });

  /// Re-anchors on a fresh sample, as a successful `refresh()` would once
  /// connectivity comes back. This resets the anchor's record of what the
  /// device clock says, which is what clears the forward-discrepancy staleness
  /// a clock jump leaves behind — the repair pass deliberately waits for it
  /// rather than acting on an anchor it has already flagged as suspect.
  void reanchor() {
    service.observe(
      TimeSample(
        remoteUtc: trueStart,
        ticksAtReceipt: ticks.elapsed,
        deviceWallAtReceipt: device.read(),
        uncertainty: Duration.zero,
        trust: TimeSourceTrust.serverAttested,
        sourceId: 'refresh',
      ),
    );
  }

  DateTime stampTime(Hlc stamp) =>
      DateTime.fromMillisecondsSinceEpoch(stamp.physicalMs, isUtc: true);

  group('stamping', () {
    test('an anchored HLC does not move when the user moves the clock', () {
      final HlcClock hlc = HlcClockImpl(
        nodeId: nodeId,
        clock: AnchoredClock(service),
      );

      final Hlc first = hlc.tick();
      for (final Duration shift in <Duration>[
        const Duration(days: 3),
        const Duration(days: -5),
        const Duration(days: 400),
      ]) {
        device.now = trueStart.add(shift);
      }
      ticks.advance(const Duration(seconds: 2));
      final Hlc second = hlc.tick();

      expect(stampTime(first), trueStart);
      expect(second.physicalMs - first.physicalMs, 2000);
    });

    test(
      'the same clock on the raw device clock is poisoned, and stays so',
      () {
        // The control. Without an anchor, one forward jump lands in
        // `_lastEmitted` and HLC's own monotonicity guarantees every later
        // stamp inherits it — the clock being wound back changes nothing.
        final HlcClock hlc = HlcClockImpl(nodeId: nodeId, clock: device.clock);

        hlc.tick();
        device.now = trueStart.add(const Duration(days: 3));
        final Hlc poisoned = hlc.tick();
        device.now = trueStart;
        final Hlc afterWindBack = hlc.tick();

        expect(stampTime(poisoned), trueStart.add(const Duration(days: 3)));
        expect(
          stampTime(afterWindBack),
          trueStart.add(const Duration(days: 3)),
          reason: 'HLC never goes backwards, so the bad value is sticky',
        );
      },
    );
  });

  group('the future-stamp ceiling', () {
    // `HlcDto.toDomain()` measures a stamp against the *ambient* clock, so
    // installing the anchored clock with `withClock` is the whole
    // integration — no call site changes.
    final HlcDto peerStamp = HlcDto(
      physicalMs: trueStart.millisecondsSinceEpoch,
      logical: 0,
      nodeId: 'device-b',
    );

    test(
      'a two-day-slow device rejects a peer stamp that is perfectly valid',
      () {
        device.now = trueStart.subtract(const Duration(days: 2));

        expect(
          () => withClock(device.clock, peerStamp.toDomain),
          throwsA(isA<HlcCorruptedException>()),
          reason: 'now + 24h is still a day behind the peer stamp',
        );
      },
    );

    test('under the anchor the same stamp is accepted', () {
      device.now = trueStart.subtract(const Duration(days: 2));

      final Hlc decoded = withClock(AnchoredClock(service), peerStamp.toDomain);

      expect(decoded.physicalMs, trueStart.millisecondsSinceEpoch);
    });

    test('a two-day-fast device stamps writes every peer would reject', () {
      device.now = trueStart.add(const Duration(days: 2));
      final HlcClock unanchored = HlcClockImpl(
        nodeId: nodeId,
        clock: device.clock,
      );
      final HlcClock anchored = HlcClockImpl(
        nodeId: nodeId,
        clock: AnchoredClock(service),
      );

      final HlcDto fromBadClock = HlcDto.fromDomain(unanchored.tick());
      final HlcDto fromAnchor = HlcDto.fromDomain(anchored.tick());

      // A peer whose own clock is right applies the same 24h ceiling.
      expect(
        () => withClock(Clock.fixed(trueStart), fromBadClock.toDomain),
        throwsA(isA<HlcCorruptedException>()),
      );
      expect(
        withClock(Clock.fixed(trueStart), fromAnchor.toDomain).physicalMs,
        trueStart.millisecondsSinceEpoch,
      );
    });
  });

  group('repairing what was written before the anchor existed', () {
    test('exactly the stamps from the bad window are planned', () {
      // Offline, no anchor yet, clock three days fast: everything written now
      // is poisoned. This is the residue anchoring cannot prevent.
      device.now = trueStart.add(const Duration(days: 3));
      final HlcClock offline = HlcClockImpl(
        nodeId: nodeId,
        clock: device.clock,
      );
      final Hlc poisonedOne = offline.tick();
      final Hlc poisonedTwo = offline.tick();

      reanchor();
      final Hlc healthy = HlcClockImpl(
        nodeId: nodeId,
        clock: AnchoredClock(service),
      ).tick();

      const StampRepairPolicy policy = StampRepairPolicy();
      final List<Hlc> planned = policy.plan<Hlc>(
        <Hlc>[poisonedOne, poisonedTwo, healthy],
        stampOf: stampTime,
        now: service.read(),
      );

      expect(planned, <Hlc>[poisonedOne, poisonedTwo]);
    });

    test('re-issuing on a fresh clock brings them back under the ceiling', () {
      device.now = trueStart.add(const Duration(days: 3));
      final Hlc poisoned = HlcClockImpl(
        nodeId: nodeId,
        clock: device.clock,
      ).tick();

      reanchor();

      // Re-issued on a clock instance that has not seen the poisoned value.
      // `HlcClockImpl._lastEmitted` is in-memory and takes the maximum of the
      // wall reading and what it has already emitted, so re-stamping through
      // the *same* instance would carry the bad value forward — the repair
      // pass has to re-seat the clock, which today means building a new one.
      final Hlc repaired = HlcClockImpl(
        nodeId: nodeId,
        clock: AnchoredClock(service),
      ).tick();

      expect(stampTime(repaired), trueStart);
      expect(repaired.compareTo(poisoned), lessThan(0));
      expect(
        withClock(
          Clock.fixed(trueStart),
          HlcDto.fromDomain(repaired).toDomain,
        ).physicalMs,
        trueStart.millisecondsSinceEpoch,
      );
    });

    test('nothing is repaired while the reading is not trustworthy', () {
      final ClockAnchorService unanchored = ClockAnchorService(
        ticks: ticks,
        integrity: ClockIntegrity(store: RecordingWatermarkStore()),
        deviceClock: device.clock,
      );
      device.now = trueStart.add(const Duration(days: 3));
      final Hlc stamp = HlcClockImpl(
        nodeId: nodeId,
        clock: device.clock,
      ).tick();

      const StampRepairPolicy policy = StampRepairPolicy();

      // A device that is merely behind would otherwise rewrite every correct
      // stamp it owns — the same mistake in the other direction.
      expect(
        policy.plan<Hlc>(
          <Hlc>[stamp],
          stampOf: stampTime,
          now: unanchored.read(),
        ),
        isEmpty,
      );
    });
  });
}
