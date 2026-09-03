import 'package:clock_anchor/clock_anchor.dart';

/// A [WatermarkStore] that also counts writes, so a test can pin the
/// persistence granularity rather than only the value.
class RecordingWatermarkStore implements WatermarkStore {
  /// Optionally seeded, standing in for a value left by a previous run.
  RecordingWatermarkStore([this._value]);

  DateTime? _value;

  /// Every value written, in order.
  final List<DateTime> writes = <DateTime>[];

  @override
  Future<DateTime?> read() async => _value;

  @override
  Future<void> write(DateTime value) async {
    _value = value.toUtc();
    writes.add(value.toUtc());
  }
}
