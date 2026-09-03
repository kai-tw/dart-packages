import 'package:clock/clock.dart';

import 'clock_anchor_policy.dart';
import 'clock_integrity.dart';
import 'clock_integrity_report.dart';
import 'monotonic_ticks.dart';
import 'time_anchor.dart';
import 'time_confidence.dart';
import 'time_reading.dart';
import 'time_sample.dart';
import 'time_source.dart';
import 'time_source_exception.dart';
import 'time_source_trust.dart';

/// Holds the anchor, decides what may replace it, and answers what time it is.
///
/// Reading is synchronous and cheap — it is arithmetic over a monotonic tick
/// reading — so it is safe on any path, including one that stamps a record.
/// Acquiring an anchor is asynchronous and explicit: call [refresh] when the
/// app starts, when it returns to the foreground, and when connectivity comes
/// back.
///
/// The device's wall clock reaches exactly two places in here: the fallback
/// reading when nothing is anchored, and the discrepancy check that notices
/// it has moved. It never contributes to an anchored answer.
class ClockAnchorService {
  /// [deviceClock] must be the *raw* system clock. Do not pass the ambient
  /// `clock` when an [AnchoredClock] is installed with `withClock`: this
  /// service would then read itself.
  ClockAnchorService({
    required MonotonicTicks ticks,
    required ClockIntegrity integrity,
    ClockAnchorPolicy policy = const ClockAnchorPolicy(),
    List<TimeSource> sources = const <TimeSource>[],
    Clock deviceClock = const Clock(),
  }) : _ticks = ticks,
       _integrity = integrity,
       _policy = policy,
       _deviceClock = deviceClock,
       _sources = List<TimeSource>.unmodifiable(
         sources.toList()..sort(
           (TimeSource a, TimeSource b) =>
               b.trust.index.compareTo(a.trust.index),
         ),
       );

  final MonotonicTicks _ticks;
  final ClockIntegrity _integrity;
  final ClockAnchorPolicy _policy;
  final Clock _deviceClock;
  final List<TimeSource> _sources;

  final List<TimeSourceException> _lastRefreshFailures =
      <TimeSourceException>[];

  TimeAnchor? _anchor;
  Duration _lastIntegrityTicks = Duration.zero;
  Duration? _lastDisagreement;

  /// The anchor currently in force, if any.
  TimeAnchor? get anchor => _anchor;

  /// Rollback state, forwarded from the integrity check.
  ClockIntegrity get integrity => _integrity;

  /// Failures from the most recent [refresh], for logging. Cleared at the
  /// start of each refresh.
  List<TimeSourceException> get lastRefreshFailures =>
      List<TimeSourceException>.unmodifiable(_lastRefreshFailures);

  /// How far the most recent sample disagreed with the anchor in force when
  /// it arrived, or null if there was nothing to compare against.
  ///
  /// Diagnostic only — the adoption decision does not read it. Two sources
  /// disagreeing is worth an event; it is not, by itself, evidence about
  /// which one is wrong.
  Duration? get lastDisagreement => _lastDisagreement;

  /// The best available answer, with the confidence that qualifies it.
  TimeReading read() {
    final TimeAnchor? current = _anchor;
    if (current == null) {
      return _unanchoredReading();
    }
    return _anchoredReading(current);
  }

  /// [read] reduced to its instant, so this can be torn off as a
  /// `DateTime Function()` — which is what [AnchoredClock] hands to
  /// `package:clock`.
  DateTime now() => read().utc;

  /// This device's clock error right now: positive when the device is behind
  /// true time. Null when nothing is anchored, because there is then nothing
  /// to measure it against.
  Duration? get deviceOffset {
    final TimeAnchor? current = _anchor;
    if (current == null) {
      return null;
    }
    return current
        .timeAt(_ticks.elapsed)
        .difference(_deviceClock.now().toUtc());
  }

