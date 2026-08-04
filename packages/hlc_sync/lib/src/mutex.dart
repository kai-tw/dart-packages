import 'dart:async';
import 'dart:collection';

import 'errors.dart';

/// A FIFO mutex providing single-holder serial execution.
///
/// FIFO ordering across [lock] callers prevents starvation — a continuous
/// stream of new lockers can never indefinitely preempt an earlier waiter.
///
/// Not re-entrant: calling [lock] from inside a held region deadlocks.
///
/// Canonical usage: explicit acquire / try / finally release at the call
/// site so per-arm catch handlers remain colocated with the work they
/// recover.
///
///     await _mutex.lock();
///     try {
///       await doWork();
///     } on SomeException {
///       handleIt();
///       rethrow;
///     } finally {
///       _mutex.release();
///     }
class Mutex {
  Mutex();

  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();
  bool _isLocked = false;
  bool _isDisposed = false;

  bool get isLocked => _isLocked;

  bool get isDisposed => _isDisposed;

  /// Acquires the lock. Completes when the caller becomes the sole holder.
  /// Caller MUST call [release] when done — wrap the work in
  /// `try { … } finally { release(); }` so a thrown exception doesn't leak
  /// the lock.
  ///
  /// If the mutex has been [dispose]d, returns a future that errors with
  /// [MutexDisposedException]. Callers should catch this and silently
  /// abort (the mutex's owner is shutting down).
  Future<void> lock() {
    if (_isDisposed) {
      return Future<void>.error(const MutexDisposedException());
    }
    if (!_isLocked) {
      _isLocked = true;
      return Future<void>.value();
    }
    final Completer<void> waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  /// Releases the lock. Must be called by the current holder. Hands off
  /// directly to the head FIFO waiter if any — prevents queue-jumping by
  /// a `lock()` that races a release.
  void release() {
    assert(_isLocked, 'release() called without lock held');
    if (_waiters.isEmpty) {
      _isLocked = false;
      return;
    }
    // _isLocked stays true — atomic hand-off to next waiter.
    _waiters.removeFirst().complete();
  }

  /// Disposes the mutex. Idempotent. Fails every queued waiter with
  /// [MutexDisposedException] so callers awaiting [lock] do not hang
  /// indefinitely. Subsequent [lock] calls also fail with
  /// [MutexDisposedException]. Does not affect the current holder (if
  /// any) — the holder is expected to be the disposer itself (typical
  /// pattern: acquire → tear down state → dispose mutex in `finally`).
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    while (_waiters.isNotEmpty) {
      _waiters.removeFirst().completeError(const MutexDisposedException());
    }
  }
}
