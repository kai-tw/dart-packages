import 'package:hlc_sync/hlc_sync.dart';
import 'package:test/test.dart';

void main() {
  const Hlc a = Hlc(physicalMs: 100, logical: 0, nodeId: 'node-a');
  const Hlc b = Hlc(physicalMs: 200, logical: 0, nodeId: 'node-b');

  group('FieldHlcs', () {
    test('round-trips', () {
      final String encoded = FieldHlcs.encode(<String, Hlc>{'name': a});
      expect(FieldHlcs.decode(encoded), <String, Hlc>{'name': a});
    });

    test('treats null and empty as no stamps', () {
      expect(FieldHlcs.decode(null), isEmpty);
      expect(FieldHlcs.decode(''), isEmpty);
    });

    test('survives a malformed column rather than throwing', () {
      // This column is rewritten every sync. One bad value should cost the
      // record its stamps, not crash the list it appears in.
      expect(FieldHlcs.decode('not json'), isEmpty);
      expect(FieldHlcs.decode('[1,2,3]'), isEmpty);
    });

    test('drops only the unparseable field, keeping the rest', () {
      const String raw = '{"name":"100-0-node-a","priority":"garbage"}';
      final Map<String, Hlc> stamps = FieldHlcs.decode(raw);
      expect(stamps.keys, <String>['name']);
      expect(stamps['name'], a);
    });

    test('stamping leaves untouched fields on their old clock', () {
      // The whole point of per-field stamps: a field that did not change
      // keeps the clock saying when it last really changed, so an edit to a
      // different field elsewhere does not look newer than it is.
      final String first = FieldHlcs.stamp(null, <String>['name'], a);
      final String second = FieldHlcs.stamp(first, <String>['priority'], b);

      final Map<String, Hlc> stamps = FieldHlcs.decode(second);
      expect(stamps['name'], a);
      expect(stamps['priority'], b);
    });

    test('a missing stamp loses to any real one', () {
      // Records written before sync existed have no stamps. They must lose,
      // not win by accident.
      final Map<String, Hlc> stamps = FieldHlcs.decode(null);
      expect(stamps['name'], isNull);
    });
  });
}
