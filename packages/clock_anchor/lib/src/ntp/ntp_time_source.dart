import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:clock/clock.dart';

import '../monotonic_ticks.dart';
import '../time_sample.dart';
import '../time_source.dart';
import '../time_source_trust.dart';
import 'ntp_exchange.dart';
import 'ntp_packet.dart';
import 'ntp_query_exception.dart';
import 'ntp_udp_exchange.dart';

/// An SNTP client, as a [TimeSource].
///
/// Its value is availability, not strength: it needs no account, no sign-in
/// and no prior relationship with a server, so it can correct a device whose
/// clock is simply wrong — the overwhelmingly common case — on a first run
/// and while signed out. That is why it exists.
///
/// It is [TimeSourceTrust.unauthenticated] and cannot be anything else. The
/// exchange is plaintext UDP with no signature, so whoever controls the
/// network can drop it or answer it, and that is the same person who would be
/// setting the device clock deliberately. The nonce echo below raises the bar
/// to *on-path*; it does not clear it. Nothing here may lower the rollback
/// watermark.
///
/// The default host is Google's, because both consuming apps already talk to
/// Google over other paths — using it adds no party that can observe the
/// device. Note that it smears leap seconds rather than stepping, which is
/// irrelevant at the resolution anything here cares about.
class NtpTimeSource implements TimeSource {
  /// [exchange] and [random] are seams for tests; production wants the
  /// defaults.
  NtpTimeSource({
    required MonotonicTicks ticks,
    this.id = 'ntp',
    this.host = 'time.google.com',
    this.port = 123,
    Duration timeout = const Duration(seconds: 5),
    NtpExchange exchange = const NtpUdpExchange(),
    Random? random,
    Clock deviceClock = const Clock(),
    DateTime? plausibleFrom,
    DateTime? plausibleUntil,
  }) : _ticks = ticks,
       _timeout = timeout,
       _exchange = exchange,
       _random = random ?? Random.secure(),
       _deviceClock = deviceClock,
       _plausibleFrom = plausibleFrom ?? DateTime.utc(2020),
       _plausibleUntil = plausibleUntil ?? DateTime.utc(2100);

  @override
  final String id;

  /// The NTP server to query.
  final String host;

  /// The NTP port. 123 everywhere that is not a test.
  final int port;

  final MonotonicTicks _ticks;
  final Duration _timeout;
  final NtpExchange _exchange;
  final Random _random;
  final Clock _deviceClock;
  final DateTime _plausibleFrom;
  final DateTime _plausibleUntil;

  @override
  TimeSourceTrust get trust => TimeSourceTrust.unauthenticated;

  @override
  Future<TimeSample> sample() async {
    final int nonceSeconds = _random.nextInt(0x100000000);
    final int nonceFraction = _random.nextInt(0x100000000);
    final NtpPacket request = NtpPacket.request(
      nonceSeconds: nonceSeconds,
      nonceFraction: nonceFraction,
    );

    final Duration sentAt = _ticks.elapsed;
    final Uint8List raw = await _send(request.bytes);
    final Duration receivedAt = _ticks.elapsed;

    final NtpPacket? reply = NtpPacket.parse(raw);
    if (reply == null) {
      throw NtpQueryException(
        id,
        'reply shorter than an SNTP message (${raw.length} bytes)',
      );
    }
    _rejectUnusableHeader(reply, nonceSeconds, nonceFraction);
    final DateTime transmitted = _usableTransmitTime(reply);

    // The round trip is measured on the monotonic base, so a clock change
    // landing mid-exchange cannot corrupt it.
    //
    // The estimate deliberately departs from RFC 4330's offset formula, which
    // combines the server's two timestamps with the client's own send and
    // receive readings. Those readings come from the device clock — the thing
    // this package exists to stop trusting — so `transmit + roundTrip / 2` is
    // used instead. It assumes a symmetric path, and the error that
    // assumption can introduce is bounded by half the round trip, which is
    // exactly what is reported as the uncertainty.
    final Duration halfTrip = (receivedAt - sentAt) ~/ 2;
    return TimeSample(
      remoteUtc: transmitted.add(halfTrip),
      ticksAtReceipt: receivedAt,
      deviceWallAtReceipt: _deviceClock.now(),
      uncertainty: halfTrip,
      trust: trust,
      sourceId: id,
    );
  }

  Future<Uint8List> _send(Uint8List request) async {
    try {
      return await _exchange.exchange(
        request,
        host: host,
        port: port,
        timeout: _timeout,
      );
    } on SocketException catch (error) {
      throw NtpQueryException(
        id,
        'socket failure (${error.osError?.errorCode})',
      );
    } on TimeoutException catch (_) {
      throw NtpQueryException(id, 'no reply within $_timeout');
    }
  }

  void _rejectUnusableHeader(
    NtpPacket reply,
    int nonceSeconds,
    int nonceFraction,
  ) {
    if (reply.mode != 4) {
      throw NtpQueryException(id, 'reply mode ${reply.mode} is not server');
    }
    if (reply.leapIndicator == 3) {
      throw NtpQueryException(id, 'server reports itself unsynchronized');
    }
    if (reply.stratum == 0) {
      throw NtpQueryException(id, 'kiss-o-death (${reply.kissCode})');
    }
    if (reply.stratum >= 16) {
      throw NtpQueryException(id, 'stratum ${reply.stratum} is unusable');
    }
    if (!reply.echoes(
      nonceSeconds: nonceSeconds,
      nonceFraction: nonceFraction,
    )) {
      // The originate field did not come back as sent, so this reply is not
      // an answer to this request — a stale datagram, or an off-path spoof.
      throw NtpQueryException(id, 'originate timestamp does not echo request');
    }
  }

  DateTime _usableTransmitTime(NtpPacket reply) {
    if (reply.transmitSeconds == 0 && reply.transmitFraction == 0) {
      throw NtpQueryException(id, 'transmit timestamp is zero');
    }
    final DateTime transmitted = reply.transmitTime;
    if (transmitted.isBefore(_plausibleFrom) ||
        transmitted.isAfter(_plausibleUntil)) {
      // A floor and a ceiling on an unauthenticated source, not a claim about
      // what time it is: a packet asserting 1900 or 2400 is malformed however
      // wrong the device's own clock happens to be, and the window is wide
      // enough that no real server can fall outside it.
      throw NtpQueryException(id, 'transmit timestamp outside plausible range');
    }
    return transmitted;
  }
}
