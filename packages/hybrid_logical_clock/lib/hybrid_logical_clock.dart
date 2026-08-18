/// Hybrid logical clocks: timestamps two devices can order the same way
/// without agreeing on a wall clock.
///
/// A wall-clock timestamp cannot decide which of two offline edits came first
/// — one device's clock is simply wrong, and the edit it stamped loses forever
/// without anyone noticing. An [Hlc] pairs physical time with a logical
/// counter and a device-stable node id, so any two stamps compare
/// deterministically and every device reaches the same answer.
///
/// What is here:
///
/// * [Hlc] — the value type, with a total order and a canonical string form.
/// * [HlcClock] — emits stamps strictly greater than everything seen so far,
///   and merges a stamp observed from another device.
/// * [HlcDto] — the validating trust boundary for stamps read back out of
///   storage you do not control.
/// * [FieldHlcs] — a stamp per field of one record, as one JSON value, which
///   is what lets two devices editing different fields both keep their edit.
///
/// This package decides *ordering* and nothing else. It moves no bytes and
/// knows nothing about where records live — no transport, no merge engine, no
/// storage interface. A sync layer built on it supplies all of that itself.
library;

export 'src/errors.dart';
export 'src/field_hlcs.dart';
export 'src/hlc.dart';
export 'src/hlc_clock.dart';
export 'src/hlc_dto.dart';
