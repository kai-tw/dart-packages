import 'dart:convert';
import 'dart:typed_data';

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
    } catch (_) {
      return null;
    }
  }

  static Map<String, Object?>? _encodeHlc(Hlc? hlc) {
    if (hlc == null) {
      return null;
    }
    return HlcDto.fromDomain(hlc).toJson();
  }

  static Hlc? _decodeHlc(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return null;
    }
    try {
      return HlcDto.fromJson(raw).toDomain();
    } catch (_) {
      // Corrupt or implausible. Treated as absent, which loses every
      // comparison — safer than accepting a forged ordering.
      return null;
    }
  }
}
