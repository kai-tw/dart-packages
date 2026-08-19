import 'package:clock/clock.dart';
import 'package:hybrid_logical_clock/hybrid_logical_clock.dart';
import 'package:test/test.dart';

/// `HlcClockImpl` — tick monotonicity and the four-case `receive` dispatch.
///
/// Ported from the first consuming app, which had built a decision table over
/// `receive`'s four rules while this package carried only three smoke tests.
/// The rules are the ones in Turukin's algorithm, and getting any of them
/// wrong corrupts ordering silently rather than loudly — which is why the
/// coverage belongs here, where it protects every consumer, rather than in
/// one app's own suite.
void main() {
  const String testNodeId = 'test-device-uuid';

  /// A clock pinned to a fixed wall time, so tick / receive outcomes are
  /// deterministic. `package:fake_async` is deliberately not used — it adds
  /// Future-driver semantics this layer has no use for.
  HlcClockImpl buildClockAt(int wallMs, {String nodeId = testNodeId}) {
    return HlcClockImpl(
      nodeId: nodeId,
      clock: Clock.fixed(
        DateTime.fromMillisecondsSinceEpoch(wallMs, isUtc: true),
      ),
    );
  }

  group('HlcClockImpl.tick — monotonic advance + logical reset', () {
    test('first tick emits physicalMs=wallNow, logical=0', () {
      final HlcClockImpl clock = buildClockAt(1000);
      final Hlc t = clock.tick();

      expect(t.physicalMs, 1000);
      expect(t.logical, 0);
      expect(t.nodeId, testNodeId);
    });

    test('a second tick in the same millisecond bumps logical', () {
      final HlcClockImpl clock = buildClockAt(1000);
      final Hlc t1 = clock.tick();
      final Hlc t2 = clock.tick();

      expect(t2.physicalMs, 1000);
      expect(t2.logical, t1.logical + 1);
      expect(t2.compareTo(t1), greaterThan(0));
    });

    test('a clock started at a later wall time resets logical to 0', () {
      // The impl exposes no way to advance its own fixed clock mid-stream, so
      // the physical-advance arm is modelled with a second clock cold-started
      // later. What is pinned is the algorithm's cold-init behaviour.
      buildClockAt(1000).tick();
      final Hlc t = buildClockAt(2000).tick();

      expect(t.physicalMs, 2000);
      expect(t.logical, 0);
    });

    test('a same-millisecond burst increments logical 0..9', () {
      final HlcClockImpl clock = buildClockAt(1000);
      final List<int> logicals = <int>[
        for (int i = 0; i < 10; i++) clock.tick().logical,
      ];

      expect(logicals, <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    });

    test('every tick is strictly greater than the one before it', () {
      // Mutation pin on the whole invariant: any arm that fails to advance
      // shows up here even if the per-arm cases above still pass.
      final HlcClockImpl clock = buildClockAt(1000);
      Hlc prev = clock.tick();
      for (int i = 0; i < 20; i++) {
        final Hlc next = clock.tick();
        expect(next.compareTo(prev), greaterThan(0));
        prev = next;
      }
    });
  });

  group('HlcClockImpl.receive — four-case dispatch on (wall, last, remote)', () {
    test(
      'rule W — wall ahead of both last and remote wins, logical resets',
      () {
        final HlcClockImpl clock = buildClockAt(3000);
        const Hlc remote = Hlc(physicalMs: 1500, logical: 99, nodeId: 'other');

        final Hlc merged = clock.receive(remote);

        expect(merged.physicalMs, 3000);
        expect(merged.logical, 0);
        expect(merged.nodeId, testNodeId);
      },
    );

    test('rule L — last at wall and ahead of remote wins, logical bumps', () {
      // Rule L proper needs the wall to regress below `last`, which the API
      // gives no way to stage; the `last == wall > remote` path exercises the
      // same arm.
      final HlcClockImpl clock = buildClockAt(5000);
      clock.tick(); // last = (5000, 0)
      const Hlc remote = Hlc(physicalMs: 1000, logical: 99, nodeId: 'other');

      final Hlc merged = clock.receive(remote);

      expect(merged.physicalMs, 5000);
      expect(merged.logical, 1);
      expect(merged.nodeId, testNodeId);
    });

    test('rule R — remote ahead of both wall and last wins, logical bumps', () {
      final HlcClockImpl clock = buildClockAt(1000); // no prior tick
      const Hlc remote = Hlc(physicalMs: 9000, logical: 5, nodeId: 'other');

      final Hlc merged = clock.receive(remote);

      expect(merged.physicalMs, 9000);
      expect(merged.logical, 6);
      expect(merged.nodeId, testNodeId);
    });

    test('rule T — last and remote tie above wall, logical takes max + 1', () {
      final HlcClockImpl clock = buildClockAt(1000);
      clock.tick();
      clock.tick(); // last = (1000, 1)
      const Hlc remote = Hlc(physicalMs: 1000, logical: 3, nodeId: 'other');

      final Hlc merged = clock.receive(remote);

      expect(merged.physicalMs, 1000);
      expect(merged.logical, 4); // max(1, 3) + 1
      expect(merged.nodeId, testNodeId);
    });

    test('two remotes in one round: physicalMs is order-independent', () {
      // The contract that actually holds. `logical` is NOT order-independent
      // when both remotes tie on physicalMs — each receive bumps once, so the
      // count depends on arrival order. Asserting logical equality here would
      // pin a guarantee the algorithm does not make; what it does guarantee is
      // the physical component converging and the result outranking both.
      const Hlc a = Hlc(physicalMs: 5000, logical: 3, nodeId: 'remote-a');
      const Hlc b = Hlc(physicalMs: 5000, logical: 7, nodeId: 'remote-b');

      final HlcClockImpl c1 = buildClockAt(1000);
      c1.receive(a);
      final Hlc afterAb = c1.receive(b);

      final HlcClockImpl c2 = buildClockAt(1000);
      c2.receive(b);
      final Hlc afterBa = c2.receive(a);

      expect(afterAb.physicalMs, 5000);
      expect(afterBa.physicalMs, afterAb.physicalMs);
      for (final Hlc result in <Hlc>[afterAb, afterBa]) {
        expect(result.compareTo(a), greaterThan(0));
        expect(result.compareTo(b), greaterThan(0));
      }
    });

    test('a received remote never pollutes the stamped nodeId', () {
      // Mutation pin: the emitted nodeId is always self, never the remote's.
      // Getting this wrong would make a device attribute its own writes to a
      // peer, which breaks the compareTo tiebreak for everyone.
      final HlcClockImpl clock = buildClockAt(1000);
      const Hlc remote = Hlc(
        physicalMs: 5000,
        logical: 0,
        nodeId: 'foreign-node-id',
      );

      expect(clock.receive(remote).nodeId, testNodeId);
      expect(clock.tick().nodeId, testNodeId);
    });

    test('the next tick after a receive outranks what was received', () {
      // The post-receive invariant the whole algorithm exists to provide.
      final HlcClockImpl clock = buildClockAt(1000);
      const Hlc remote = Hlc(physicalMs: 9000, logical: 5, nodeId: 'remote');

      final Hlc merged = clock.receive(remote);
      final Hlc next = clock.tick();

      expect(next.compareTo(remote), greaterThan(0));
      expect(next.compareTo(merged), greaterThan(0));
    });
  });
}
