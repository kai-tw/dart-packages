import 'package:hlc_sync/hlc_sync.dart';
import 'package:test/test.dart';

void main() {
  const Hlc base = Hlc(physicalMs: 100, logical: 0, nodeId: 'node-a');
  const Hlc newerA = Hlc(physicalMs: 200, logical: 0, nodeId: 'node-a');
  const Hlc newerB = Hlc(physicalMs: 200, logical: 0, nodeId: 'node-b');

  group('classifyField', () {
    test('nothing changed', () {
      expect(
        classifyField(local: base, cloud: base, base: base),
        FieldDivergence.unchanged,
      );
    });

    test('only local moved — fast-forward, no dialog', () {
      expect(
        classifyField(local: newerA, cloud: base, base: base),
        FieldDivergence.localOnly,
      );
    });

    test('only cloud moved — fast-forward, no dialog', () {
      expect(
        classifyField(local: base, cloud: newerB, base: base),
        FieldDivergence.cloudOnly,
      );
    });

    test('both moved — the only case worth asking about', () {
      expect(
        classifyField(local: newerA, cloud: newerB, base: base),
        FieldDivergence.concurrent,
      );
    });

    test('both moved to the same clock is one write seen twice', () {
      // One side already received the other's write. Reporting this as a
      // conflict would ask the user to choose between a value and itself.
      expect(
        classifyField(local: newerA, cloud: newerA, base: base),
        FieldDivergence.unchanged,
      );
    });
  });

  group('no base', () {
    test('a side with a stamp counts as changed', () {
      expect(
        classifyField(local: newerA, cloud: null, base: null),
        FieldDivergence.localOnly,
      );
    });

    test('both stamped with no common ancestor is concurrent', () {
      // First sync between two devices that each already had data. There is
      // no ancestor to have diverged from, so neither can be fast-forwarded.
      expect(
        classifyField(local: newerA, cloud: newerB, base: null),
        FieldDivergence.concurrent,
      );
    });

    test('neither side stamped is unchanged', () {
      expect(
        classifyField(local: null, cloud: null, base: null),
        FieldDivergence.unchanged,
      );
    });
  });

  group('isConcurrent', () {
    test('two stamps from one device are never concurrent', () {
      // A device's own clock only moves forward, so its writes are ordered by
      // construction.
      expect(isConcurrent(base, newerA), isFalse);
    });

    test('different devices with different stamps are concurrent', () {
      expect(isConcurrent(newerA, newerB), isTrue);
    });

    test('identical stamps are not concurrent', () {
      expect(isConcurrent(newerA, newerA), isFalse);
    });

    test('errs toward reporting a conflict rather than hiding one', () {
      // An HLC cannot tell "B saw A's write, then stamped" apart from "B
      // stamped unaware of A" without vector clocks. A false positive costs
      // one dialog; a false negative silently discards an edit. This asserts
      // the direction of that trade-off, so a future change to make the
      // predicate cleverer has to confront it.
      const Hlc earlier = Hlc(physicalMs: 100, logical: 0, nodeId: 'node-a');
      const Hlc laterOtherDevice = Hlc(
        physicalMs: 999,
        logical: 0,
        nodeId: 'node-b',
      );
      expect(isConcurrent(earlier, laterOtherDevice), isTrue);
    });
  });
}
