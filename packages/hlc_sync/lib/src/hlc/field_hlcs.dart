import 'dart:convert';

import 'hlc.dart';

/// Encodes and decodes the per-field HLC stamp map.
///
/// Stored as `{"<field>": "<encoded hlc>"}` — a shape chosen so the whole map
/// fits one string column or one JSON value, with no schema change when a
/// record type gains a field.
///
/// A missing key means the field has never been stamped, which compares as
/// older than anything — so a record written before sync existed loses to any
/// later edit rather than winning by accident.
abstract final class FieldHlcs {
  /// Decodes the stored form. Returns empty on null or on anything unparseable.
  ///
  /// Tolerant on purpose: this value is rewritten on every sync, so one
  /// malformed entry should cost the record its stamps, not crash the list the
  /// record appears in.
  static Map<String, Hlc> decode(String? raw) {
    if (raw == null || raw.isEmpty) {
      return <String, Hlc>{};
    }
    try {
      final Object? parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic>) {
        return <String, Hlc>{};
      }
      final Map<String, Hlc> result = <String, Hlc>{};
      for (final MapEntry<String, dynamic> entry in parsed.entries) {
        final Object? value = entry.value;
        if (value is String) {
          try {
            result[entry.key] = Hlc.decode(value);
          } catch (_) {
            // Skip this field; the rest of the record is still usable.
          }
        }
      }
      return result;
    } catch (_) {
      return <String, Hlc>{};
    }
  }

  static String encode(Map<String, Hlc> stamps) {
    return jsonEncode(<String, String>{
      for (final MapEntry<String, Hlc> e in stamps.entries)
        e.key: e.value.encode(),
    });
  }

  /// Stamps [fields] with [stamp], keeping any existing stamps for fields not
  /// named. Used on write: only what actually changed gets a new clock, so an
  /// untouched field keeps the stamp that says when it last really changed.
  static String stamp(String? raw, Iterable<String> fields, Hlc stamp) {
    final Map<String, Hlc> current = decode(raw);
    for (final String field in fields) {
      current[field] = stamp;
    }
    return encode(current);
  }
}
