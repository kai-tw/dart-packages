import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'ntp_exchange.dart';

/// The real [NtpExchange]: one UDP datagram out, the first one back.
///
/// Deliberately the whole of the I/O. Everything that decides whether a reply
/// is usable lives in `NtpTimeSource`, on the other side of the [NtpExchange]
/// seam, so those decisions can be tested without a socket.
class NtpUdpExchange implements NtpExchange {
  /// Binds an ephemeral port per exchange; there is no long-lived socket.
  ///
  /// [resolve] is a seam for the same reason [NtpExchange] itself is one:
  /// without it, the branch where a host resolves to nothing is unreachable
  /// from a test and would ship unexercised.
  const NtpUdpExchange({this.resolve = InternetAddress.lookup});

  /// Resolves a host name to addresses. Defaults to the platform resolver.
  final Future<List<InternetAddress>> Function(String host) resolve;

  @override
  Future<Uint8List> exchange(
    Uint8List request, {
    required String host,
    required int port,
    required Duration timeout,
  }) async {
    final List<InternetAddress> addresses = await resolve(host);
    if (addresses.isEmpty) {
      throw const SocketException('no address resolved for NTP host');
    }
    final RawDatagramSocket socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
    );
    try {
      return await _firstReply(
        socket,
        request,
        addresses.first,
        port,
        timeout,
      );
    } finally {
      socket.close();
    }
  }

  Future<Uint8List> _firstReply(
    RawDatagramSocket socket,
    Uint8List request,
    InternetAddress address,
    int port,
    Duration timeout,
  ) async {
    final Completer<Uint8List> completer = Completer<Uint8List>();
    final StreamSubscription<RawSocketEvent> subscription = socket.listen((
      RawSocketEvent event,
    ) {
      if (event != RawSocketEvent.read) {
        return;
      }
      final Datagram? datagram = socket.receive();
      if (datagram == null || completer.isCompleted) {
        return;
      }
      completer.complete(datagram.data);
    });
    try {
      socket.send(request, address, port);
      return await completer.future.timeout(timeout);
    } finally {
      await subscription.cancel();
    }
  }
}
