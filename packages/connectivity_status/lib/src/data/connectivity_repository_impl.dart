import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:log_system/log_system.dart';
import 'package:rxdart/rxdart.dart';

import '../domain/connectivity_repository.dart';
import '../domain/connectivity_status.dart';
import 'connectivity_data_source.dart';
import 'connectivity_data_source_impl.dart';
import 'connectivity_metered_data_source.dart';
import 'connectivity_metered_data_source_impl.dart';

class ConnectivityRepositoryImpl implements ConnectivityRepository {
  ConnectivityRepositoryImpl(this._source, this._meteredSource) {
    _seedAndForward();
  }

  /// The real platform wiring: [ConnectivityDataSourceImpl] and
  /// [ConnectivityMeteredDataSourceImpl] behind this repository.
  factory ConnectivityRepositoryImpl.platform() => ConnectivityRepositoryImpl(
    ConnectivityDataSourceImpl(),
    ConnectivityMeteredDataSourceImpl(),
  );

  /// The shared repository for a consumer with no DI framework of its own.
  /// Built once, on first access, via [ConnectivityRepositoryImpl.platform].
  ///
  /// A consumer using `get_it`, Riverpod, or anything else registers
  /// [ConnectivityRepositoryImpl.platform] with it instead of reading this
  /// getter — that keeps the app's own container the one source of truth
  /// for the instance, rather than two caches (this one and the
  /// container's) that could disagree.
  static ConnectivityRepository? _instance;
  static ConnectivityRepository get instance =>
      _instance ??= ConnectivityRepositoryImpl.platform();

  /// Drops the shared [instance]. Test seam — production code never calls
  /// it. Without this, the first test in a suite to touch [instance] would
  /// leave every later test sharing its repository (and its already-open
  /// platform-channel subscriptions).
  @visibleForTesting
  static void resetInstance() => _instance = null;

  final ConnectivityDataSource _source;
  final ConnectivityMeteredDataSource _meteredSource;
  // Seed synchronously at construction so the ValueStream's `.value`
  // contract holds from frame zero. The placeholder is `offline` — any
  // caller that races `_seedAndForward()`'s async first-status fetch sees
  // "offline" until the real status lands. Without the eager seed,
  // `_subject.value` throws on boot.
  final BehaviorSubject<ConnectivityStatus> _subject =
      BehaviorSubject<ConnectivityStatus>.seeded(ConnectivityStatus.offline);

  Future<void> _seedAndForward() async {
    // Seed the live status once so `.value` is real as early as possible,
    // falling back to the construction-time `offline` seed on a probe fault.
    try {
      _subject.add(await getStatus());
    } on PlatformException catch (e, s) {
      LogSystem.error(
        'Connectivity seed failed → fallback offline',
        error: e,
        stackTrace: s,
      );
      _subject.add(ConnectivityStatus.offline);
    }

    // Forward every later change, re-deriving status (incl. the metered probe)
    // per emission via asyncMap so emission order is preserved. asyncMap
    // serializes per event: a rare probe timeout (≤5s) back-pressures queued
    // events, so don't hang short-window time-sensitive logic off this stream.
    _source
        .observeConnectivity()
        .asyncMap(_statusFrom)
        .listen(_subject.add, onError: _onStreamError);
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    LogSystem.error(
      'Connectivity adapter stream emitted error → keeping last known status',
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  Future<ConnectivityStatus> getStatus() async {
    final List<ConnectivityResult> results = await _source.checkConnectivity();
    return _statusFrom(results);
  }

  @override
  ValueStream<ConnectivityStatus> observeStatus() => _subject.stream;

  Future<ConnectivityStatus> _statusFrom(
    List<ConnectivityResult> results,
  ) async {
    // Offline gate: with no active link there is nothing to meter — skip the
    // platform probe entirely.
    final bool isOnline = results.any(
      (ConnectivityResult r) => r != ConnectivityResult.none,
    );
    if (!isOnline) {
      return ConnectivityStatus.offline;
    }

    // Prefer the OS metered capability: it reflects the underlying transport
    // even when a VPN masks it, and flags a metered Wi-Fi hotspot — neither of
    // which the connection-type list alone can tell apart.
    final bool? metered = await _readMetered();
    if (metered != null) {
      return metered
          ? ConnectivityStatus.cellular
          : ConnectivityStatus.unmetered;
    }

    // Heuristic fallback when no platform signal is available (desktop / web)
    // or the probe faulted: only Wi-Fi / ethernet are confidently unmetered;
    // every other link (cellular, vpn, bluetooth, other) is treated as metered.
    final bool unmetered = results.any(
      (ConnectivityResult r) =>
          r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet,
    );
    return unmetered
        ? ConnectivityStatus.unmetered
        : ConnectivityStatus.cellular;
  }

  Future<bool?> _readMetered() async {
    try {
      return await _meteredSource.isActiveNetworkMetered();
    } on PlatformException catch (e, stackTrace) {
      // Mobile metered probe faulted (e.g. a missing ACCESS_NETWORK_STATE
      // surfacing as a SecurityException) → degrade to the type-list heuristic
      // rather than fail the download gate.
      LogSystem.warning(
        'Metered probe failed → heuristic fallback',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    } on TimeoutException catch (e, stackTrace) {
      // Probe outran its timeout → same heuristic fallback. Logged (not
      // debug) because the probe is an instant OS read, so a timeout is a
      // genuine anomaly: the gate is silently degrading to the heuristic.
      LogSystem.warning(
        'Metered probe timed out → heuristic fallback',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}
