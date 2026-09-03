import 'dart:typed_data';

import 'package:clock_anchor/clock_anchor_ntp.dart';
import 'package:test/test.dart';

/// `NtpPacket` — the wire format, including the two things that only break
/// on a specific date and would otherwise ship unnoticed.
void main() {
  void writeUint32(Uint8List bytes, int offset, int value) {
    bytes[offset] = (value >> 24) & 0xFF;
    bytes[offset + 1] = (value >> 16) & 0xFF;
    bytes[offset + 2] = (value >> 8) & 0xFF;
    bytes[offset + 3] = value & 0xFF;
  }

  int ntpSecondsFor(DateTime instant) {
    final int unix = instant.millisecondsSinceEpoch ~/ 1000;
    final int era0 = unix + NtpPacket.ntpToUnixSeconds;
    return era0 > 0xFFFFFFFF ? era0 - 0x100000000 : era0;
  }

  Uint8List replyBytes({
    int leapIndicator = 0,
    int mode = 4,
    int stratum = 2,
    int transmitSeconds = 0,
    int transmitFraction = 0,
    String kiss = '',
  }) {
    final Uint8List bytes = Uint8List(NtpPacket.packetLength);
    bytes[0] = (leapIndicator << 6) | (4 << 3) | mode;
    bytes[1] = stratum;
    for (int index = 0; index < kiss.length && index < 4; index += 1) {
      bytes[12 + index] = kiss.codeUnitAt(index);
    }
    writeUint32(bytes, NtpPacket.transmitOffset, transmitSeconds);
    writeUint32(bytes, NtpPacket.transmitOffset + 4, transmitFraction);
    return bytes;
  }

  group('request', () {
    test('is a version 4 client message carrying the nonce', () {
      final NtpPacket request = NtpPacket.request(
        nonceSeconds: 0x11223344,
        nonceFraction: 0x55667788,
      );

      expect(request.bytes, hasLength(48));
      expect(request.bytes[0], 0x23);
      expect((request.bytes[0] >> 6) & 0x03, 0, reason: 'leap indicator');
      expect((request.bytes[0] >> 3) & 0x07, 4, reason: 'version');
      expect(request.bytes[0] & 0x07, 3, reason: 'client mode');
      expect(request.transmitSeconds, 0x11223344);
      expect(request.transmitFraction, 0x55667788);
    });
  });

  group('parse', () {
    test('refuses anything shorter than an SNTP message', () {
      expect(NtpPacket.parse(Uint8List(47)), isNull);
      expect(NtpPacket.parse(Uint8List(0)), isNull);
      expect(NtpPacket.parse(Uint8List(48)), isNotNull);
    });

    test('reads the header fields back out', () {
      final NtpPacket? packet = NtpPacket.parse(
        replyBytes(leapIndicator: 3, mode: 4, stratum: 15),
      );

      expect(packet?.leapIndicator, 3);
      expect(packet?.mode, 4);
      expect(packet?.stratum, 15);
    });

    test('echoes() compares the originate timestamp', () {
      final Uint8List bytes = replyBytes();
      writeUint32(bytes, NtpPacket.originateOffset, 0xAABBCCDD);
      writeUint32(bytes, NtpPacket.originateOffset + 4, 0x01020304);
      final NtpPacket? packet = NtpPacket.parse(bytes);

      expect(
        packet?.echoes(nonceSeconds: 0xAABBCCDD, nonceFraction: 0x01020304),
        isTrue,
      );
      expect(
        packet?.echoes(nonceSeconds: 0xAABBCCDD, nonceFraction: 0),
        isFalse,
      );
    });
  });

  group('timestamps', () {
    test('converts a present-day transmit timestamp', () {
      final DateTime instant = DateTime.utc(2026, 9, 3, 12);
      final NtpPacket? packet = NtpPacket.parse(
        replyBytes(transmitSeconds: ntpSecondsFor(instant)),
      );

      expect(packet?.transmitTime, instant);
    });

    test('the fraction field is a binary fraction of a second', () {
      final DateTime instant = DateTime.utc(2026, 9, 3, 12);
      final NtpPacket? packet = NtpPacket.parse(
        replyBytes(
          transmitSeconds: ntpSecondsFor(instant),
          transmitFraction: 0x80000000,
        ),
      );

      expect(
        packet?.transmitTime,
        instant.add(const Duration(milliseconds: 500)),
      );
    });

    test('survives the 2036 era rollover', () {
      // The seconds field is 32 bits counted from 1900 and wraps in February
      // 2036. Read naively, every timestamp after that decodes as 1900 — a
      // bug that would ship silently today and fire on a fixed date, which is
      // exactly the class of failure this package exists to stop.
      final DateTime afterRollover = DateTime.utc(2040, 6, 1);
      final int seconds = ntpSecondsFor(afterRollover);

      expect(seconds & 0x80000000, 0, reason: 'era bit is clear post-2036');

      final NtpPacket? packet = NtpPacket.parse(
        replyBytes(transmitSeconds: seconds),
      );
      expect(packet?.transmitTime, afterRollover);
    });

    test('the era boundary itself lands where RFC 4330 says', () {
      final DateTime lastOfEraZero = DateTime.utc(2036, 2, 7, 6, 28, 15);
      final DateTime firstOfEraOne = DateTime.utc(2036, 2, 7, 6, 28, 16);

      expect(
        NtpPacket.parse(
          replyBytes(transmitSeconds: ntpSecondsFor(lastOfEraZero)),
        )?.transmitTime,
        lastOfEraZero,
      );
      expect(
        NtpPacket.parse(
          replyBytes(transmitSeconds: ntpSecondsFor(firstOfEraOne)),
        )?.transmitTime,
        firstOfEraOne,
      );
    });
  });

  group('kiss code', () {
    test('is returned for a printable four-letter code', () {
      final NtpPacket? packet = NtpPacket.parse(
        replyBytes(stratum: 0, kiss: 'RATE'),
      );

      expect(packet?.kissCode, 'RATE');
    });

    test('is empty when the bytes are not four upper-case letters', () {
      // A hostile packet must not be able to put control characters into a
      // log line by way of the reference identifier.
      final Uint8List bytes = replyBytes(stratum: 0);
      bytes[12] = 0x07;
      bytes[13] = 0x1B;

      expect(NtpPacket.parse(bytes)?.kissCode, isEmpty);
    });
  });

  group('kiss code bounds', () {
    test('A and Z, the ends of the accepted range, are letters', () {
      expect(
        NtpPacket.parse(replyBytes(stratum: 0, kiss: 'AZZA'))?.kissCode,
        'AZZA',
      );
    });

    test('the character just past each end is not', () {
      final Uint8List belowA = replyBytes(stratum: 0, kiss: 'RATE');
      belowA[12] = 0x40;
      expect(NtpPacket.parse(belowA)?.kissCode, isEmpty);

      final Uint8List pastZ = replyBytes(stratum: 0, kiss: 'RATE');
      pastZ[15] = 0x5B;
      expect(NtpPacket.parse(pastZ)?.kissCode, isEmpty);
    });
  });
}
