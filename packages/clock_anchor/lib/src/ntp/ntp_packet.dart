import 'dart:typed_data';

/// The 48-byte SNTP message, encoded and decoded.
///
/// Only what a client needs: enough of the header to reject an answer that
/// should not be trusted, the originate timestamp for the anti-spoofing echo
/// check, and the transmit timestamp that is the actual payload.
class NtpPacket {
  /// Builds a client request carrying [nonceSeconds] / [nonceFraction] as its
  /// transmit timestamp.
  ///
  /// A conforming server copies that value back into the reply's *originate*
  /// field, so a random nonce turns into a cheap check that the reply belongs
  /// to this request. It is not authentication — anyone who can see the
  /// request can echo it — but it does cost a blind off-path spoofer the
  /// ability to answer.
  factory NtpPacket.request({
    required int nonceSeconds,
    required int nonceFraction,
  }) {
    final Uint8List bytes = Uint8List(packetLength);
    // LI = 0 (no warning), VN = 4, Mode = 3 (client).
    bytes[0] = 0x23;
    _writeUint32(bytes, transmitOffset, nonceSeconds);
    _writeUint32(bytes, transmitOffset + 4, nonceFraction);
    return NtpPacket._(
      bytes: bytes,
      leapIndicator: 0,
      mode: 3,
      stratum: 0,
      originateSeconds: 0,
      originateFraction: 0,
      transmitSeconds: nonceSeconds,
      transmitFraction: nonceFraction,
    );
  }

  const NtpPacket._({
    required this.bytes,
    required this.leapIndicator,
    required this.mode,
    required this.stratum,
    required this.originateSeconds,
    required this.originateFraction,
    required this.transmitSeconds,
    required this.transmitFraction,
  });

  /// Decodes a reply, or returns null when it is too short to be one.
  ///
  /// Only the length is checked here. Whether the *contents* are acceptable —
  /// the mode, the stratum, the leap indicator, the echoed nonce — is
  /// `NtpTimeSource`'s decision, so that every rejection is reported with one
  /// vocabulary.
  static NtpPacket? parse(Uint8List bytes) {
    if (bytes.length < packetLength) {
      return null;
    }
    return NtpPacket._(
      bytes: bytes,
      leapIndicator: (bytes[0] >> 6) & 0x03,
      mode: bytes[0] & 0x07,
      stratum: bytes[1],
      originateSeconds: _readUint32(bytes, originateOffset),
      originateFraction: _readUint32(bytes, originateOffset + 4),
      transmitSeconds: _readUint32(bytes, transmitOffset),
      transmitFraction: _readUint32(bytes, transmitOffset + 4),
    );
  }

  /// Length of an SNTP message without extensions.
  static const int packetLength = 48;

  /// Byte offset of the originate timestamp.
  static const int originateOffset = 24;

  /// Byte offset of the transmit timestamp.
  static const int transmitOffset = 40;

  /// Seconds between the NTP epoch (1900-01-01) and the Unix epoch.
  static const int ntpToUnixSeconds = 2208988800;

  /// What to add instead when the era bit says the timestamp is post-2036:
  /// `2^32 - ntpToUnixSeconds`.
  static const int ntpEraOneSeconds = 2085978496;

  /// The wire bytes.
  final Uint8List bytes;

  /// 0 no warning, 1 last minute has 61 seconds, 2 has 59, 3 unsynchronized.
  final int leapIndicator;

  /// 3 for a client request, 4 for a server reply.
  final int mode;

  /// 1-15 for a usable server; 0 is a kiss-o'-death, 16+ unsynchronized.
  final int stratum;

  /// Seconds field of the originate timestamp — the client's transmit value,
  /// echoed back.
  final int originateSeconds;

  /// Fraction field of the originate timestamp.
  final int originateFraction;

  /// Seconds field of the transmit timestamp — when the server sent the reply.
  final int transmitSeconds;

  /// Fraction field of the transmit timestamp.
  final int transmitFraction;

  /// The four-character kiss code a stratum-0 reply carries in the reference
  /// identifier, for diagnostics.
  ///
  /// Only meaningful when [stratum] is 0. Returned as its ASCII letters when
  /// it is printable and as an empty string otherwise, so a hostile packet
  /// cannot inject control characters into a log line.
  String get kissCode {
    final StringBuffer buffer = StringBuffer();
    for (int index = 12; index < 16; index += 1) {
      final int byte = bytes[index];
      if (byte < 0x41 || byte > 0x5A) {
        return '';
      }
      buffer.writeCharCode(byte);
    }
    return buffer.toString();
  }

  /// The transmit timestamp as a UTC [DateTime].
  ///
  /// Handles the 2036 rollover the way RFC 4330 §3 prescribes: the seconds
  /// field is 32 bits and wraps, so the high bit selects the era. Set means
  /// 1968-2036 counted from 1900; clear means 2036-2104 counted from the
  /// rollover. Without this the package would start reading 2036 as 1900 on
  /// a fixed date, which is exactly the class of bug it exists to prevent.
  DateTime get transmitTime => _toDateTime(transmitSeconds, transmitFraction);

  /// Whether this reply echoes the nonce that was sent.
  bool echoes({required int nonceSeconds, required int nonceFraction}) =>
      originateSeconds == nonceSeconds && originateFraction == nonceFraction;

  static DateTime _toDateTime(int seconds, int fraction) {
    final bool eraZero = (seconds & 0x80000000) != 0;
    final int unixSeconds = eraZero
        ? seconds - ntpToUnixSeconds
        : seconds + ntpEraOneSeconds;
    // The fraction is a binary fraction of a second over 2^32.
    final int microseconds = (fraction * 1000000) >> 32;
    return DateTime.fromMicrosecondsSinceEpoch(
      unixSeconds * 1000000 + microseconds,
      isUtc: true,
    );
  }

  static int _readUint32(Uint8List bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  static void _writeUint32(Uint8List bytes, int offset, int value) {
    bytes[offset] = (value >> 24) & 0xFF;
    bytes[offset + 1] = (value >> 16) & 0xFF;
    bytes[offset + 2] = (value >> 8) & 0xFF;
    bytes[offset + 3] = value & 0xFF;
  }
}
