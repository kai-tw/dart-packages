import '../hlc/hlc.dart';

/// What happened to one field across local, cloud, and the base.
enum FieldDivergence {
  /// Neither side touched it since the last sync.
  unchanged,

  /// Only local changed. Safe to take local without asking.
  localOnly,

  /// Only cloud changed. Safe to take cloud without asking.
  cloudOnly,

  /// Both changed since the base. This is the only case a human needs to see.
  concurrent,
}

/// Classifies one field, given its clock on each side.
///
/// Compares clocks rather than values, which is why the base needs no stored
/// payload — "did this side touch the field" is answerable from the stamp
/// alone.
///
/// A null [base] means the base never had a stamp for this field, so any side
/// that has one counts as having changed it.
FieldDivergence classifyField({
  required Hlc? local,
  required Hlc? cloud,
  required Hlc? base,
}) {
  final bool localChanged = _differs(local, base);
  final bool cloudChanged = _differs(cloud, base);

  if (!localChanged && !cloudChanged) {
    return FieldDivergence.unchanged;
  }
  if (localChanged && !cloudChanged) {
    return FieldDivergence.localOnly;
  }
  if (!localChanged && cloudChanged) {
    return FieldDivergence.cloudOnly;
  }

  // Both moved. If they landed on the same clock they are the same write
  // observed twice — one side already received the other's — not a conflict.
  if (local != null && cloud != null && local == cloud) {
    return FieldDivergence.unchanged;
  }
  return FieldDivergence.concurrent;
}

bool _differs(Hlc? side, Hlc? base) {
  if (side == null && base == null) {
    return false;
  }
  if (side == null || base == null) {
    return true;
  }
  return side != base;
}

/// Whether two clocks represent genuinely concurrent writes.
///
/// Deliberately conservative, and worth understanding before changing:
///
/// - Same node id → not concurrent. A device's own clock only moves forward,
///   so two stamps from one device are ordered by construction.
/// - Different node ids and different values → treated as concurrent, even
///   though one may well have happened after the other in real time.
///
/// An HLC cannot distinguish "B received A's write, then stamped its own"
/// from "B stamped independently, unaware of A" without vector clocks. Given
/// that ambiguity the safe direction is clear: a false positive costs the user
/// one dialog they could have been spared, while a false negative silently
/// discards someone's edit. This layer exists to prevent the second thing.
bool isConcurrent(Hlc a, Hlc b) {
  if (a.nodeId == b.nodeId) {
    return false;
  }
  return a.compareTo(b) != 0;
}
