import 'package:clock/clock.dart';
import 'package:hlc/hlc.dart';
import 'package:test/test.dart';

/// [HlcDto] is hand-written rather than generated, so the wire format is not
/// guaranteed by a generator any more — these tests are what guarantees it.
void main() {
  const Hlc hlc = Hlc(
    physicalMs: 1700000000000,
    logical: 3,
    nodeId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
  );

  group('wire format', () {
    test('uses exactly the three documented keys', () {
      // Pinned deliberately. Renaming a key here silently stops every record
      // already in the cloud from decoding, and the failure looks like data
      // loss rather than a format change.
      expect(HlcDto.fromDomain(hlc).toJson(), <String, dynamic>{
        'physicalMs': 1700000000000,
        'logical': 3,
        'nodeId': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      });
    });

    test('round-trips through JSON back to the same Hlc', () {
      final Map<String, dynamic> json = HlcDto.fromDomain(hlc).toJson();
      expect(HlcDto.fromJson(json).toDomain(), hlc);
    });

    test('rejects a missing field rather than defaulting it', () {
      // A defaulted physicalMs of 0 would lose every comparison forever, so
      // the record would look permanently stale instead of obviously broken.
      expect(
        () => HlcDto.fromJson(<String, dynamic>{'logical': 0, 'nodeId': 'n'}),
        throwsA(isA<TypeError>()),
      );
    });

    test('rejects a wrong type rather than coercing it', () {
      expect(
        () => HlcDto.fromJson(<String, dynamic>{
          'physicalMs': '1700000000000',
          'logical': 0,
          'nodeId': 'n',
        }),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('toDomain validation', () {
    test('accepts a value inside the skew window', () {
      withClock(Clock.fixed(DateTime.utc(2026)), () {
        final int nowMs = DateTime.utc(2026).millisecondsSinceEpoch;
        final HlcDto dto = HlcDto(
          physicalMs: nowMs + Duration.millisecondsPerHour,
          logical: 0,
          nodeId: 'n',
        );
        expect(dto.toDomain().physicalMs, nowMs + Duration.millisecondsPerHour);
      });
    });

    test('rejects a physicalMs beyond 24h in the future', () {
      // An HLC far ahead of everyone wins every conflict forever. Rejecting
      // beats clamping: clamping would silently accept the forged ordering.
      withClock(Clock.fixed(DateTime.utc(2026)), () {
        final int nowMs = DateTime.utc(2026).millisecondsSinceEpoch;
        final HlcDto dto = HlcDto(
          physicalMs: nowMs + Duration.millisecondsPerDay + 1,
          logical: 0,
          nodeId: 'n',
        );
        expect(dto.toDomain, throwsA(isA<HlcCorruptedException>()));
      });
    });

    test('rejects a logical counter past the cap', () {
      const HlcDto dto = HlcDto(
        physicalMs: 0,
        logical: (1 << 20) + 1,
        nodeId: 'n',
      );
      expect(dto.toDomain, throwsA(isA<HlcCorruptedException>()));
    });

    test('keeps nodeId out of the exception message', () {
      // nodeId is attacker-influenced. If it reached a log line it would
      // round-trip to whatever crash reporter the consuming app wires up.
      withClock(Clock.fixed(DateTime.utc(2026)), () {
        final int nowMs = DateTime.utc(2026).millisecondsSinceEpoch;
        final HlcDto dto = HlcDto(
          physicalMs: nowMs + Duration.millisecondsPerDay + 1,
          logical: 0,
          nodeId: 'secret-node-id',
        );
        expect(
          () => dto.toDomain(),
          throwsA(
            isA<HlcCorruptedException>().having(
              (HlcCorruptedException e) => e.toString(),
              'toString',
              isNot(contains('secret-node-id')),
            ),
          ),
        );
      });
    });
  });

  group('value semantics', () {
    test('equal fields compare equal and hash alike', () {
      const HlcDto a = HlcDto(physicalMs: 1, logical: 2, nodeId: 'n');
      const HlcDto b = HlcDto(physicalMs: 1, logical: 2, nodeId: 'n');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a differing nodeId is not equal', () {
      const HlcDto a = HlcDto(physicalMs: 1, logical: 2, nodeId: 'n');
      const HlcDto b = HlcDto(physicalMs: 1, logical: 2, nodeId: 'm');
      expect(a, isNot(b));
    });
  });
}
