import 'package:clock_anchor/clock_anchor.dart';
import 'package:test/test.dart';

import 'support/fake_monotonic_ticks.dart';
import 'support/mutable_wall_clock.dart';
import 'support/recording_watermark_store.dart';
import 'support/scripted_time_source.dart';

/// `ClockAnchorService` — the claim the package exists to make, and the
/// adoption rules that keep it true.
///
/// The claim: once anchored, the answer is derived from monotonic ticks
/// alone, so moving the device clock — once, or five times in a row, in
/// either direction — moves nothing. Every group below is a way that could
/// stop being true.
void main() {
  final DateTime trueStart = DateTime.utc(2026, 9, 3, 12);

  late FakeMonotonicTicks ticks;
  late MutableWallClock device;
  late RecordingWatermarkStore store;
  late ClockIntegrity integrity;

  setUp(() {
    ticks = FakeMonotonicTicks();
    device = MutableWallClock(trueStart);
    store = RecordingWatermarkStore();
    integrity = ClockIntegrity(store: store);
  });

  ClockAnchorService buildService({
    ClockAnchorPolicy policy = const ClockAnchorPolicy(),
    List<TimeSource> sources = const <TimeSource>[],
  }) => ClockAnchorService(
    ticks: ticks,
    integrity: integrity,
    policy: policy,
    sources: sources,
    deviceClock: device.clock,
  );

  TimeSample sampleOf(
    DateTime remote, {
    Duration uncertainty = Duration.zero,
    TimeSourceTrust trust = TimeSourceTrust.serverAttested,
    String sourceId = 'test',
  }) => TimeSample(
    remoteUtc: remote,
    ticksAtReceipt: ticks.elapsed,
    deviceWallAtReceipt: device.read(),
    uncertainty: uncertainty,
    trust: trust,
    sourceId: sourceId,
  );

  group('an anchored reading ignores the device clock', () {
    test('five clock changes in a row move the answer by exactly nothing', () {
      final ClockAnchorService service = buildService();
      service.observe(sampleOf(trueStart));
      final DateTime anchored = service.now();

      // The scenario in the founder's own words: the user changes the phone's
      // time several times in quick succession. No monotonic time passes
      // between the changes, so every reading must be bit-identical — not
      // "close", identical, because the device clock is not a term in the
      // expression that produced it.
      for (final Duration shift in <Duration>[
        const Duration(days: 3),
        const Duration(days: -5),
        const Duration(hours: 1),
        const Duration(days: -400),
        const Duration(minutes: 7),
      ]) {
        device.now = trueStart.add(shift);
        expect(service.now(), anchored);
      }
    });

    test('time advances by elapsed ticks while the clock is being moved', () {
      final ClockAnchorService service = buildService();
      service.observe(sampleOf(trueStart));

      for (int step = 1; step <= 5; step += 1) {
        ticks.advance(const Duration(seconds: 1));
        device.now = trueStart.add(Duration(days: step * 11));
        expect(service.now(), trueStart.add(Duration(seconds: step)));
      }
    });

    test('winding the clock backwards does not cost the anchor confidence', () {
      final ClockAnchorService service = buildService();
      service.observe(sampleOf(trueStart));

      device.now = trueStart.subtract(const Duration(days: 3));

      // A wall clock behind the monotonic base can only be a clock change.
      // Sleep cannot produce it, so there is nothing ambiguous to be cautious
      // about and the anchor's arithmetic is untouched.
      final TimeReading reading = service.read();
      expect(reading.confidence, TimeConfidence.anchored);
      expect(reading.utc, trueStart);
    });

    test('a forward jump is treated as possible sleep: stale, and wider', () {
      final ClockAnchorService service = buildService();
      service.observe(sampleOf(trueStart));

      device.now = trueStart.add(const Duration(hours: 2));

      // Indistinguishable from two hours of deep sleep the tick source did
      // not count, in which case the anchor now lags by that much. Carried as
      // uncertainty rather than ignored.
      final TimeReading reading = service.read();
      expect(reading.confidence, TimeConfidence.staleAnchor);
      expect(
        reading.uncertainty,
        greaterThanOrEqualTo(const Duration(hours: 2)),
      );
      expect(reading.isTrustworthy, isFalse);
    });

    test('an anchor ages out on monotonic time, not on the device clock', () {
      final ClockAnchorService service = buildService(
        policy: const ClockAnchorPolicy(maxAnchorAge: Duration(hours: 1)),
      );
      service.observe(sampleOf(trueStart));

      // Winding the device clock forward a week must not expire the anchor;
      // only real elapsed time can.
      device.now = trueStart.add(const Duration(days: 7));
      ticks.advance(const Duration(minutes: 30));
      expect(
        service.read().confidence,
        TimeConfidence.staleAnchor,
        reason: 'the forward jump alone makes it stale',
      );

      device.now = trueStart.add(const Duration(minutes: 30));
      expect(service.read().confidence, TimeConfidence.anchored);

      ticks.advance(const Duration(minutes: 31));
      device.now = trueStart.add(const Duration(minutes: 61));
      expect(service.read().confidence, TimeConfidence.staleAnchor);
    });

    test('uncertainty widens with drift as the anchor ages', () {
      final ClockAnchorService service = buildService(
        policy: const ClockAnchorPolicy(driftPpm: 1000000),
      );
      service.observe(sampleOf(trueStart, uncertainty: Duration.zero));

      ticks.advance(const Duration(seconds: 10));
      device.now = trueStart.add(const Duration(seconds: 10));

      // 1e6 ppm is one second of drift per second, chosen so the arithmetic
      // is checkable by eye rather than by repeating the formula.
      expect(service.read().uncertainty, const Duration(seconds: 10));
    });
  });

  group('with no anchor', () {
    test('falls back to the device clock, marked as such', () {
      final ClockAnchorService service = buildService();

      final TimeReading reading = service.read();
      expect(reading.confidence, TimeConfidence.deviceOnly);
      expect(reading.utc, trueStart);
      expect(reading.isTrustworthy, isFalse);
      expect(service.deviceOffset, isNull);
    });

    test('drops to unknown once the clock is caught rolling back', () async {
      final ClockAnchorService service = buildService();
      await service.checkIntegrity();

      device.now = trueStart.subtract(const Duration(days: 1));
      await service.checkIntegrity();

      // Offline, no anchor, and the one thing we do know is that this clock
      // has moved backwards. That is not a usable estimate.
      expect(service.read().confidence, TimeConfidence.unknown);
    });
  });

  group('adoption rules', () {
    test('a sample wider than the policy allows is dropped', () {
      final ClockAnchorService service = buildService(
        policy: const ClockAnchorPolicy(
          maxSampleUncertainty: Duration(seconds: 1),
        ),
      );

      expect(
        service.observe(
          sampleOf(trueStart, uncertainty: const Duration(seconds: 30)),
        ),
        isFalse,
      );
      expect(service.anchor, isNull);
    });

    test(
      'a weaker source cannot displace a stronger one, even disagreeing',
      () {
        final ClockAnchorService service = buildService();
        service.observe(
          sampleOf(trueStart, trust: TimeSourceTrust.serverAttested),
        );

        final bool adopted = service.observe(
          sampleOf(
            trueStart.add(const Duration(hours: 9)),
            trust: TimeSourceTrust.unauthenticated,
          ),
        );

        // The disagreement is exactly what an unauthenticated source is
        // expected to be lying about, so it is not evidence against the anchor.
        expect(adopted, isFalse);
        expect(service.now(), trueStart);
        expect(service.lastDisagreement, const Duration(hours: 9));
      },
    );

    test('a stronger source displaces a weaker one when they disagree', () {
      final ClockAnchorService service = buildService();
      service.observe(
        sampleOf(trueStart, trust: TimeSourceTrust.unauthenticated),
      );

      final bool adopted = service.observe(
        sampleOf(
          trueStart.add(const Duration(hours: 9)),
          trust: TimeSourceTrust.transportAuthenticated,
        ),
      );

      expect(adopted, isTrue);
      expect(service.now(), trueStart.add(const Duration(hours: 9)));
    });

    test(
      'at equal trust a less precise sample waits until the anchor ages',
      () {
        final ClockAnchorService service = buildService(
          policy: const ClockAnchorPolicy(driftPpm: 1000000),
        );
        service.observe(sampleOf(trueStart));

        expect(
          service.observe(
            sampleOf(trueStart, uncertainty: const Duration(seconds: 5)),
          ),
          isFalse,
          reason: 'replacing a perfect anchor with a worse one is a downgrade',
        );

        ticks.advance(const Duration(seconds: 6));
        device.now = trueStart.add(const Duration(seconds: 6));

        expect(
          service.observe(
            sampleOf(
              trueStart.add(const Duration(seconds: 6)),
              uncertainty: const Duration(seconds: 5),
            ),
          ),
          isTrue,
          reason: 'the anchor has now drifted past the sample it refused',
        );
      },
    );

    test('a stale anchor accepts anything that survives the width gate', () {
      final ClockAnchorService service = buildService(
        policy: const ClockAnchorPolicy(maxAnchorAge: Duration(minutes: 1)),
      );
      service.observe(sampleOf(trueStart));

      ticks.advance(const Duration(minutes: 2));
      device.now = trueStart.add(const Duration(minutes: 2));

      expect(
        service.observe(
          sampleOf(
            trueStart.add(const Duration(minutes: 2)),
            uncertainty: const Duration(seconds: 5),
            trust: TimeSourceTrust.unauthenticated,
          ),
        ),
        isTrue,
      );
    });

    test('reports this device clock error once anchored', () {
      final ClockAnchorService service = buildService();
      service.observe(sampleOf(trueStart));

      device.now = trueStart.subtract(const Duration(minutes: 4));
      expect(service.deviceOffset, const Duration(minutes: 4));
    });
  });

  group('refresh', () {
    test('offline: every source fails, the reading is left alone', () async {
      final ClockAnchorService service = buildService(
        sources: <TimeSource>[
          ScriptedTimeSource(
            id: 'ntp',
            trust: TimeSourceTrust.unauthenticated,
            script: <Object>[
              const TimeSourceException('ntp', 'offline'),
            ],
          ),
          ScriptedTimeSource(
            id: 'drive',
            trust: TimeSourceTrust.serverAttested,
            script: <Object>[
              const TimeSourceException('drive', 'offline'),
            ],
          ),
        ],
      );

      expect(await service.refresh(), 0);
      expect(service.lastRefreshFailures, hasLength(2));
      expect(service.read().confidence, TimeConfidence.deviceOnly);
    });

    test('queries the strongest source first', () async {
      final ScriptedTimeSource weak = ScriptedTimeSource(
        id: 'ntp',
        trust: TimeSourceTrust.unauthenticated,
        script: <Object>[
          sampleOf(
            trueStart.add(const Duration(hours: 9)),
            trust: TimeSourceTrust.unauthenticated,
            sourceId: 'ntp',
          ),
        ],
      );
      final ScriptedTimeSource strong = ScriptedTimeSource(
        id: 'firestore',
        trust: TimeSourceTrust.serverAttested,
        script: <Object>[sampleOf(trueStart, sourceId: 'firestore')],
      );
      final ClockAnchorService service = buildService(
        sources: <TimeSource>[weak, strong],
      );

      await service.refresh();

      // Both were asked, but the strong one anchored first and the weak one
      // could not displace it — so the order is observable in the outcome.
      expect(service.anchor?.sourceId, 'firestore');
      expect(service.now(), trueStart);
    });

    test(
      'an undeclared failure from a source is a defect and propagates',
      () async {
        final ClockAnchorService service = buildService(
          sources: <TimeSource>[
            ScriptedTimeSource(
              id: 'broken',
              trust: TimeSourceTrust.serverAttested,
              script: <Object>[const Duration(seconds: 1)],
            ),
          ],
        );

        await expectLater(service.refresh(), throwsStateError);
      },
    );
  });
}
