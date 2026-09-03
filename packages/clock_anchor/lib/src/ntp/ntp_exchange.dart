import 'dart:typed_data';

/// Sends one SNTP request and returns the reply.
///
/// A seam, and the reason the SNTP client is testable at all: every rule
/// worth pinning — a spoofed nonce, a kiss-o'-death, a stratum-16 server, the
/// 2036 rollover — is a property of the *reply*, and a test that had to stand
/// up a UDP server to produce one would pin none of them.
abstract class NtpExchange {
  /// Sends [request] to [host]:[port] and completes with the first reply.
  ///
  /// Must complete with an error if nothing arrives within [timeout]; the
  /// caller translates that into an `NtpQueryException`.
  Future<Uint8List> exchange(
    Uint8List request, {
    required String host,
    required int port,
    required Duration timeout,
  });
}
