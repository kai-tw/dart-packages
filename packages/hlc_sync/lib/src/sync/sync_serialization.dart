import '../hlc/hlc.dart';

/// Shared value conversions for the sync wire format.
///
/// Everything here is deliberately lenient. These values arrive as JSON from
/// cloud storage, so a wrong type is possible and must degrade to "absent"
/// rather than throw — one malformed field should cost that field, not abort
/// the round for every other record.

/// UTC ISO-8601, or null.
///
/// Always UTC on the wire. Two devices in different timezones writing local
/// times would produce values that compare wrongly and display wrongly, and
/// the bug would only appear when someone travels.
String? encodeDateTime(DateTime? value) => value?.toUtc().toIso8601String();

DateTime? decodeDateTime(Object? raw) {
  if (raw is! String || raw.isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw)?.toUtc();
}

/// A list of record ids, filtering anything that is not a non-empty string.
List<String> decodeIdList(Object? raw) {
  if (raw is! List) {
    return <String>[];
  }
  return raw.whereType<String>().where((String s) => s.isNotEmpty).toList();
}

Hlc? decodeHlcOrNull(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  try {
    return Hlc.decode(raw);
  } catch (_) {
    // Absent loses every comparison, which is the safe direction: a garbage
    // stamp accepted as real could mark a genuine edit as unchanged.
    return null;
  }
}
