import 'package:clock_anchor/clock_anchor.dart';

/// A [TimeSource] that hands back prepared samples, or throws.
///
/// Lets the adoption rules be tested as a decision table — trust levels,
/// disagreements, precision — without any transport in the way.
class ScriptedTimeSource implements TimeSource {
  /// Each call to [sample] consumes one entry of [script]; an entry that is a
  /// [TimeSourceException] is thrown instead of returned.
  ScriptedTimeSource({
    required this.id,
    required this.trust,
    required List<Object> script,
  }) : _script = List<Object>.of(script);

  @override
  final String id;

  @override
  final TimeSourceTrust trust;

  final List<Object> _script;

  /// How many times [sample] has been called.
  int calls = 0;

  @override
  Future<TimeSample> sample() async {
    calls += 1;
    if (_script.isEmpty) {
      throw TimeSourceException(id, 'script exhausted');
    }
    final Object next = _script.removeAt(0);
    if (next is TimeSourceException) {
      throw next;
    }
    if (next is TimeSample) {
      return next;
    }
    throw StateError('script entry is neither a sample nor a failure');
  }
}
