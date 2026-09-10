import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';

/// FIFO queue with a single holder used to serialize locker operations.
///
/// A transaction holds the lane from `beginTransaction` until `commit`/`abort`;
/// a standalone operation holds it for the duration of its execution. Waiting
/// never blocks the event loop, so callers simply await [acquire].
class OperationLane {
  final Queue<Completer<void>> _waiters = Queue();

  bool _busy = false;

  /// Whether the lane is currently held by an operation or a transaction.
  bool get isBusy => _busy;

  /// Completes when the lane becomes free, in FIFO order.
  Future<void> acquire() {
    if (!_busy) {
      _busy = true;

      return Future.value();
    }

    final ticket = Completer<void>();
    _waiters.add(ticket);

    return ticket.future;
  }

  /// Releases the lane and hands it to the next waiter, if any.
  void release() {
    if (!_busy) {
      // Nothing to release: the lane was already discarded by [failPending]
      // and the holder is finishing up.
      return;
    }

    if (_waiters.isEmpty) {
      _busy = false;

      return;
    }

    _waiters.removeFirst().complete();
  }

  /// Completes all pending waiters with [error] without releasing the lane.
  ///
  /// Used by `lock()`/`dispose()`: operations queued before the locker was
  /// locked must fail instead of running afterwards.
  void failPending(Object error) {
    while (_waiters.isNotEmpty) {
      _waiters.removeFirst().completeError(error);
    }
  }

  @visibleForTesting
  int get pendingCount => _waiters.length;
}
