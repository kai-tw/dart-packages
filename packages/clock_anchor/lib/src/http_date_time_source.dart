import 'package:clock/clock.dart';

import 'http_date_exception.dart';
import 'monotonic_ticks.dart';
import 'time_sample.dart';
import 'time_source.dart';
import 'time_source_trust.dart';

/// A [TimeSource] reading the `Date` header of an HTTPS response.
///
/// Worth having because of what it is *not*: unlike SNTP, this value arrives
/// inside a validated TLS session, so forging it needs a certificate the
/// platform trust store accepts rather than a spoofed UDP packet. That is
/// what earns it [TimeSourceTrust.transportAuthenticated] and, with it, the
/// right to lower the rollback watermark.
///
/// The price is resolution: the header carries whole seconds, so a sample can
/// never be better than half a second even on a perfect link.
///
/// The probe is injected rather than built here — the package takes no HTTP
/// dependency, and the app's own client already owns TLS policy, redirects
/// and timeouts. **The probe must reject a plain-http URL and any downgrade
/// redirect**; a `Date` read over cleartext is worth no more than SNTP while
/// claiming to be worth more.
class HttpDateTimeSource implements TimeSource {
  /// [probe] performs one request to [uri] and returns the raw `Date` header,
  /// or null when the response carried none. It must throw a
  /// `TimeSourceException` when the request itself fails.
  HttpDateTimeSource({
    required this.id,
    required this.uri,
    required MonotonicTicks ticks,
    required Future<String?> Function(Uri uri) probe,
    Clock deviceClock = const Clock(),
  }) : _ticks = ticks,
       _probe = probe,
       _deviceClock = deviceClock;

  @override
  final String id;

  /// The endpoint to probe. Any cheap HTTPS endpoint the app already talks to
  /// will do; a `HEAD` against one costs a round trip and no body.
  final Uri uri;

  final MonotonicTicks _ticks;
  final Future<String?> Function(Uri uri) _probe;
  final Clock _deviceClock;

  /// One second — the resolution of an HTTP-date.
  static const Duration resolution = Duration(seconds: 1);

  @override
  TimeSourceTrust get trust => TimeSourceTrust.transportAuthenticated;

  @override
  Future<TimeSample> sample() async {
    final Duration sentAt = _ticks.elapsed;
    final String? header = await _probe(uri);
    final Duration receivedAt = _ticks.elapsed;

    if (header == null) {
      throw HttpDateException(id, 'response carried no Date header');
    }
    final DateTime? parsed = parseHttpDate(header);
    if (parsed == null) {
      throw HttpDateException(
        id,
        'Date header did not match any HTTP-date form '
        '(length ${header.length})',
      );
    }

    final Duration halfTrip = (receivedAt - sentAt) ~/ 2;
    const Duration halfStep = Duration(milliseconds: 500);

    return TimeSample(
      remoteUtc: parsed.add(halfTrip).add(halfStep),
      ticksAtReceipt: receivedAt,
      deviceWallAtReceipt: _deviceClock.now(),
      uncertainty: halfTrip + halfStep,
      trust: trust,
      sourceId: id,
    );
  }

  /// Parses the three date forms RFC 9110 requires a recipient to accept,
  /// returning null on anything else.
  ///
  /// Hand-written rather than delegating to `dart:io`'s `HttpDate.parse`,
  /// which would pull `dart:io` into the core library and make the package
  /// unusable anywhere that is unavailable. It also lets a malformed header
  /// be a null instead of a `FormatException` to catch.
  ///
  /// Two-digit years in the obsolete RFC 850 form are read as 1970-2069.
  /// RFC 9110's own rule — anything more than fifty years ahead is in the
  /// past — needs a trusted current year, which is precisely what this source
  /// is being asked to establish.
  static DateTime? parseHttpDate(String value) {
    final String input = value.trim();
    final DateTime? fixdate = _parseImfFixdate(input);
    if (fixdate != null) {
      return fixdate;
    }
    final DateTime? rfc850 = _parseRfc850(input);
    if (rfc850 != null) {
      return rfc850;
    }
    return _parseAsctime(input);
  }

