import 'dart:typed_data';

import 'package:clock_anchor/clock_anchor_ntp.dart';

/// An [NtpExchange] driven by a handler the test supplies.
///
/// Every rule worth pinning in the SNTP client is a property of the reply, so
/// the reply is what a test needs to control — including the nonce echo,
/// which can only be exercised by building the reply *from* the request.
/// Standing up a real UDP server would pin none of it.
class ScriptedNtpExchange implements NtpExchange {
  /// [handler] receives the request bytes and returns the reply, or throws to
  /// simulate a transport failure. It is also the place to advance a fake
  /// tick source, which is how a round trip is given a duration.
  ScriptedNtpExchange(this.handler);

  /// The handler.
  final Uint8List Function(Uint8List request) handler;

  /// The last request seen.
  Uint8List? lastRequest;

  @override
  Future<Uint8List> exchange(
    Uint8List request, {
    required String host,
    required int port,
    required Duration timeout,
  }) async {
    lastRequest = request;
    return handler(request);
  }
}
