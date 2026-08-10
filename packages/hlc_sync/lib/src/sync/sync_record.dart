import 'dart:convert';
import 'dart:typed_data';

import '../errors.dart';
import '../hlc/hlc.dart';
import '../hlc/hlc_dto.dart';
import 'mirror_store.dart';
import 'sync_entity_presence.dart';

/// One record as it travels to and from the cloud.
///
/// Values are a plain `field → value` map rather than a typed model. The sync
/// layer never interprets them — it decides *which* side's value wins per
/// field and hands the result back to the owning DAO. Keeping them opaque is
/// what lets one engine serve four record types without knowing anything
/// about any particular record type.
class SyncRecord {
  const SyncRecord({
    required this.id,
    required this.recordType,
    required this.values,
    this.createdHlc,
    this.deletedHlc,
    this.fieldHlcs = const <String, Hlc>{},
  });

  final String id;
  final String recordType;

  /// Field values. Only JSON-representable types.
  final Map<String, Object?> values;

  final Hlc? createdHlc;
  final Hlc? deletedHlc;
  final Map<String, Hlc> fieldHlcs;

  bool get isDeleted => deletedHlc != null;

  SyncSideState get sideState => SyncSideState(
    presence: isDeleted
        ? SyncEntityPresence.deleted
        : SyncEntityPresence.present,
    createdHlc: createdHlc,
    deletedHlc: deletedHlc,
    fieldHlcs: fieldHlcs,
  );

  Uint8List encode() {
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'id': id,
          'recordType': recordType,
          'createdHlc': _encodeHlc(createdHlc),
          'deletedHlc': _encodeHlc(deletedHlc),
          'fieldHlcs': <String, Object?>{
            for (final MapEntry<String, Hlc> e in fieldHlcs.entries)
              e.key: _encodeHlc(e.value),
          },
          'values': values,
        }),
      ),
    );
  }

  /// Parses bytes that came from the cloud.
  ///
  /// Every HLC goes through [HlcDto], which validates rather than trusting.
  /// These bytes are influenced by anything able to write to the user's Drive,
  /// and an HLC far in the future would win every conflict forever.
  ///
  /// Returns null on anything malformed instead of throwing. One unreadable
  /// file must not abort a sync round — the other records are still fine, and
  /// a round that dies on the first bad byte would never recover on its own.
  static SyncRecord? decode(Uint8List bytes) {
    try {
      final Object? parsed = jsonDecode(utf8.decode(bytes));
      if (parsed is! Map<String, dynamic>) {
        return null;
      }

      final Object? id = parsed['id'];
      final Object? recordType = parsed['recordType'];
      if (id is! String || recordType is! String || id.isEmpty) {
        return null;
      }

      final Object? rawValues = parsed['values'];
      final Object? rawFieldHlcs = parsed['fieldHlcs'];

      // Size bounds before the values are trusted. Without them a single
      // crafted document decides how much memory the reading device
      // allocates, and this runs on every record of every round — the bound
      // is what keeps one bad document from being a denial of service on the
      // whole data set.
      //
      // Generous rather than tight: ceilings on the absurd, not validation of
      // any particular schema. A record legitimately this wide is not a record
      // this format was meant to carry.
      if (rawValues is Map<String, dynamic> &&
          rawValues.length > _maxFieldCount) {
        return null;
      }
      if (rawFieldHlcs is Map<String, dynamic> &&
          rawFieldHlcs.length > _maxFieldCount) {
        return null;
      }
      if (rawValues is Map<String, dynamic> && _exceedsValueBounds(rawValues)) {
        return null;
      }

      return SyncRecord(
        id: id,
        recordType: recordType,
        values: rawValues is Map<String, dynamic>
            ? Map<String, Object?>.from(rawValues)
            : <String, Object?>{},
        createdHlc: _decodeHlc(parsed['createdHlc']),
        deletedHlc: _decodeHlc(parsed['deletedHlc']),
        fieldHlcs: rawFieldHlcs is Map<String, dynamic>
            ? <String, Hlc>{
                for (final MapEntry<String, dynamic> e in rawFieldHlcs.entries)
                  if (_decodeHlc(e.value) case final Hlc hlc) e.key: hlc,
              }
            : <String, Hlc>{},
      );
    } on FormatException {
      // A malformed document is dropped, not fatal. Narrow on purpose: a bare
      // catch also swallows programming errors, and would have reported a bug
      // in this decoder as "this record does not exist".
      return null;
    }
  }

  /// No sane record type comes close to this many fields.
  static const int _maxFieldCount = 200;

  /// One free-text body is the largest legitimate value, and it is nowhere
  /// near this.
  static const int _maxStringLength = 1 << 20; // 1 MiB

  static const int _maxListLength = 10000;

  /// Rejects a values map carrying something absurd, one level deep — which is
  /// as deep as these records nest.
  static bool _exceedsValueBounds(Map<String, dynamic> values) {
    for (final Object? value in values.values) {
      if (value is String && value.length > _maxStringLength) {
        return true;
      }
      if (value is List<Object?> && value.length > _maxListLength) {
        return true;
      }
      if (value is Map<Object?, Object?> && value.length > _maxFieldCount) {
        return true;
      }
    }
    return false;
  }

  static Map<String, Object?>? _encodeHlc(Hlc? hlc) {
    if (hlc == null) {
      return null;
    }
    return HlcDto.fromDomain(hlc).toJson();
  }

  /// Reads one embedded HLC, or null if this file has no believable one.
  ///
  /// The field types are checked here rather than left to [HlcDto.fromJson]'s
  /// casts. A cast failure raises `TypeError`, which is an [Error] — so it
  /// would neither be caught below nor *should* be, since catching [Error]
  /// hides real bugs. At a trust boundary a wrong type is not a bug, it is the
  /// input being wrong, and it has to be answerable without one.
  ///
  /// Every route out returns null rather than throwing, because the caller's
  /// contract is to skip an unbelievable file, not to die on it. A throw
  /// escaping here takes down the whole round — and since the base never
  /// advances, every later round replays the same file and dies identically.
  static Hlc? _decodeHlc(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return null;
    }
    final Object? physicalMs = raw['physicalMs'];
    final Object? logical = raw['logical'];
    final Object? nodeId = raw['nodeId'];
    if (physicalMs is! int || logical is! int || nodeId is! String) {
      return null;
    }
    try {
      return HlcDto(
        physicalMs: physicalMs,
        logical: logical,
        nodeId: nodeId,
      ).toDomain();
    } on HlcCorruptedException {
      // Parsed, but claims a time or counter no real clock produces. Treated
      // as absent, which loses every comparison — safer than accepting a
      // forged ordering, which would win every conflict forever.
      return null;
    }
  }
}