  static const List<String> _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static final RegExp _imfFixdate = RegExp(
    r'^[A-Za-z]{3}, (\d{2}) ([A-Za-z]{3}) (\d{4}) '
    r'(\d{2}):(\d{2}):(\d{2}) GMT$',
  );

  static final RegExp _rfc850 = RegExp(
    r'^[A-Za-z]{6,9}, (\d{2})-([A-Za-z]{3})-(\d{2}) '
    r'(\d{2}):(\d{2}):(\d{2}) GMT$',
  );

  static final RegExp _asctime = RegExp(
    r'^[A-Za-z]{3} ([A-Za-z]{3}) ([ \d]\d) '
    r'(\d{2}):(\d{2}):(\d{2}) (\d{4})$',
  );

  /// A regex group as an integer, or -1 when it is absent or not a number.
  ///
  /// -1 rather than null so the range checks in [_isPlausibleDate] and
  /// [_isPlausibleTime] are the single place a malformed field is rejected —
  /// every out-of-range value, however it got that way, fails there.
  static int _int(String? raw) => int.tryParse((raw ?? '').trim()) ?? -1;

  static DateTime? _parseImfFixdate(String input) {
    final RegExpMatch? match = _imfFixdate.firstMatch(input);
    if (match == null) {
      return null;
    }
    return _build(
      year: _int(match.group(3)),
      month: match.group(2) ?? '',
      day: _int(match.group(1)),
      hour: _int(match.group(4)),
      minute: _int(match.group(5)),
      second: _int(match.group(6)),
    );
  }

  static DateTime? _parseRfc850(String input) {
    final RegExpMatch? match = _rfc850.firstMatch(input);
    if (match == null) {
      return null;
    }
    final int shortYear = _int(match.group(3));
    if (shortYear < 0) {
      return null;
    }
    return _build(
      year: shortYear >= 70 ? 1900 + shortYear : 2000 + shortYear,
      month: match.group(2) ?? '',
      day: _int(match.group(1)),
      hour: _int(match.group(4)),
      minute: _int(match.group(5)),
      second: _int(match.group(6)),
    );
  }

  static DateTime? _parseAsctime(String input) {
    final RegExpMatch? match = _asctime.firstMatch(input);
    if (match == null) {
      return null;
    }
    return _build(
      year: _int(match.group(6)),
      month: match.group(1) ?? '',
      day: _int(match.group(2)),
      hour: _int(match.group(3)),
      minute: _int(match.group(4)),
      second: _int(match.group(5)),
    );
  }

  static bool _isPlausibleDate(int year, int monthIndex, int day) {
    if (year < 1 || year > 9999) {
      return false;
    }
    if (monthIndex < 0) {
      return false;
    }
    // Rejected against the actual month, not a flat 1..31: `DateTime.utc`
    // silently rolls Feb 31 into Mar 3, so a header naming a day that does
    // not exist would otherwise parse as a date three days later.
    final DateTime firstOfMonth = DateTime.utc(year, monthIndex + 1);
    final int daysInMonth = DateTime.utc(
      year,
      monthIndex + 2,
    ).difference(firstOfMonth).inDays;
    return day >= 1 && day <= daysInMonth;
  }

  static bool _isPlausibleTime(int hour, int minute, int second) {
    if (hour < 0 || hour > 23) {
      return false;
    }
    if (minute < 0 || minute > 59) {
      return false;
    }
    // 60 is a leap second. `DateTime` has no room for one and rolls it into
    // the next minute, which is the same instant to within the one second
    // this source can resolve anyway.
    return second >= 0 && second <= 60;
  }

  static DateTime? _build({
    required int year,
    required String month,
    required int day,
    required int hour,
    required int minute,
    required int second,
  }) {
    final int monthIndex = _months.indexOf(month);
    if (!_isPlausibleDate(year, monthIndex, day)) {
      return null;
    }
    if (!_isPlausibleTime(hour, minute, second)) {
      return null;
    }
    return DateTime.utc(year, monthIndex + 1, day, hour, minute, second);
  }
}
