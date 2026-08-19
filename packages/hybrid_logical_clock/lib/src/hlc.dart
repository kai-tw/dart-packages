import 'package:clock/clock.dart';

import 'errors.dart';

/// Hybrid Logical Clock value type.
///
/// Combines wall-clock physical time with a logical counter and a
/// device-stable node id so two writes from different devices in
/// the same physical millisecond have a deterministic, causality-
/// respecting order. Algorithm per Sergei Turukin, "Hybrid Logical
/// Clocks", 2017.
///
/// Compare order: physicalMs → logical → nodeId. The nodeId
/// tiebreak is deterministic; it does not imply that the lower
/// nodeId "wrote first" — only that the conflict resolution
/// across all participating devices agrees on the same winner.
///
/// Pre-HLC legacy writes are seeded via [Hlc.fromLegacyWallClock]
/// under the sentinel [legacyNodeId], which always orders below
/// any real device's writes at equal `(physicalMs, logical)` —
/// so a new write on any device beats a legacy write at the same
/// wall time.
class Hlc implements Comparable<Hlc> {
  const Hlc({
    required this.physicalMs,
    required this.logical,
    required this.nodeId,
  });

  /// Seed an HLC from a pre-HLC wall-clock-only timestamp **this device
  /// produced** — a receive time, a migration time, any locally-read
  /// anchor for records that have no HLC of their own.
  ///
  /// Unvalidated by design: the input is the local clock, so there is no
  /// trust boundary to police, and a gate keyed on `clock.now()` would only
  /// compare that clock against itself. For a timestamp that came out of
  /// bytes, use [Hlc.fromUntrustedWallClock] instead — the two are told
  /// apart only by where the caller got the `DateTime`.
  factory Hlc.fromLegacyWallClock(DateTime wallClock) => Hlc(
    physicalMs: wallClock.millisecondsSinceEpoch,
    logical: 0,
    nodeId: legacyNodeId,
  );

  /// Seed an HLC from a wall-clock timestamp that came **out of bytes** —
  /// a DTO's backward-compat fallback when the HLC fields are absent from
  /// the stored shape and only a plain timestamp is there to seed from.
  ///
  /// Applies the same [futureSkewCeilingMs] gate [HlcDto.toDomain] does,
  /// because this is the **other** way an [Hlc] gets built from untrusted
  /// bytes: omit the HLC fields entirely and let the plain timestamp seed
  /// it. Without this, the ceiling on the HLC fields is bypassed by simply
  /// not writing them — a stored `createdAt` of `+275760-09-13` parses
  /// cleanly into a stamp that outranks every later write forever.
  ///
  /// Like [HlcDto.toDomain] this rejects rather than clamps, and throws
  /// [HlcCorruptedException]. A caller that cannot afford to abort a whole
  /// batch should catch per record and skip that one.
  factory Hlc.fromUntrustedWallClock(DateTime wallClock) {
    final int physicalMs = wallClock.millisecondsSinceEpoch;
    final int nowMs = clock.now().millisecondsSinceEpoch;
    if (physicalMs > nowMs + futureSkewCeilingMs) {
      throw HlcCorruptedException(
        'Hlc.fromUntrustedWallClock: wall clock exceeds clock-now + 24h '
        '(nowMs=$nowMs, physicalMs=$physicalMs)',
      );
    }
    return Hlc(physicalMs: physicalMs, logical: 0, nodeId: legacyNodeId);
  }

