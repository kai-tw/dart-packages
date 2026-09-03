import 'package:clock_anchor/clock_anchor.dart';
import 'package:test/test.dart';

import 'support/fake_monotonic_ticks.dart';
import 'support/mutable_wall_clock.dart';

/// `CallbackTimeSource` — the adapter for a service the app already talks to,
/// and the arithmetic it applies to what comes back.
void main() {
  final DateTime serverTime = DateTime.utc(2026, 9, 3, 12);

  late FakeMonotonicTicks ticks;
  late MutableWallClock device;

  setUp(() {
    ticks = FakeMonotonicTicks(const Duration(minutes: 7));
    device = MutableWallClock(DateTime.utc(2026, 9, 1));
  });

  CallbackTimeSource buildSource(
    Future<DateTime> Function() probe, {
    Duration resolution = Duration.zero,
    TimeSourceTrust trust = TimeSourceTrust.serverAttested,
  }) => CallbackTimeSource(
    id: 'firestore',
    trust: trust,
    ticks: ticks,
    probe: probe,
    resolution: resolution,
    deviceClock: device.clock,
  );

  test(
    'half the round trip is added to the estimate and the error bar',
    () async {
      final CallbackTimeSource source = buildSource(() async {
        ticks.advance(const Duration(milliseconds: 300));
        return serverTime;
      });

      final TimeSample sample = await source.sample();

      expect(
        sample.remoteUtc,
        serverTime.add(const Duration(milliseconds: 150)),
      );
      expect(sample.uncertainty, const Duration(milliseconds: 150));
      expect(
        sample.ticksAtReceipt,
        const Duration(minutes: 7, milliseconds: 300),
      );
      expect(sample.sourceId, 'firestore');
    },
  );

  test('a coarse remote resolution widens both halves again', () async {
    final CallbackTimeSource source = buildSource(
      () async {
        ticks.advance(const Duration(milliseconds: 300));
        return serverTime;
      },
      resolution: const Duration(seconds: 1),
    );

    final TimeSample sample = await source.sample();

    expect(sample.remoteUtc, serverTime.add(const Duration(milliseconds: 650)));
    expect(sample.uncertainty, const Duration(milliseconds: 650));
  });

  test('a clock change mid-request cannot corrupt the round trip', () async {
    final CallbackTimeSource source = buildSource(() async {
      ticks.advance(const Duration(milliseconds: 300));
      // The measurement is taken on the monotonic base, so this is invisible
      // to it. Timing the request on the wall clock would report a round trip
      // of five years.
      device.now = DateTime.utc(2031);
      return serverTime;
    });

    final TimeSample sample = await source.sample();

    expect(sample.uncertainty, const Duration(milliseconds: 150));
    expect(sample.deviceWallAtReceipt, DateTime.utc(2031));
  });

  test(
    'the device offset is recorded but never used to build the estimate',
    () async {
      device.now = serverTime.subtract(const Duration(minutes: 90));
      final CallbackTimeSource source = buildSource(() async => serverTime);

      final TimeSample sample = await source.sample();

      expect(sample.deviceOffset, const Duration(minutes: 90));
      expect(sample.remoteUtc, serverTime);
    },
  );

  test('a local DateTime from the callback is normalised to UTC', () async {
    final CallbackTimeSource source = buildSource(
      () async => serverTime.toLocal(),
    );

    final TimeSample sample = await source.sample();

    expect(sample.remoteUtc.isUtc, isTrue);
    expect(sample.remoteUtc, serverTime);
  });

  test(
    'a failure the callback declares reaches the caller unchanged',
    () async {
      await expectLater(
        buildSource(() async {
          throw const TimeSourceException('firestore', 'offline');
        }).sample(),
        throwsA(isA<TimeSourceException>()),
      );
    },
  );
}
