import 'package:clock/clock.dart';
import 'hlc.dart';

/// Produces causally-ordered [Hlc] timestamps for the local device.
///
/// `tick` and `receive` are **synchronous** on top of a single-isolate
/// Dart runtime — no `await` inside either method, so concurrent
/// callers within one frame interleave deterministically without
/// needing an async lock. The `_lastEmitted` field is mutated atomically
/// inside a sync method body; Dart's event loop guarantees the body
/// runs to completion before any other code resumes.
abstract class HlcClock {
  /// Emit a new [Hlc] strictly greater than every previously emitted
  /// or received HLC and the current wall clock — per Turukin §"Tick".
  Hlc tick();

  /// Update internal state after observing a remote HLC (e.g. on
  /// metadata read from cloud / mirror). Returns the merged HLC for
  /// the next tick — per Turukin §"Implementation".
  ///
  /// Single-remote merge: when multiple remotes are observed in one
  /// sync round, call `receive` once per remote. Each invocation is
  /// idempotent under all-max semantics, so call order does not
  /// affect the final `_lastEmitted`.
  Hlc receive(Hlc remote);
}

/// Production [HlcClock] implementation.
///
/// Holds a device-stable `nodeId` (resolved once at construction from
/// `DeviceIdentityPreferenceRepository`, then cached) and a mutable
/// `_lastEmitted` that monotonically advances under tick / receive.
/// The `Clock` collaborator from `package:clock` is the wall-clock seam
/// `package:clock`'s zoning APIs use, so tests can `withClock` to
/// force deterministic wall-clock values without monkey-patching.
class HlcClockImpl implements HlcClock {
  HlcClockImpl({required String nodeId, Clock? clock})
    : _nodeId = nodeId,
      _injectedClock = clock;

  final String _nodeId;

  /// An explicitly supplied clock, or null to follow the ambient one.
  ///
  /// Deviation from the source this was ported from, which defaulted to
  /// `const Clock()`. That constructor reads `DateTime.now` directly and does
  /// **not** consult `package:clock`'s zoned getter, so `withClock(...)` in a
  /// test had no effect on it despite the doc claiming otherwise. Falling back
  /// to the ambient `clock` makes the seam real.
  final Clock? _injectedClock;

  Clock get _clock => _injectedClock ?? clock;

  Hlc? _lastEmitted;

  @override
  Hlc tick() {
    // Compute wall-now and the higher of (wall, lastPhysical) — per
    // Turukin §"Tick": newPhysical = max(wallNow, last.physical).
    final int wallNow = _clock.now().millisecondsSinceEpoch;
    final Hlc? last = _lastEmitted;
    final int lastPhysical = last?.physicalMs ?? 0;
    final int newPhysical = wallNow > lastPhysical ? wallNow : lastPhysical;

    // Logical increment: if physical did not advance over last, bump
    // logical; otherwise reset logical to 0.
    final int newLogical = (last != null && newPhysical == last.physicalMs)
        ? last.logical + 1
        : 0;

    // Stamp + persist as new lastEmitted.
    final Hlc next = Hlc(
      physicalMs: newPhysical,
      logical: newLogical,
      nodeId: _nodeId,
    );
    _lastEmitted = next;
    return next;
  }

  @override
  Hlc receive(Hlc remote) {
    final int wallNow = _clock.now().millisecondsSinceEpoch;
    final Hlc? last = _lastEmitted;
    final int lastPhysical = last?.physicalMs ?? 0;
    final int lastLogical = last?.logical ?? 0;
    final int newPhysical = _mergePhysical(wallNow, lastPhysical, remote);
    final int newLogical = _mergeLogical(
      lastPhysical,
      lastLogical,
      remote,
      newPhysical,
    );

    // Stamp + persist.
    final Hlc next = Hlc(
      physicalMs: newPhysical,
      logical: newLogical,
      nodeId: _nodeId,
    );
    _lastEmitted = next;
    return next;
  }

  /// The all-max physical across (wallNow, last, remote) — per Turukin
  /// §"Implementation".
  int _mergePhysical(int wallNow, int lastPhysical, Hlc remote) {
    int newPhysical = wallNow;
    if (lastPhysical > newPhysical) {
      newPhysical = lastPhysical;
    }
    if (remote.physicalMs > newPhysical) {
      newPhysical = remote.physicalMs;
    }
    return newPhysical;
  }

  /// The logical counter for whichever of (last, remote) shares the
  /// winning physical — bumps the winner's logical by 1; if last and
  /// remote tie, bumps max(last.logical, remote.logical) by 1; if wall
  /// won outright, resets to 0.
  int _mergeLogical(
    int lastPhysical,
    int lastLogical,
    Hlc remote,
    int newPhysical,
  ) {
    if (newPhysical == lastPhysical && newPhysical == remote.physicalMs) {
      // Last and remote tie at the winning physical — bump max logical.
      final int higher = lastLogical > remote.logical
          ? lastLogical
          : remote.logical;
      return higher + 1;
    } else if (newPhysical == lastPhysical) {
      // Last won — bump its logical.
      return lastLogical + 1;
    } else if (newPhysical == remote.physicalMs) {
      // Remote won — adopt its logical and bump.
      return remote.logical + 1;
    } else {
      // Wall won — fresh logical run.
      return 0;
    }
  }
}
