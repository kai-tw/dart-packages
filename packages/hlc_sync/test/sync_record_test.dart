import 'dart:convert';
import 'dart:typed_data';

import 'package:hlc_sync/hlc_sync.dart';
import 'package:test/test.dart';

/// What [SyncRecord.decode] does with bytes it should not believe.
///
/// The store this package reads from is passive and shared. Another device may
/// run an older build of the app, and anyone who reaches the account behind the
/// store can write to it directly. So these bytes are input, not data.
///
/// Two guarantees, and they fail differently: an unbelievable record must not
/// be *believed*, and it must not take the round down. Only the first is
/// obvious, and only the second is silent when it breaks — a throw escaping
/// `decode` aborts the round, the base never advances, and every later round
/// replays the same file and dies the same way. Sync would be dead
/// permanently, on a file the user cannot see or delete.
void main() {
  Uint8List bytes(Map<String, Object?> json) {
    return Uint8List.fromList(utf8.encode(jsonEncode(json)));
  }

  Map<String, Object?> record(Object? hlc) {
    return <String, Object?>{
      'id': 'r1',
      'recordType': 'thing',
      'values': <String, Object?>{'name': 'x'},
      'fieldHlcs': <String, Object?>{'name': hlc},
      'createdHlc': hlc,
    };
  }

  group('an HLC no real clock could have produced', () {
    test('a physical time far in the future decodes as absent', () {
      final SyncRecord? decoded = SyncRecord.decode(
        bytes(
          record(<String, Object?>{
            'physicalMs': DateTime.now()
                .add(const Duration(days: 3650))
                .millisecondsSinceEpoch,
            'logical': 0,
            'nodeId': 'attacker',
          }),
        ),
      );

      // Absent, not merely "not in the future": absent loses every comparison,
      // which is the whole point. Accepting the stamp would let this record
      // beat every real edit on every device, forever.
      expect(decoded, isNotNull);
      expect(decoded!.createdHlc, isNull);
      expect(decoded.fieldHlcs, isEmpty);
    });

    test('a logical counter past the cap decodes as absent', () {
      final SyncRecord? decoded = SyncRecord.decode(
        bytes(
          record(<String, Object?>{
            'physicalMs': DateTime.now().millisecondsSinceEpoch,
            'logical': (1 << 20) + 1,
            'nodeId': 'attacker',
          }),
        ),
      );

      expect(decoded, isNotNull);
      expect(decoded!.createdHlc, isNull);
      expect(decoded.fieldHlcs, isEmpty);
    });

    test('a stamp of the wrong type decodes as absent', () {
      // HlcDto.fromJson casts, so a string where an int belongs raises
      // TypeError — an Error, not an Exception. A third escape route, and the
      // one an `on Exception` clause cannot cover even in principle, which is
      // why the field types are checked before the DTO is built rather than
      // after it throws.
      final SyncRecord? decoded = SyncRecord.decode(
        bytes(
          record(<String, Object?>{
            'physicalMs': 'not-a-number',
            'logical': 0,
            'nodeId': 'attacker',
          }),
        ),
      );

      expect(decoded, isNotNull);
      expect(decoded!.createdHlc, isNull);
      expect(decoded.fieldHlcs, isEmpty);
    });

    test('a stamp that is not a map at all decodes as absent', () {
      final SyncRecord? decoded = SyncRecord.decode(bytes(record('nonsense')));

      expect(decoded, isNotNull);
      expect(decoded!.createdHlc, isNull);
    });
  });

  group('a document too large to trust', () {
    test('more fields than any record has is dropped', () {
      final Map<String, Object?> wide = <String, Object?>{
        for (int i = 0; i < 500; i++) 'f$i': 'v',
      };

      expect(
        SyncRecord.decode(
          bytes(<String, Object?>{
            'id': 'r1',
            'recordType': 'thing',
            'values': wide,
            'fieldHlcs': <String, Object?>{},
          }),
        ),
        isNull,
      );
    });

    test('a single absurd string value is dropped', () {
      expect(
        SyncRecord.decode(
          bytes(<String, Object?>{
            'id': 'r1',
            'recordType': 'thing',
            'values': <String, Object?>{'name': 'x' * ((1 << 20) + 1)},
            'fieldHlcs': <String, Object?>{},
          }),
        ),
        isNull,
      );
    });

    test('a list longer than any record carries is dropped', () {
      expect(
        SyncRecord.decode(
          bytes(<String, Object?>{
            'id': 'r1',
            'recordType': 'thing',
            'values': <String, Object?>{
              'tags': List<String>.filled(10001, 't'),
            },
            'fieldHlcs': <String, Object?>{},
          }),
        ),
        isNull,
      );
    });

    test('a record of ordinary size still decodes', () {
      // The bounds are ceilings on the absurd. If a normal record trips one,
      // the bound is wrong, and this is what would say so.
      final SyncRecord? decoded = SyncRecord.decode(
        bytes(<String, Object?>{
          'id': 'r1',
          'recordType': 'thing',
          'values': <String, Object?>{
            'name': 'x' * 2000,
            'tags': List<String>.filled(50, 't'),
          },
          'fieldHlcs': <String, Object?>{},
        }),
      );

      expect(decoded, isNotNull);
      expect(decoded!.values['name'], hasLength(2000));
    });
  });

  group('malformed bytes', () {
    test('are dropped rather than thrown', () {
      expect(SyncRecord.decode(Uint8List.fromList(utf8.encode('{'))), isNull);
      expect(SyncRecord.decode(Uint8List.fromList(<int>[0xff, 0xfe])), isNull);
      expect(
        SyncRecord.decode(Uint8List.fromList(utf8.encode('[1,2,3]'))),
        isNull,
      );
    });

    test('a record without a usable id is dropped', () {
      expect(
        SyncRecord.decode(
          bytes(<String, Object?>{
            'id': '',
            'recordType': 'thing',
            'values': <String, Object?>{},
            'fieldHlcs': <String, Object?>{},
          }),
        ),
        isNull,
      );
    });
  });
}
