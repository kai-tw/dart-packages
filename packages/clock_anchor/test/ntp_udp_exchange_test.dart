import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock_anchor/clock_anchor_ntp.dart';
import 'package:test/test.dart';

/// `NtpUdpExchange` — the only part of the package that touches a socket.
///
/// Exercised against a loopback server rather than mocked away: the parts
/// worth pinning are the ones a fake cannot have — that a reply is actually
/// received, that a silent server becomes a timeout rather than a hang, and
/// that the listener is torn down either way.
void main() {
  late RawDatagramSocket server;

  setUp(() async {
    server = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() {
    server.close();
  });

  /// Answers the first datagram with [reply], or stays silent when null.
  void serveOnce(Uint8List? reply) {
    server.listen((RawSocketEvent event) {
      if (event != RawSocketEvent.read) {
        return;
      }
      final Datagram? datagram = server.receive();
      if (datagram == null || reply == null) {
        return;
      }
      server.send(reply, datagram.address, datagram.port);
    });
  }

  test('sends a request and returns the reply', () async {
    final Uint8List reply = Uint8List.fromList(
      List<int>.generate(NtpPacket.packetLength, (int index) => index),
    );
    serveOnce(reply);

    final Uint8List received = await const NtpUdpExchange().exchange(
      NtpPacket.request(nonceSeconds: 1, nonceFraction: 2).bytes,
      host: '127.0.0.1',
      port: server.port,
      timeout: const Duration(seconds: 5),
    );

    expect(received, reply);
  });

  test('a silent server becomes a timeout, not a hang', () async {
    serveOnce(null);

    await expectLater(
      const NtpUdpExchange().exchange(
        NtpPacket.request(nonceSeconds: 1, nonceFraction: 2).bytes,
        host: '127.0.0.1',
        port: server.port,
        timeout: const Duration(milliseconds: 200),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('a host that resolves to nothing is a socket failure', () async {
    // Declared rather than left to `.first` on an empty list, which would
    // surface as a StateError and be treated as a defect instead of an
    // outage.
    const NtpUdpExchange exchange = NtpUdpExchange(resolve: _noAddresses);

    await expectLater(
      exchange.exchange(
        NtpPacket.request(nonceSeconds: 1, nonceFraction: 2).bytes,
        host: 'nowhere.invalid',
        port: 123,
        timeout: const Duration(seconds: 1),
      ),
      throwsA(isA<SocketException>()),
    );
  });
}

Future<List<InternetAddress>> _noAddresses(String host) async =>
    <InternetAddress>[];