  /// Folds one observation in, and reports whether it became the new anchor.
  ///
  /// Adoption rules, in order:
  ///
  /// 1. A sample wider than `ClockAnchorPolicy.maxSampleUncertainty` is
  ///    dropped — it would replace a good estimate with a worse one.
  /// 2. With no anchor, or a stale one, any surviving sample is adopted.
  /// 3. Otherwise the sample must come from a source at least as trusted as
  ///    the one in force. A weaker source may not displace a stronger one
  ///    even when it disagrees, because the disagreement is exactly what a
  ///    weaker source is expected to be lying about.
  /// 4. At equal trust, the sample must also be no less precise than the
  ///    anchor has become. As the anchor ages this stops being a hurdle,
  ///    which is what makes refreshing self-correcting rather than a fight.
  bool observe(TimeSample sample) {
    if (sample.uncertainty > _policy.maxSampleUncertainty) {
      return false;
    }
    final TimeAnchor? current = _anchor;
    _lastDisagreement = current == null
        ? null
        : sample.remoteUtc.difference(current.timeAt(sample.ticksAtReceipt));
    if (current != null && !_shouldReplace(current, sample)) {
      return false;
    }
    _anchor = TimeAnchor.fromSample(sample);
    return true;
  }

  /// Samples every configured source, strongest first, and folds in what
  /// comes back. Returns how many samples were adopted.
  ///
  /// A source that throws [TimeSourceException] is recorded and skipped;
  /// anything else propagates, because a source failing in a way it did not
  /// declare is a defect rather than an outage.
  Future<int> refresh() async {
    _lastRefreshFailures.clear();
    int adopted = 0;
    for (final TimeSource source in _sources) {
      final TimeSample? sample = await _trySample(source);
      if (sample != null && observe(sample)) {
        adopted += 1;
      }
    }
    final TimeAnchor? current = _anchor;
    if (adopted > 0 && current != null) {
      await _integrity.reconcile(current, _ticks.elapsed, _deviceClock.now());
    }
    return adopted;
  }

  /// Looks at the device clock and updates the rollback watermark.
  ///
  /// Event-driven: startup, foreground, and before a decision that must fail
  /// closed. The monotonic advance since the previous call is supplied for
  /// you, which is what lets an implausible forward jump be told apart from
  /// time simply having passed.
  Future<ClockIntegrityReport> checkIntegrity() async {
    final Duration ticksNow = _ticks.elapsed;
    final Duration advance = ticksNow - _lastIntegrityTicks;
    _lastIntegrityTicks = ticksNow;
    return _integrity.observe(_deviceClock.now(), monotonicAdvance: advance);
  }

  TimeReading _unanchoredReading() => TimeReading(
    utc: _deviceClock.now(),
    confidence: _integrity.isRolledBack
        ? TimeConfidence.unknown
        : TimeConfidence.deviceOnly,
    uncertainty: _policy.unanchoredUncertainty,
  );

  TimeReading _anchoredReading(TimeAnchor current) {
    final Duration ticksNow = _ticks.elapsed;
    final Duration drift = current.discrepancyAt(
      ticksNow,
      _deviceClock.now(),
    );
    Duration uncertainty = current.uncertaintyAt(ticksNow, _policy.driftPpm);
    bool stale = current.ageAt(ticksNow) > _policy.maxAnchorAge;

    // Only a forward drift degrades the anchor. The wall clock running
    // *behind* the monotonic base is unambiguously a clock change and leaves
    // the anchor's arithmetic untouched — a user winding the phone back does
    // not cost this service its confidence. Running *ahead* may instead be
    // sleep the tick source did not count, in which case the anchor now lags
    // true time by up to that much, so it is carried as uncertainty rather
    // than silently ignored.
    if (drift > _policy.maxDiscrepancy) {
      stale = true;
      uncertainty += drift;
    }

    return TimeReading(
      utc: current.timeAt(ticksNow),
      confidence: stale ? TimeConfidence.staleAnchor : TimeConfidence.anchored,
      uncertainty: uncertainty,
    );
  }

  bool _shouldReplace(TimeAnchor current, TimeSample sample) {
    final Duration ticksNow = _ticks.elapsed;
    if (_isStale(current, ticksNow)) {
      return true;
    }
    if (!sample.trust.isAtLeast(current.trust)) {
      return false;
    }
    if (sample.trust != current.trust) {
      return true;
    }
    return sample.uncertainty <=
        current.uncertaintyAt(ticksNow, _policy.driftPpm);
  }

  bool _isStale(TimeAnchor current, Duration ticksNow) {
    if (current.ageAt(ticksNow) > _policy.maxAnchorAge) {
      return true;
    }
    return current.discrepancyAt(ticksNow, _deviceClock.now()) >
        _policy.maxDiscrepancy;
  }

  Future<TimeSample?> _trySample(TimeSource source) async {
    try {
      return await source.sample();
    } on TimeSourceException catch (error) {
      _lastRefreshFailures.add(error);
      return null;
    }
  }
}
