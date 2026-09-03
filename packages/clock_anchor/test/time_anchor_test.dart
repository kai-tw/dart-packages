import 'package:clock_anchor/clock_anchor.dart';
import 'package:test/test.dart';

/// `TimeAnchor` — the arithmetic everything else rests on.
///
/// Small enough to read, load-bearing enough that a sign error here would be
/// invisible everywhere else: it would still produce plausible timestamps,
/// just wrong ones.
void main() {
  final DateTime reference = DateTime.utc(2026, 9, 3, 12);

  TimeAnchor anchor({
    Duration ticksAtReference = const Duration(minutes: 5),
    Duration uncertainty = Duration.zero,
  }) => TimeAnchor(
    referenceUtc: reference,
    ticksAtReference: ticksAtReference,
    deviceWallAtReference: reference,
    uncertainty: uncertainty,
    trust: TimeSourceTrust.serverAttested,
    sourceId: 'test',
  );

  test('time is the reference plus elapsed ticks, and nothing else', () {
    expect(
      anchor().timeAt(const Duration(minutes: 8)),
      reference.add(const Duration(minutes: 3)),
    );
  });

  test('a local DateTime is normalised to UTC on the way in', () {
    final TimeAnchor local = TimeAnchor(
      referenceUtc: reference.toLocal(),
      ticksAtReference: Duration.zero,
      deviceWallAtReference: reference.toLocal(),
      uncertainty: Duration.zero,
      trust: TimeSourceTrust.serverAttested,
      sourceId: 'test',
    );

    expect(local.referenceUtc.isUtc, isTrue);
    expect(local.timeAt(Duration.zero), reference);
  });

  test('age is measured in ticks, so no clock can influence it', () {
    expect(
      anchor().ageAt(const Duration(minutes: 12)),
      const Duration(minutes: 7),
    );
  });

  test('drift widens the uncertainty in proportion to age', () {
    final TimeAnchor aged = anchor(
      ticksAtReference: Duration.zero,
      uncertainty: const Duration(milliseconds: 20),
    );

    // 1000 ppm is a millisecond per second; ten seconds of age therefore adds
    // exactly ten milliseconds to the twenty it started with.
    expect(
      aged.uncertaintyAt(const Duration(seconds: 10), 1000),
      const Duration(milliseconds: 30),
    );
  });

  group('discrepancy', () {
    test('is zero when the wall clock keeps step with the ticks', () {
      expect(
        anchor().discrepancyAt(
          const Duration(minutes: 6),
          reference.add(const Duration(minutes: 1)),
        ),
        Duration.zero,
      );
    });

    test('is positive when the wall clock ran ahead — a jump, or sleep', () {
      expect(
        anchor().discrepancyAt(
          const Duration(minutes: 6),
          reference.add(const Duration(hours: 3, minutes: 1)),
        ),
        const Duration(hours: 3),
      );
    });

    test('is negative when the wall clock went back — only a clock change', () {
      expect(
        anchor().discrepancyAt(
          const Duration(minutes: 6),
          reference.subtract(const Duration(hours: 2)),
        ),
        const Duration(hours: -2, minutes: -1),
      );
    });
  });
}
