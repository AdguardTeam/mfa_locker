import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';

/// FIFO queue with a single holder that serializes locker operations; a
/// transaction holds it for the whole body of `withTransaction`.
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
      // Already discarded by [failPending]: the holder is finishing up.
      return;
    }

    if (_waiters.isEmpty) {
      _busy = false;

      return;
    }

    _waiters.removeFirst().complete();
  }

  /// Completes all pending waiters with [error] without releasing the lane, so
  /// operations queued before `lock()`/`dispose()` fail instead of running.
  void failPending(Object error) {
    while (_waiters.isNotEmpty) {
      _waiters.removeFirst().completeError(error);
    }
  }

  @visibleForTesting
  int get pendingCount => _waiters.length;
}