  /// Decode the canonical string form `<physicalMs>-<logical>-<nodeId>`.
  /// nodeId may itself contain `-` (UUID v4 / legacy sentinel) so the
  /// decoder splits only on the first two delimiters.
  ///
  /// Exception messages deliberately omit the raw input — if the
  /// decoder is ever wired to a logger, the input may be
  /// attacker-supplied JSON from cloud storage, and interpolating it
  /// into an error payload would round-trip that payload to whatever
  /// crash reporter the app uses. The position-and-length summary is
  /// enough to diagnose the failure without leaking the bytes themselves.
  factory Hlc.decode(String s) {
    // Locate first two delimiters; the rest is the nodeId verbatim.
    final int len = s.length;
    final int firstDash = s.indexOf('-');
    if (firstDash <= 0) {
      throw HlcDecodeException(
        'Hlc.decode: missing first delimiter or empty physicalMs (len=$len)',
      );
    }
    final int secondDash = s.indexOf('-', firstDash + 1);
    if (secondDash <= firstDash + 1) {
      throw HlcDecodeException(
        'Hlc.decode: missing second delimiter or empty logical '
        '(len=$len, firstDash=$firstDash)',
      );
    }

    // Parse parts; reject negatives and empty nodeId.
    final int? physicalMs = int.tryParse(s.substring(0, firstDash));
    final int? logical = int.tryParse(s.substring(firstDash + 1, secondDash));
    final String nodeId = s.substring(secondDash + 1);
    if (physicalMs == null || physicalMs < 0) {
      throw HlcDecodeException(
        'Hlc.decode: physicalMs is not a non-negative integer '
        '(len=$len, firstDash=$firstDash)',
      );
    }
    if (logical == null || logical < 0) {
      throw HlcDecodeException(
        'Hlc.decode: logical is not a non-negative integer '
        '(len=$len, firstDash=$firstDash, secondDash=$secondDash)',
      );
    }
    if (nodeId.isEmpty) {
      throw HlcDecodeException(
        'Hlc.decode: nodeId is empty (len=$len, secondDash=$secondDash)',
      );
    }

    return Hlc(physicalMs: physicalMs, logical: logical, nodeId: nodeId);
  }

  /// [Hlc.decode], returning null instead of throwing on a malformed string.
  ///
  /// A stamp arriving from cloud storage malformed is an ordinary, expected
  /// condition rather than a fault, so a caller that means to tolerate it says
  /// so with a null check. Catching the exception instead would also swallow a
  /// defect in the decoder itself and report it as "this field has no stamp".
  static Hlc? tryDecode(String s) {
    try {
      return Hlc.decode(s);
    } on HlcDecodeException {
      return null;
    }
  }

  final int physicalMs;
  final int logical;
  final String nodeId;

  /// Sentinel node id stamped on legacy wall-clock-seeded HLCs.
  /// Always orders below any real device id at equal
  /// `(physicalMs, logical)` (lexicographic `String.compareTo`,
  /// real device ids are UUID v4 starting with `[0-9a-f]` so the
  /// `00000000-legacy-…` prefix is strictly less). Tracked here so
  /// reverse-references at conflict-resolution sites can branch on
  /// the legacy case without duplicating the string literal.
  static const String legacyNodeId = '00000000-legacy-pre-hlc-write';

  /// Tolerance ceiling for [physicalMs] over the reader's wall clock.
  /// Accommodates ordinary cross-device skew plus a manually advanced
  /// clock; beyond it the value is forged or corrupt.
  ///
  /// Lives on [Hlc] rather than on [HlcDto] because it must bound **every**
  /// construction of an [Hlc] from untrusted bytes, and there are two:
  /// [HlcDto.toDomain] and [Hlc.fromUntrustedWallClock]. A ceiling that
  /// guards only one is a ceiling with a documented way around it.
  ///
  /// This is a **bound, not an authentication**. Anything able to write the
  /// storage can still supply `now + 23h` and pass. What it removes is the
  /// unbounded case: [compareTo] orders on [physicalMs] first, so an
  /// uncapped far-future stamp outranks every real write *permanently*,
  /// which turns one bad row into a record that can never be corrected.
  static const int futureSkewCeilingMs = 24 * 60 * 60 * 1000;

  /// Canonical serialized form: `<physicalMs>-<logical>-<nodeId>`.
  String encode() => '$physicalMs-$logical-$nodeId';

  @override
  int compareTo(Hlc other) {
    final int p = physicalMs.compareTo(other.physicalMs);
    if (p != 0) {
      return p;
    }
    final int l = logical.compareTo(other.logical);
    if (l != 0) {
      return l;
    }
    return nodeId.compareTo(other.nodeId);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Hlc &&
          other.physicalMs == physicalMs &&
          other.logical == logical &&
          other.nodeId == nodeId;

  @override
  int get hashCode => Object.hash(physicalMs, logical, nodeId);

  @override
  String toString() => 'Hlc(${encode()})';
}
