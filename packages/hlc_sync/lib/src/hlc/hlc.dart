import '../errors.dart';

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

  /// Seed an HLC from a pre-HLC wall-clock-only timestamp. Used by
  /// DTO `fromJson` backward-compat reads when the persisted shape
  /// does not yet carry HLC fields.
  factory Hlc.fromLegacyWallClock(DateTime wallClock) => Hlc(
    physicalMs: wallClock.millisecondsSinceEpoch,
    logical: 0,
    nodeId: legacyNodeId,
  );

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
