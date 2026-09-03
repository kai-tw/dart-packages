/// The SNTP time source, kept out of `clock_anchor.dart` so that the core
/// library takes no `dart:io` dependency.
///
/// Import this only where an app actually wants to query an NTP server.
/// [NtpTimeSource] is [TimeSourceTrust.unauthenticated] by construction — the
/// exchange is plaintext UDP that anyone on the path can answer — so it can
/// correct an honest wrong clock but must never be the thing that lowers the
/// rollback watermark.
library;

export 'src/ntp/ntp_exchange.dart';
export 'src/ntp/ntp_packet.dart';
export 'src/ntp/ntp_query_exception.dart';
export 'src/ntp/ntp_time_source.dart';
export 'src/ntp/ntp_udp_exchange.dart';
