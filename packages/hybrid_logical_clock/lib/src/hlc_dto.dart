import 'package:clock/clock.dart';

import 'hlc.dart';
import 'hlc_corrupted_exception.dart';

/// JSON wire format for [Hlc] embedded inside other DTOs.
///
/// Three structural fields rather than the single-string [Hlc.encode] form:
/// it keeps the wire format introspectable, and it lets a reader validate each
/// component before it ever becomes an [Hlc].
///
/// Written by hand rather than generated. This package has no build step, so
/// consumers never inherit a code generator's analyzer version window — which
/// matters more than the twenty lines it saves, because two apps sharing this
/// package would otherwise have to move their generator versions in lockstep.
class HlcDto {
  const HlcDto({
    required this.physicalMs,
    required this.logical,
    required this.nodeId,
  });

  /// Reads the wire form.
  ///
  /// Throws if a field is missing or of the wrong type. Deliberately strict:
  /// callers at a trust boundary are expected to catch, and a wrong type here
  /// means the value was not written by this package.
  factory HlcDto.fromJson(Map<String, dynamic> json) => HlcDto(
    physicalMs: json['physicalMs'] as int,
    logical: json['logical'] as int,
    nodeId: json['nodeId'] as String,
  );

  factory HlcDto.fromDomain(Hlc hlc) => HlcDto(
    physicalMs: hlc.physicalMs,
    logical: hlc.logical,
    nodeId: hlc.nodeId,
  );

  final int physicalMs;
  final int logical;
  final String nodeId;

  /// Hard cap on [logical]. The clock resets it to 0 whenever `physicalMs`
  /// advances, so reaching this would need millions of ticks inside a single
  /// wall-clock millisecond.
  static const int _logicalCap = 1 << 20;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'physicalMs': physicalMs,
    'logical': logical,
    'nodeId': nodeId,
  };

  /// Converts to the domain [Hlc], validating as it goes.
  ///
  /// This is the trust boundary. These bytes come from shared storage, so they
  /// are influenced by anything that can write there — including a device with
  /// a wrong or deliberately-set clock. An HLC far in the future would win
  /// every conflict forever, so it is rejected rather than clamped: clamping
  /// would silently accept a forged ordering.
  ///
  /// Cloud read paths catch this and skip the record; local reads let it
  /// propagate, because a corrupt local row is a bug rather than hostile input.
  ///
  /// The message carries only numbers. `nodeId` is attacker-influenced and is
  /// left out for the same reason [Hlc.decode] omits its input.
  Hlc toDomain() {
    final int nowMs = clock.now().millisecondsSinceEpoch;
    if (physicalMs > nowMs + Hlc.futureSkewCeilingMs) {
      throw HlcCorruptedException(
        'HlcDto.toDomain: physicalMs exceeds clock-now + 24h '
        '(nowMs=$nowMs, physicalMs=$physicalMs)',
      );
    }
    if (logical > _logicalCap) {
      throw HlcCorruptedException(
        'HlcDto.toDomain: logical exceeds cap 2^20 (logical=$logical)',
      );
    }
    return Hlc(physicalMs: physicalMs, logical: logical, nodeId: nodeId);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HlcDto &&
          other.physicalMs == physicalMs &&
          other.logical == logical &&
          other.nodeId == nodeId;

  @override
  int get hashCode => Object.hash(physicalMs, logical, nodeId);

  @override
  String toString() =>
      'HlcDto(physicalMs: $physicalMs, logical: $logical, nodeId: $nodeId)';
}
