import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';

/// FIFO queue with a single holder that serializes locker operations; a
/// transaction holds it for the whole body of `withTransaction`.
class OperationLane {
  final Queue<Completer<void>> _queue = Queue();

  bool _busy = false;

  /// Bumped by [invalidate], so a granted-but-not-resumed operation can detect
  /// via [isCurrent] that the locker was locked while it was waiting/running.
  int _generation = 0;

  bool get isBusy => _busy;

  int get generation => _generation;

  /// Completes when the lane becomes free, in FIFO order.
  Future<void> acquire() {
    if (!_busy) {
      _busy = true;

      return Future.value();
    }

    final ticket = Completer<void>();
    _queue.add(ticket);

    return ticket.future;
  }

  /// Releases the lane and hands it to the next waiter, if any.
  void release() {
    if (!_busy) {
      // Already discarded by [invalidate]: the holder is finishing up.
      return;
    }

    if (_queue.isEmpty) {
      _busy = false;

      return;
    }

    _queue.removeFirst().complete();
  }

  /// Completes all pending waiters with [error] without releasing the lane, so
  /// operations queued before `lock()`/`dispose()` fail instead of running.
  void failPending(Object error) {
    while (_queue.isNotEmpty) {
      _queue.removeFirst().completeError(error);
    }
  }

  /// Invalidates the lane: bumps the generation and fails pending waiters with
  /// [error]; called by `lock()`/`dispose()`/`eraseStorage()`.
  void invalidate(Object error) {
    _generation++;
    failPending(error);
  }

  /// Whether [generation] is still current, i.e. no [invalidate] since.
  bool isCurrent(int generation) => generation == _generation;

  @visibleForTesting
  int get pendingCount => _queue.length;
}
